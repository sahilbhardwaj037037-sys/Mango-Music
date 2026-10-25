import Foundation
import SQLite3
import Testing
@testable import MangoMusic

private struct TemporaryLibrary {
    let directory: URL
    let url: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MangoStoreTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        url = directory.appendingPathComponent("nested/library.sqlite3")
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

/// Raw SQL is confined to fixture creation/inspection, never the user's database.
private func fixtureSQL(_ url: URL, _ sql: String) throws {
    var db: OpaquePointer?
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw PersistenceError.unavailable }
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw PersistenceError.writeFailed }
}
private func scalar(_ url: URL, _ sql: String) throws -> Int {
    var db: OpaquePointer?, statement: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw PersistenceError.unavailable }
    defer { sqlite3_close(db) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw PersistenceError.invalidData }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw PersistenceError.invalidData }
    return Int(sqlite3_column_int64(statement, 0))
}

struct SQLitePersistenceTests {
    @Test func freshCreationReopeningAndBoundMetadata() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        let store = SQLiteLibraryStore(url: temp.url)
        #expect(try await store.load() == LibrarySnapshot())
        let song = Song(id: "youtube:abcdefghij0", title: "Robert'); DROP TABLE songs;-- 🎵", artist: "O'Connor", duration: 0, durationKnown: false)
        let favorite = FavoriteRecord(song: song, addedAt: Date(timeIntervalSince1970: 100))
        let history = HistoryEntry(song: song, playedAt: Date(timeIntervalSince1970: 200), playCount: 3)
        let entries = [QueueEntry(song: song), QueueEntry(song: song)]
        var snapshot = LibrarySnapshot(favorites: [favorite], history: [history], queue: entries, currentSong: song)
        snapshot.revision = try await store.save(snapshot, expecting: 0)
        await store.close()
        let reopened = SQLiteLibraryStore(url: temp.url)
        #expect(try await reopened.load() == snapshot)
        #expect(try scalar(temp.url, "PRAGMA user_version") == 2)
        #expect(try scalar(temp.url, "SELECT count(*) FROM songs") == 1)
        await reopened.close()
    }
    @Test func constraintsRollbackAndFavoriteDeduplication() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        let store = SQLiteLibraryStore(url: temp.url)
        _ = try await store.load()
        let favorite = FavoriteRecord(song: testSong(0), addedAt: Date(timeIntervalSince1970: 1000))
        var valid = LibrarySnapshot(favorites: [favorite], queue: [QueueEntry(song: testSong(1))])
        valid.revision = try await store.save(valid, expecting: 0)
        var duplicate = valid; duplicate.favorites.append(favorite); duplicate.queue.removeAll()
        await #expect(throws: PersistenceError.invalidData) { try await store.save(duplicate, expecting: 1) }
        #expect(try await store.load() == valid) // DELETEs and inserts must all roll back.
        var invalid = valid; invalid.queue = [QueueEntry(song: Song.samples[0])]
        await #expect(throws: PersistenceError.invalidData) { try await store.save(invalid, expecting: 1) }
        #expect(try await store.load() == valid)
        var cleared = LibrarySnapshot(); cleared.revision = try await store.save(cleared, expecting: 1)
        #expect(try await store.load() == cleared)
        await store.close()
    }
    @Test func queueOrderingIdentityRemovalAndClear() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        let store = SQLiteLibraryStore(url: temp.url)
        var snapshot = try await store.load()
        let first = QueueEntry(song: testSong(0)), second = QueueEntry(song: testSong(0)), third = QueueEntry(song: testSong(1))
        snapshot.queue = [third, first, second]
        snapshot.revision = try await store.save(snapshot, expecting: snapshot.revision)
        #expect(try await store.load().queue == [third, first, second])
        snapshot.queue.remove(at: 1)
        snapshot.revision = try await store.save(snapshot, expecting: snapshot.revision)
        #expect(try await store.load().queue == [third, second])
        snapshot.queue.removeAll()
        snapshot.revision = try await store.save(snapshot, expecting: snapshot.revision)
        #expect(try await store.load().queue.isEmpty)
        await store.close()
    }
    @Test func versionOneMigrationPreservesData() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        let store = SQLiteLibraryStore(url: temp.url)
        _ = try await store.load()
        let entry = HistoryEntry(song: testSong(0), playedAt: Date(timeIntervalSince1970: 1000))
        _ = try await store.save(LibrarySnapshot(history: [entry], queue: [QueueEntry(song: testSong(1))]), expecting: 0)
        await store.close()
        try fixtureSQL(temp.url, "DROP INDEX history_recent; ALTER TABLE history DROP COLUMN play_count; PRAGMA user_version=1;")
        let migrated = SQLiteLibraryStore(url: temp.url)
        let snapshot = try await migrated.load()
        #expect(snapshot.history == [entry]); #expect(snapshot.queue.first?.song == testSong(1))
        #expect(try scalar(temp.url, "PRAGMA user_version") == 2)
        await migrated.close()
    }
    @Test func futureUnknownAndFailedMigrationsPreserveFiles() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        try fixtureSQL(temp.url, "CREATE TABLE personal_data(value TEXT); INSERT INTO personal_data VALUES('preserve'); PRAGMA user_version=99;")
        let future = SQLiteLibraryStore(url: temp.url)
        await #expect(throws: PersistenceError.newerSchema) { try await future.load() }
        #expect(try scalar(temp.url, "SELECT count(*) FROM personal_data") == 1)
        await future.close()
        try fixtureSQL(temp.url, "PRAGMA user_version=0")
        let unknown = SQLiteLibraryStore(url: temp.url)
        await #expect(throws: PersistenceError.unrecognizedSchema) { try await unknown.load() }
        #expect(try scalar(temp.url, "SELECT count(*) FROM personal_data") == 1)
        await unknown.close()
        try fixtureSQL(temp.url, "CREATE TABLE history(video_id TEXT,entry_id TEXT,played_at REAL); PRAGMA user_version=1;")
        let broken = SQLiteLibraryStore(url: temp.url)
        await #expect(throws: PersistenceError.unrecognizedSchema) { try await broken.load() }
        #expect(try scalar(temp.url, "PRAGMA user_version") == 1)
        #expect(try scalar(temp.url, "SELECT count(*) FROM pragma_table_info('history') WHERE name='play_count'") == 0)
        #expect(try scalar(temp.url, "SELECT count(*) FROM personal_data") == 1)
        await broken.close()
    }
    @Test func corruptionReadOnlyAndUnavailablePaths() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        try FileManager.default.createDirectory(at: temp.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data("This is not a database; preserve these bytes".utf8)
        try bytes.write(to: temp.url)
        let corrupt = SQLiteLibraryStore(url: temp.url)
        await #expect(throws: PersistenceError.corrupt) { try await corrupt.load() }
        #expect(try Data(contentsOf: temp.url) == bytes)
        await corrupt.close()
        let validURL = temp.directory.appendingPathComponent("valid.sqlite3")
        let valid = SQLiteLibraryStore(url: validURL); _ = try await valid.load(); await valid.close()
        let readOnly = SQLiteLibraryStore(url: validURL, readOnly: true)
        #expect(try await readOnly.load().favorites.isEmpty)
        await #expect(throws: PersistenceError.writeFailed) { try await readOnly.save(LibrarySnapshot(favorites: [FavoriteRecord(song: testSong(0), addedAt: Date(timeIntervalSince1970: 1000))]), expecting: 0) }
        #expect(try await readOnly.load().favorites.isEmpty)
        await readOnly.close()
        let impossible = SQLiteLibraryStore(url: temp.url.appendingPathComponent("child.sqlite3"))
        await #expect(throws: (any Error).self) { try await impossible.load() }
        await impossible.close()
    }
    @Test func staleWritersCannotOverwriteAnotherInstance() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        let a = SQLiteLibraryStore(url: temp.url), b = SQLiteLibraryStore(url: temp.url)
        _ = try await a.load(); _ = try await b.load()
        _ = try await a.save(LibrarySnapshot(queue: [QueueEntry(song: testSong(0))]), expecting: 0)
        await #expect(throws: PersistenceError.conflict) { try await b.save(LibrarySnapshot(), expecting: 0) }
        #expect(try await b.load().queue.first?.song == testSong(0))
        await a.close(); await b.close()
        await #expect(throws: PersistenceError.closed) { try await a.load() }
    }
    @Test func busyDatabaseFailsWithoutLosingLastCommitAndCanRetry() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        let store = SQLiteLibraryStore(url: temp.url)
        _ = try await store.load()
        let original = LibrarySnapshot(queue: [QueueEntry(song: testSong(0))])
        _ = try await store.save(original, expecting: 0)
        var blocker: OpaquePointer?
        #expect(sqlite3_open(temp.url.path, &blocker) == SQLITE_OK)
        defer { sqlite3_close(blocker) }
        #expect(sqlite3_exec(blocker, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        let start = Date()
        await #expect(throws: PersistenceError.writeFailed) { try await store.save(LibrarySnapshot(), expecting: 1) }
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        #expect(try await store.load().queue == original.queue)
        #expect(try await store.save(LibrarySnapshot(), expecting: 1) == 2)
        await store.close()
    }

    @Test func historyOrderingAndCountsRoundTrip() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        let store = SQLiteLibraryStore(url: temp.url); _ = try await store.load()
        let old = HistoryEntry(song: testSong(0), playedAt: Date(timeIntervalSince1970: 100), playCount: 4)
        let recent = HistoryEntry(song: testSong(1), playedAt: Date(timeIntervalSince1970: 200), playCount: 2)
        _ = try await store.save(LibrarySnapshot(history: [old, recent]), expecting: 0)
        #expect(try await store.load().history == [recent, old])
        await store.close()
    }
}

