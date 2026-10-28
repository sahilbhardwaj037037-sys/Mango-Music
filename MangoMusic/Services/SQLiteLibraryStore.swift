import Foundation
import SQLite3

/// All SQLite handles/statements are confined to this actor, never to SwiftUI's main actor.
actor SQLiteLibraryStore: LibraryPersisting {
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MangoMusic", isDirectory: true).appendingPathComponent("library.sqlite3")
    }
    let url: URL
    private let readOnly: Bool
    private var database: LibraryDatabase?
    private var closed = false
    init(url: URL = SQLiteLibraryStore.defaultURL, readOnly: Bool = false) {
        self.url = url; self.readOnly = readOnly
    }
    private func connection() throws -> LibraryDatabase {
        guard !closed else { throw PersistenceError.closed }
        if let database { return database }
        let opened = try LibraryDatabase(url: url, readOnly: readOnly)
        database = opened
        return opened
    }
    func load() throws -> LibrarySnapshot { try connection().load() }
    func save(_ snapshot: LibrarySnapshot, expecting revision: Int) throws -> Int {
        try connection().save(snapshot, expecting: revision)
    }
    func close() { database = nil; closed = true }
}

private enum SQLValue: Equatable {
    case text(String), integer(Int), real(Double), null
    var text: String? { if case .text(let value) = self { value } else { nil } }
    var integer: Int? { if case .integer(let value) = self { value } else { nil } }
    var number: Double? {
        switch self { case .real(let v): v; case .integer(let v): Double(v); default: nil }
    }
}