private actor CountingResolver: AudioStreamResolving {
    var calls = 0
    func resolve(_ song: Song) -> URL { calls += 1; return URL(string: "https://example.com/audio")! }
    func count() -> Int { calls }
}
@MainActor
private final class ControlledPlayer: AudioPlaying {
    var onEvent: ((UUID, PlaybackEvent) -> Void)?
    var request = UUID()
    var loads = 0
    var shutdowns = 0
    func load(_ url: URL, request: UUID, volume: Double, paused: Bool) async throws {
        self.request = request; loads += 1; onEvent?(request, .loaded)
    }
    func emit(_ event: PlaybackEvent) { onEvent?(request, event) }
    func pause(_ paused: Bool) async throws { emit(.paused(paused)) }
    func seek(_ position: Double) async throws { emit(.position(position)) }
    func volume(_ value: Double) async throws { emit(.volume(value)) }
    func stop() async {}
    func interrupt() {}
    func shutdown() { shutdowns += 1 }
}
private actor SwitchableStore: LibraryPersisting {
    var data = LibrarySnapshot()
    var failingLoad = false
    var failingSave = false
    var saves = 0
    var delayMilliseconds = 0
    var closed = false
    func load() throws -> LibrarySnapshot { if failingLoad { throw PersistenceError.corrupt }; return data }
    func save(_ snapshot: LibrarySnapshot, expecting revision: Int) async throws -> Int {
        saves += 1
        if delayMilliseconds > 0 { try await Task.sleep(for: .milliseconds(delayMilliseconds)) }
        if failingSave { throw PersistenceError.writeFailed }
        data = snapshot; data.revision = revision + 1; return data.revision
    }
    func close() { closed = true }
    func failLoad(_ value: Bool) { failingLoad = value }
    func failSave(_ value: Bool) { failingSave = value }
    func saved() -> LibrarySnapshot { data }
    func didClose() -> Bool { closed }
    func delay(_ value: Int) { delayMilliseconds = value }
    func saveCount() -> Int { saves }
}

@MainActor
struct LibraryRestorationTests {
    func defaults() -> UserDefaults { UserDefaults(suiteName: "MangoPersistenceTests.\(UUID())")! }
    @Test func startupRestoresWithoutPlayerOrNetworkAndRecoversUnstartedQueue() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        let first = SQLiteLibraryStore(url: temp.url); _ = try await first.load()
        let pending = QueueEntry(song: testSong(0)), upcoming = QueueEntry(song: testSong(1))
        _ = try await first.save(LibrarySnapshot(favorites: [FavoriteRecord(song: testSong(1), addedAt: .now)],
                                               history: [HistoryEntry(song: testSong(1), playedAt: .now)], queue: [upcoming],
                                               currentSong: testSong(0), pendingQueueEntry: pending), expecting: 0)
        await first.close()
        let store = SQLiteLibraryStore(url: temp.url), resolver = CountingResolver(), player = ControlledPlayer()
        let library = MusicLibrary(defaults: defaults(), resolver: resolver, player: player, store: store)
        #expect(library.isRestoring); #expect(!library.canEditLibrary)
        await library.restorationTask?.value
        #expect(await library.flushPersistence())
        #expect(library.queue == [pending, upcoming]); #expect(library.favorites == [testSong(1)])
        #expect(library.history.count == 1); #expect(library.currentSong == testSong(0))
        #expect(!library.isPlaying); #expect(library.progress == 0); #expect(player.loads == 0)
        #expect(await resolver.count() == 0)
        #expect(await library.prepareToQuit())
        let again = SQLiteLibraryStore(url: temp.url)
        #expect(try await again.load().queue == [pending, upcoming])
        await again.close()
    }
    @Test func pendingRecoveryDoesNotDuplicateAnExistingQueueIdentity() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        let store = SQLiteLibraryStore(url: temp.url); _ = try await store.load()
        let first = QueueEntry(song: testSong(0)), intentionalDuplicate = QueueEntry(song: testSong(0))
        _ = try await store.save(LibrarySnapshot(queue: [first, intentionalDuplicate], currentSong: testSong(0), pendingQueueEntry: first), expecting: 0)
        await store.close()
        let library = MusicLibrary(defaults: defaults(), player: ControlledPlayer(), store: SQLiteLibraryStore(url: temp.url))
        await library.restorationTask?.value
        #expect(library.queue == [first, intentionalDuplicate])
        #expect(await library.prepareToQuit())
    }

    @Test func favoritesRapidActionsQueueEditsAndRestart() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        let store = SQLiteLibraryStore(url: temp.url)
        let library = MusicLibrary(defaults: defaults(), player: ControlledPlayer(), store: store)
        await library.restorationTask?.value
        for _ in 0..<51 { library.toggleFavorite(testSong(0)) }
        for _ in 0..<30 { library.enqueue(testSong(0)) }
        library.playNext(testSong(1))
        let entries = library.queue
        library.moveQueueEntry(entries[4].id, before: entries[0].id)
        library.removeQueueEntry(entries[3].id)
        let expected = library.queue
        #expect(library.hasUnsavedChanges)
        #expect(await library.prepareToQuit()) // Flush even when Cmd+Q follows the last edit immediately.
        let reopened = MusicLibrary(defaults: defaults(), player: ControlledPlayer(), store: SQLiteLibraryStore(url: temp.url))
        await reopened.restorationTask?.value
        #expect(reopened.favorites == [testSong(0)]); #expect(reopened.queue == expected)
        reopened.toggleFavorite(testSong(0)); reopened.clearQueue()
        #expect(await reopened.prepareToQuit())
        let final = SQLiteLibraryStore(url: temp.url)
        let data = try await final.load()
        #expect(data.favorites.isEmpty); #expect(data.queue.isEmpty)
        await final.close()
    }
    @Test func historyStartsOnClockNotSelectionAndRetryDoesNotDoubleCount() async throws {
        let store = SwitchableStore(), player = ControlledPlayer()
        let library = MusicLibrary(defaults: defaults(), resolver: CountingResolver(), player: player, store: store)
        await library.restorationTask?.value
        library.play(testSong(0)); await library.playbackTask?.value
        #expect(library.history.isEmpty) // file-loaded alone is insufficient
        player.emit(.failure("Failed before clock")); #expect(library.history.isEmpty)
        library.retryPlayback(); await library.playbackTask?.value
        player.emit(.position(1)); #expect(library.history.first?.playCount == 1)
        player.emit(.paused(true)); player.emit(.paused(false)); player.emit(.position(5))
        player.emit(.failure("Interrupted")); library.retryPlayback(); await library.playbackTask?.value
        player.emit(.position(1)); #expect(library.history.first?.playCount == 1)
        library.play(testSong(1)); await library.playbackTask?.value; player.emit(.position(1))
        library.play(testSong(0)); await library.playbackTask?.value; player.emit(.position(1))
        #expect(library.history.map(\.song.id) == [testSong(0).id, testSong(1).id])
        #expect(library.history.first?.playCount == 2)
        #expect(await library.flushPersistence()); #expect(await store.saved().history == library.history)
        #expect(await library.prepareToQuit())
    }
    @Test func failedQueuedSongAndStopPreserveUnplayedEntry() async throws {
        let store = SwitchableStore(), player = ControlledPlayer()
        let library = MusicLibrary(defaults: defaults(), resolver: CountingResolver(), player: player, store: store)
        await library.restorationTask?.value
        library.enqueue(testSong(0)); library.enqueue(testSong(1)); let entries = library.queue
        library.next(); await library.playbackTask?.value
        player.emit(.failure("Unavailable")); #expect(library.currentSong?.id == testSong(0).id)
        #expect(await library.flushPersistence()); #expect(await store.saved().pendingQueueEntry == entries[0])
        #expect(library.queue == [entries[1]])
        library.stop(); await library.playbackTask?.value
        #expect(library.queue == entries); #expect(await library.prepareToQuit())
    }
    @Test func queueCompletionAndDirectPlayPersistTheirDistinctSemantics() async throws {
        let store = SwitchableStore(), player = ControlledPlayer()
        let library = MusicLibrary(defaults: defaults(), resolver: CountingResolver(), player: player, store: store)
        await library.restorationTask?.value
        library.enqueue(testSong(1)); library.play(testSong(0)); await library.playbackTask?.value
        player.emit(.position(1)); let old = player.request
        player.emit(.ended); library.receive(old, .ended); await library.playbackTask?.value
        #expect(library.currentSong?.id == testSong(1).id); #expect(library.queue.isEmpty)
        player.emit(.position(1)); #expect(await library.flushPersistence())
        #expect(await store.saved().pendingQueueEntry == nil)
        player.emit(.ended); #expect(!library.isPlaying); #expect(await library.prepareToQuit())
        let reopenedPlayer = ControlledPlayer()
        let restored = MusicLibrary(defaults: defaults(), player: reopenedPlayer, store: store)
        await restored.restorationTask?.value
        #expect(restored.queue.isEmpty); #expect(restored.currentSong?.id == testSong(1).id)
        #expect(reopenedPlayer.loads == 0); #expect(!restored.isPlaying)
    }
    @Test func loadFailureBlocksEditsAndRetryDoesNotEraseExistingState() async {
        let store = SwitchableStore(); await store.failLoad(true)
        let library = MusicLibrary(defaults: defaults(), player: ControlledPlayer(), store: store)
        await library.restorationTask?.value
        #expect(library.persistenceError != nil); #expect(!library.canEditLibrary)
        library.enqueue(testSong(0)); library.toggleFavorite(testSong(0))
        #expect(library.queue.isEmpty); #expect(library.favoriteIDs.isEmpty)
        await store.failLoad(false); library.retryPersistence(); await library.restorationTask?.value
        #expect(library.canEditLibrary); #expect(library.persistenceError == nil)
        #expect(await library.prepareToQuit())
    }
    @Test func writeFailureIsVisibleQuitIsCancelledAndRetryCanSave() async {
        let store = SwitchableStore(), player = ControlledPlayer()
        let library = MusicLibrary(defaults: defaults(), player: player, store: store)
        await library.restorationTask?.value
        await store.failSave(true)
        library.toggleFavorite(testSong(0)); await library.persistenceTask?.value
        #expect(library.hasUnsavedChanges); #expect(library.persistenceError != nil)
        #expect(await store.saved().favorites.isEmpty)
        #expect(!(await library.prepareToQuit()))
        #expect(!library.isClosing); #expect(!(await store.didClose())); #expect(player.shutdowns == 0)
        await store.failSave(false); library.retryPersistence()
        #expect(await library.flushPersistence()); #expect(!library.hasUnsavedChanges); #expect(library.persistenceError == nil)
        #expect(await store.saved().favorites.map(\.song) == [testSong(0)])
        #expect(await library.prepareToQuit()); #expect(await store.didClose()); #expect(player.shutdowns == 1)
    }
    @Test func restoredPlayConsumesRecoveryOnceAndExplicitReplayCountsAgain() async throws {
        let store = SwitchableStore(), player = ControlledPlayer()
        let pending = QueueEntry(song: testSong(0))
        _ = try await store.save(LibrarySnapshot(queue: [pending], currentSong: testSong(0), pendingQueueEntry: pending), expecting: 0)
        let library = MusicLibrary(defaults: defaults(), resolver: CountingResolver(), player: player, store: store)
        await library.restorationTask?.value
        library.togglePlayback(); await library.playbackTask?.value
        #expect(library.queue.isEmpty)
        player.emit(.position(1)); player.emit(.ended)
        #expect(!library.isPlaying); #expect(library.history.first?.playCount == 1)
        library.togglePlayback(); await library.playbackTask?.value; player.emit(.position(1))
        #expect(library.history.first?.playCount == 2)
        #expect(library.queue.isEmpty)
        #expect(await library.prepareToQuit())
    }
    @Test func removingRecoveredUpcomingItemHonorsTheUsersRemoval() async throws {
        let store = SwitchableStore(), player = ControlledPlayer()
        let pending = QueueEntry(song: testSong(0))
        _ = try await store.save(LibrarySnapshot(queue: [pending], currentSong: testSong(0), pendingQueueEntry: pending), expecting: 0)
        let library = MusicLibrary(defaults: defaults(), player: player, store: store)
        await library.restorationTask?.value
        library.removeQueueEntry(pending.id)
        #expect(await library.prepareToQuit())
        #expect(await store.saved().queue.isEmpty)
        #expect(await store.saved().pendingQueueEntry == nil)
    }

    @Test func editsDuringInflightSaveAreCoalescedWithoutLoss() async throws {
        let store = SwitchableStore()
        await store.delay(50)
        let library = MusicLibrary(defaults: defaults(), player: ControlledPlayer(), store: store)
        await library.restorationTask?.value
        library.enqueue(testSong(0))
        while await store.saveCount() == 0 { await Task.yield() }
        library.enqueue(testSong(1)); library.toggleFavorite(testSong(2)); library.playNext(testSong(3))
        let expected = library.queue
        #expect(await library.flushPersistence())
        #expect(await store.saved().queue == expected)
        #expect(await store.saved().favorites.map(\.song) == [testSong(2)])
        #expect(await store.saveCount() == 2)
        #expect(await library.prepareToQuit())
    }
    @Test func startedQueuedTrackStaysConsumedAcrossRealDatabaseRestart() async throws {
        let temp = try TemporaryLibrary(); defer { temp.remove() }
        let store = SQLiteLibraryStore(url: temp.url), player = ControlledPlayer()
        let library = MusicLibrary(defaults: defaults(), resolver: CountingResolver(), player: player, store: store)
        await library.restorationTask?.value
        library.enqueue(testSong(0)); library.enqueue(testSong(1)); let remaining = library.queue[1]
        library.next(); await library.playbackTask?.value; player.emit(.position(1))
        #expect(await library.prepareToQuit())
        let nextPlayer = ControlledPlayer(), resolver = CountingResolver()
        let restored = MusicLibrary(defaults: defaults(), resolver: resolver, player: nextPlayer, store: SQLiteLibraryStore(url: temp.url))
        await restored.restorationTask?.value
        #expect(restored.queue == [remaining]); #expect(restored.currentSong?.id == testSong(0).id)
        #expect(restored.history.first?.playCount == 1); #expect(!restored.isPlaying)
        #expect(nextPlayer.loads == 0); #expect(await resolver.count() == 0)
        #expect(await restored.prepareToQuit())
    }
    @Test func unchangedLibraryCanQuitWithoutAttemptingAnUnnecessaryWrite() async {
        let store = SwitchableStore(), player = ControlledPlayer()
        let library = MusicLibrary(defaults: defaults(), player: player, store: store)
        await library.restorationTask?.value
        await store.failSave(true)
        #expect(await library.prepareToQuit())
        #expect(await store.saveCount() == 0)
        #expect(library.persistenceError == nil)
        #expect(player.shutdowns == 1)
    }

    @Test func settingsRestoreValidateAndClamp() {
        let prefs = defaults()
        let player = ControlledPlayer()
        let first = MusicLibrary(defaults: prefs, player: player)
        #expect(first.volume == 0.7); #expect(first.sidebarVisible)
        first.setVolume(0.23); first.toggleSidebar()
        let again = MusicLibrary(defaults: prefs, player: ControlledPlayer())
        #expect(again.volume == 0.23); #expect(!again.sidebarVisible)
        prefs.set(2.5, forKey: "volume"); #expect(MusicLibrary(defaults: prefs).volume == 1)
        prefs.set(-2, forKey: "volume"); #expect(MusicLibrary(defaults: prefs).volume == 0)
        prefs.set("invalid", forKey: "volume"); #expect(MusicLibrary(defaults: prefs).volume == 0.7)
        prefs.set(true, forKey: "volume"); #expect(MusicLibrary(defaults: prefs).volume == 0.7)
        prefs.set(Double.infinity, forKey: "volume"); #expect(MusicLibrary(defaults: prefs).volume == 0.7)
        prefs.set("false", forKey: "sidebarVisible"); #expect(MusicLibrary(defaults: prefs).sidebarVisible)
        first.setVolume(.nan); #expect(first.volume == 0.23)
        #expect(player.loads == 0)
    }
}