private final class LibraryDatabase {
    private var handle: OpaquePointer?
    private var operationDeadline = Date.distantFuture
    private let readOnly: Bool
    init(url: URL, readOnly: Bool) throws {
        self.readOnly = readOnly
        do {
            if !readOnly {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            }
            let existed = FileManager.default.fileExists(atPath: url.path)
            let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX
            guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else { throw PersistenceError.unavailable }
            sqlite3_extended_result_codes(handle, 1)
            sqlite3_busy_timeout(handle, 250)
            if !existed && !readOnly { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
            sqlite3_progress_handler(handle, 1000, { context in
                guard let context else { return 0 }
                let owner = Unmanaged<LibraryDatabase>.fromOpaque(context).takeUnretainedValue()
                return Date() > owner.operationDeadline ? 1 : 0
            }, Unmanaged.passUnretained(self).toOpaque())
            operationDeadline = Date().addingTimeInterval(3)
            guard try rows("PRAGMA quick_check").first?.first?.text == "ok" else { throw PersistenceError.corrupt }
            try execute("PRAGMA foreign_keys = ON")
            try migrate()
            guard try rows("PRAGMA foreign_key_check").isEmpty else { throw PersistenceError.corrupt }
            if !readOnly {
                _ = try rows("PRAGMA journal_mode = WAL")
                try execute("PRAGMA synchronous = FULL")
            }
            operationDeadline = .distantFuture
        } catch {
            if let handle { sqlite3_close_v2(handle) }; handle = nil
            throw (error as? PersistenceError) ?? .unavailable
        }
    }
    deinit { if let handle { sqlite3_progress_handler(handle, 0, nil, nil); sqlite3_close_v2(handle) } }

    private func failure(_ code: Int32) -> PersistenceError {
        switch code & 0xff {
        case SQLITE_CORRUPT, SQLITE_NOTADB: .corrupt
        case SQLITE_CONSTRAINT: .invalidData
        default: .writeFailed
        }
    }
    private func statement(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var pointer: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &pointer, nil)
        guard code == SQLITE_OK, let pointer else { throw failure(code) }
        do {
            guard sqlite3_bind_parameter_count(pointer) == values.count else { throw PersistenceError.invalidData }
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1), result: Int32
                switch value {
                case .text(let string):
                    result = string.withCString { sqlite3_bind_text(pointer, index, $0, Int32(string.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                case .integer(let number): result = sqlite3_bind_int64(pointer, index, sqlite3_int64(number))
                case .real(let number): result = sqlite3_bind_double(pointer, index, number)
                case .null: result = sqlite3_bind_null(pointer, index)
                }
                guard result == SQLITE_OK else { throw failure(result) }
            }
            return pointer
        } catch { sqlite3_finalize(pointer); throw error }
    }
    private func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        let pointer = try statement(sql, values); defer { sqlite3_finalize(pointer) }
        let result = sqlite3_step(pointer)
        guard result == SQLITE_DONE else { throw failure(result) }
    }
    private func rows(_ sql: String, _ values: [SQLValue] = []) throws -> [[SQLValue]] {
        let pointer = try statement(sql, values); defer { sqlite3_finalize(pointer) }
        var result: [[SQLValue]] = []
        while true {
            let code = sqlite3_step(pointer)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW else { throw failure(code) }
            var row: [SQLValue] = []
            for column in 0..<sqlite3_column_count(pointer) {
                switch sqlite3_column_type(pointer, column) {
                case SQLITE_INTEGER: row.append(.integer(Int(sqlite3_column_int64(pointer, column))))
                case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(pointer, column)))
                case SQLITE_TEXT:
                    guard let bytes = sqlite3_column_text(pointer, column) else { throw PersistenceError.invalidData }
                    let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(pointer, column)))
                    guard let value = String(data: data, encoding: .utf8) else { throw PersistenceError.invalidData }
                    row.append(.text(value))
                case SQLITE_NULL: row.append(.null)
                default: throw PersistenceError.invalidData
                }
            }
            result.append(row)
        }
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let value = try body(); try execute("COMMIT"); return value }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func migrate() throws {
        let version = try rows("PRAGMA user_version").first?.first?.integer ?? -1
        guard version <= 2 else { throw PersistenceError.newerSchema }
        guard version >= 0 else { throw PersistenceError.unrecognizedSchema }
        if version == 2 { try verifySchema(); return }
        guard !readOnly else { throw PersistenceError.writeFailed }
        try transaction {
            if version == 0 {
                guard try rows("SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").isEmpty else {
                    throw PersistenceError.unrecognizedSchema
                }
                try execute("""
                    CREATE TABLE songs (
                      video_id TEXT PRIMARY KEY NOT NULL CHECK(length(video_id)=11 AND video_id NOT GLOB '*[^A-Za-z0-9_-]*'),
                      title TEXT NOT NULL CHECK(length(title)>0), artist TEXT NOT NULL,
                      duration REAL CHECK(duration IS NULL OR (duration>=0 AND duration<=31536000)))
                    """)
                try execute("CREATE TABLE favorites (video_id TEXT PRIMARY KEY NOT NULL REFERENCES songs(video_id), added_at REAL NOT NULL)")
                try execute("CREATE TABLE history (video_id TEXT PRIMARY KEY NOT NULL REFERENCES songs(video_id), entry_id TEXT UNIQUE NOT NULL, played_at REAL NOT NULL)")
                try execute("CREATE TABLE queue (entry_id TEXT PRIMARY KEY NOT NULL, video_id TEXT NOT NULL REFERENCES songs(video_id), position INTEGER UNIQUE NOT NULL CHECK(position>=0))")
                try execute("""
                    CREATE TABLE session (id INTEGER PRIMARY KEY CHECK(id=1), current_video_id TEXT REFERENCES songs(video_id),
                      pending_entry_id TEXT, pending_video_id TEXT REFERENCES songs(video_id), revision INTEGER NOT NULL DEFAULT 0 CHECK(revision>=0),
                      CHECK((pending_entry_id IS NULL)=(pending_video_id IS NULL)))
                    """)
                try execute("INSERT INTO session(id) VALUES(1)")
                try execute("PRAGMA user_version = 1")
            }
            // Version 1 -> 2 preserves all rows and assigns existing history a first play.
            try execute("ALTER TABLE history ADD COLUMN play_count INTEGER NOT NULL DEFAULT 1 CHECK(play_count>0)")
            try execute("CREATE INDEX history_recent ON history(played_at DESC, video_id)")
            try execute("PRAGMA user_version = 2")
            try verifySchema()
        }
    }
    private func verifySchema() throws {
        do {
            _ = try rows("SELECT video_id,title,artist,duration FROM songs LIMIT 0")
            _ = try rows("SELECT video_id,added_at FROM favorites LIMIT 0")
            _ = try rows("SELECT video_id,entry_id,played_at,play_count FROM history LIMIT 0")
            _ = try rows("SELECT entry_id,video_id,position FROM queue LIMIT 0")
            guard try rows("SELECT id FROM session WHERE id=1").count == 1 else { throw PersistenceError.unrecognizedSchema }
            _ = try rows("SELECT current_video_id,pending_entry_id,pending_video_id,revision FROM session LIMIT 0")
        } catch { throw PersistenceError.unrecognizedSchema }
    }
    private func videoID(_ song: Song) throws -> String {
        guard let id = try? YouTubeVideoID.validate(song.id), !song.title.isEmpty,
              song.title.utf8.count <= 40_000, song.artist.utf8.count <= 40_000,
              !song.title.contains("\0"), !song.artist.contains("\0"),
              !song.durationKnown || (song.duration.isFinite && (0...31_536_000).contains(song.duration)) else { throw PersistenceError.invalidData }
        return id
    }
    func load() throws -> LibrarySnapshot {
        operationDeadline = Date().addingTimeInterval(3); defer { operationDeadline = .distantFuture }
        // A read transaction gives all restored entities the same database snapshot.
        try execute("BEGIN")
        do {
            var songs: [String: Song] = [:]
            for row in try rows("SELECT video_id,title,artist,duration FROM songs") {
                guard let id = row[0].text, let title = row[1].text, let artist = row[2].text else { throw PersistenceError.invalidData }
                guard row[3] == .null || row[3].number != nil else { throw PersistenceError.invalidData }
                let song = Song(id: "youtube:\(id)", title: title, artist: artist, duration: row[3].number ?? 0, durationKnown: row[3] != .null)
                _ = try videoID(song); songs[id] = song
            }
            func song(_ value: SQLValue) throws -> Song {
                guard let id = value.text, let song = songs[id] else { throw PersistenceError.invalidData }; return song
            }
            func date(_ value: SQLValue) throws -> Date {
                guard let seconds = value.number, seconds.isFinite else { throw PersistenceError.invalidData }
                return Date(timeIntervalSince1970: seconds)
            }
            var snapshot = LibrarySnapshot()
            snapshot.favorites = try rows("SELECT video_id,added_at FROM favorites ORDER BY video_id").map { try FavoriteRecord(song: song($0[0]), addedAt: date($0[1])) }
            snapshot.history = try rows("SELECT video_id,entry_id,played_at,play_count FROM history ORDER BY played_at DESC,video_id").map {
                guard let id = $0[1].text.flatMap(UUID.init(uuidString:)), let count = $0[3].integer, count > 0 else { throw PersistenceError.invalidData }
                return try HistoryEntry(id: id, song: song($0[0]), playedAt: date($0[2]), playCount: count)
            }
            snapshot.queue = try rows("SELECT entry_id,video_id,position FROM queue ORDER BY position").enumerated().map { index, row in
                guard let id = row[0].text.flatMap(UUID.init(uuidString:)), row[2].integer == index else { throw PersistenceError.invalidData }
                return try QueueEntry(id: id, song: song(row[1]))
            }
            guard let state = try rows("SELECT current_video_id,pending_entry_id,pending_video_id,revision FROM session WHERE id=1").first,
                  let revision = state[3].integer, revision >= 0 else { throw PersistenceError.invalidData }
            snapshot.revision = revision
            if state[0] != .null { snapshot.currentSong = try song(state[0]) }
            if state[1] != .null {
                guard let id = state[1].text.flatMap(UUID.init(uuidString:)) else { throw PersistenceError.invalidData }
                snapshot.pendingQueueEntry = try QueueEntry(id: id, song: song(state[2]))
                guard snapshot.pendingQueueEntry?.song.id == snapshot.currentSong?.id else { throw PersistenceError.invalidData }
            }
            guard Set(snapshot.favorites.map { $0.song.id }).count == snapshot.favorites.count,
                  Set(snapshot.history.map { $0.song.id }).count == snapshot.history.count,
                  Set(snapshot.queue.map(\.id)).count == snapshot.queue.count else { throw PersistenceError.invalidData }
            if let pending = snapshot.pendingQueueEntry, let existing = snapshot.queue.first(where: { $0.id == pending.id }) {
                guard existing.song.id == pending.song.id else { throw PersistenceError.invalidData }
            }
            try execute("COMMIT"); return snapshot
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func save(_ snapshot: LibrarySnapshot, expecting revision: Int) throws -> Int {
        operationDeadline = Date().addingTimeInterval(3); defer { operationDeadline = .distantFuture }
        guard snapshot.queue.count <= 10_000, snapshot.favorites.count <= 10_000,
              revision >= 0, revision < Int.max,
              snapshot.pendingQueueEntry == nil || snapshot.pendingQueueEntry?.song.id == snapshot.currentSong?.id else { throw PersistenceError.invalidData }
        return try transaction {
            guard try rows("SELECT revision FROM session WHERE id=1").first?.first?.integer == revision else { throw PersistenceError.conflict }
            var songs = snapshot.favorites.map(\.song) + snapshot.history.map(\.song) + snapshot.queue.map(\.song)
            if let pending = snapshot.pendingQueueEntry { songs.append(pending.song) }
            if let current = snapshot.currentSong { songs.append(current) }
            for song in songs {
                let id = try videoID(song)
                try execute("""
                    INSERT INTO songs(video_id,title,artist,duration) VALUES(?,?,?,?)
                    ON CONFLICT(video_id) DO UPDATE SET title=excluded.title, artist=excluded.artist, duration=COALESCE(excluded.duration,songs.duration)
                    """, [.text(id), .text(song.title), .text(song.artist), song.durationKnown ? .real(song.duration) : .null])
            }
            try execute("DELETE FROM favorites"); try execute("DELETE FROM history"); try execute("DELETE FROM queue")
            for record in snapshot.favorites {
                guard record.addedAt.timeIntervalSince1970.isFinite else { throw PersistenceError.invalidData }
                try execute("INSERT INTO favorites(video_id,added_at) VALUES(?,?)", [.text(try videoID(record.song)), .real(record.addedAt.timeIntervalSince1970)])
            }
            for entry in snapshot.history {
                guard entry.playCount > 0, entry.playedAt.timeIntervalSince1970.isFinite else { throw PersistenceError.invalidData }
                try execute("INSERT INTO history(video_id,entry_id,played_at,play_count) VALUES(?,?,?,?)",
                            [.text(try videoID(entry.song)), .text(entry.id.uuidString), .real(entry.playedAt.timeIntervalSince1970), .integer(entry.playCount)])
            }
            for (position, entry) in snapshot.queue.enumerated() {
                try execute("INSERT INTO queue(entry_id,video_id,position) VALUES(?,?,?)", [.text(entry.id.uuidString), .text(try videoID(entry.song)), .integer(position)])
            }
            try execute("UPDATE session SET current_video_id=?, pending_entry_id=?, pending_video_id=?, revision=? WHERE id=1", [
                try snapshot.currentSong.map { .text(try videoID($0)) } ?? .null,
                snapshot.pendingQueueEntry.map { .text($0.id.uuidString) } ?? .null,
                try snapshot.pendingQueueEntry.map { .text(try videoID($0.song)) } ?? .null,
                .integer(revision + 1)])
            try execute("""
                DELETE FROM songs WHERE video_id NOT IN (SELECT video_id FROM favorites UNION SELECT video_id FROM history UNION SELECT video_id FROM queue)
                AND video_id NOT IN (SELECT current_video_id FROM session WHERE current_video_id IS NOT NULL)
                AND video_id NOT IN (SELECT pending_video_id FROM session WHERE pending_video_id IS NOT NULL)
                """)
            return revision + 1
        }
    }
}
