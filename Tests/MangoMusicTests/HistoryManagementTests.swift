import Foundation
import Testing
@testable import MangoMusic

private var historyNow: Date { Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)) }

private func historySong(_ index: Int) -> Song {
    Song(id: "youtube:" + String(format: "%011d", index), title: "History \(index)", artist: "Fixture", duration: 100)
}

@MainActor
private final class HistoryFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MangoHistory-\(UUID())")
    let suite = "MangoHistoryTests.\(UUID())"
    let defaults: UserDefaults
    var url: URL { directory.appendingPathComponent("library.sqlite3") }
    init() { defaults = UserDefaults(suiteName: suite)! }
    func seed(_ snapshot: LibrarySnapshot) async throws {
        let store = SQLiteLibraryStore(url: url)
        _ = try await store.load()
        _ = try await store.save(snapshot, expecting: 0)
        await store.close()
    }
    func library(player: FixturePlayer = FixturePlayer()) -> MusicLibrary {
        MusicLibrary(defaults: defaults, resolver: FixtureResolver(), player: player, store: SQLiteLibraryStore(url: url))
    }
    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
struct HistoryManagementTests {
    @Test func deletingOneEntryPersistsAndPreservesPlaybackCollections() async throws {
        let fixture = HistoryFixture(); defer { fixture.remove() }
        let rows = (0..<3).map { HistoryEntry(song: historySong($0), playedAt: historyNow.addingTimeInterval(-Double($0))) }
        let favorite = FavoriteRecord(song: historySong(0), addedAt: historyNow)
        let queued = QueueEntry(song: historySong(2))
        try await fixture.seed(LibrarySnapshot(favorites: [favorite], history: rows, queue: [queued]))
        let player = FixturePlayer(), library = fixture.library(player: player)
        await library.restorationTask?.value
        library.playFavorites(); await library.playbackTask?.value
        let sequence = library.favoritesSequence, generation = library.mediaPlaybackSnapshot.generation
        let selected = try #require(library.history.first(where: { $0.song.id == historySong(0).id }))
        library.deleteHistoryEntry(selected.id)
        #expect(library.history.map(\.id) == [rows[1].id, rows[2].id])
        #expect(library.isPlaying); #expect(library.mediaPlaybackSnapshot.generation == generation)
        #expect(library.favoritesSequence == sequence); #expect(library.queue == [queued])
        #expect(library.favorites == [favorite.song])
        player.emit(.position(10)) // Deletion must not reinsert the same active playback attempt.
        #expect(library.history.count == 2)
        library.deleteHistoryEntry(UUID())
        #expect(await library.prepareToQuit())
        let store = SQLiteLibraryStore(url: fixture.url), saved = try await store.load()
        #expect(saved.history.map(\.id) == [rows[1].id, rows[2].id])
        #expect(saved.favorites == [favorite]); #expect(saved.queue == [queued])
        await store.close()
    }

    @Test func clearRequiresConfirmationAndCancelDoesNotChangeHistory() async throws {
        let fixture = HistoryFixture(); defer { fixture.remove() }
        let row = HistoryEntry(song: historySong(0), playedAt: historyNow, playCount: 7)
        let queued = QueueEntry(song: row.song), favorite = FavoriteRecord(song: row.song, addedAt: historyNow)
        try await fixture.seed(LibrarySnapshot(favorites: [favorite], history: [row], queue: [queued], currentSong: row.song))
        let library = fixture.library(); await library.restorationTask?.value
        library.confirmClearHistory(); #expect(library.history == [row])
        library.requestClearHistory(); #expect(library.isClearHistoryConfirmationPresented)
        #expect(library.history == [row]); #expect(!library.hasUnsavedChanges)
        library.cancelClearHistory(); library.confirmClearHistory()
        #expect(library.history == [row]); #expect(!library.hasUnsavedChanges)
        library.requestClearHistory(); library.confirmClearHistory()
        #expect(library.history.isEmpty); #expect(!library.isClearHistoryConfirmationPresented)
        #expect(library.queue == [queued]); #expect(library.favorites == [row.song])
        #expect(library.currentSong == row.song)
        library.requestClearHistory(); #expect(!library.isClearHistoryConfirmationPresented)
        #expect(await library.prepareToQuit())
        let store = SQLiteLibraryStore(url: fixture.url), saved = try await store.load()
        #expect(saved.history.isEmpty); #expect(saved.favorites == [favorite]); #expect(saved.queue == [queued])
        #expect(saved.currentSong == row.song)
        await store.close()
    }

    @Test(arguments: [HistoryRetention.sevenDays, .thirtyDays, .ninetyDays])
    func cleanupHonorsAgeBoundaryAndKeepsReferences(policy: HistoryRetention) async throws {
        let fixture = HistoryFixture(); defer { fixture.remove() }
        let now = historyNow.addingTimeInterval(300)
        let cutoff = now.addingTimeInterval(-Double(try #require(policy.days)) * 86_400)
        let recent = HistoryEntry(song: historySong(0), playedAt: now)
        let boundary = HistoryEntry(song: historySong(1), playedAt: cutoff)
        let older = HistoryEntry(song: historySong(2), playedAt: cutoff.addingTimeInterval(-1))
        let favorite = FavoriteRecord(song: older.song, addedAt: historyNow), queued = QueueEntry(song: boundary.song)
        try await fixture.seed(LibrarySnapshot(favorites: [favorite], history: [recent, boundary, older], queue: [queued]))
        let library = fixture.library(); await library.restorationTask?.value
        #expect(library.history.count == 3) // Never is the backward-compatible default.
        library.setHistoryRetention(policy)
        library.cleanupHistory(now: now)
        #expect(library.history == [recent]); #expect(library.favorites == [older.song]); #expect(library.queue == [queued])
        #expect(await library.prepareToQuit())
        let restored = fixture.library(); await restored.restorationTask?.value
        #expect(restored.history == [recent]); #expect(restored.historyRetention == policy)
        #expect(await restored.prepareToQuit())
    }

    @Test func startupAppliesPoliciesWithoutAutoplay() async throws {
        let fixture = HistoryFixture(); defer { fixture.remove() }
        let now = Date()
        let rows = (0..<510).map { HistoryEntry(song: historySong($0), playedAt: now.addingTimeInterval(-Double($0) * 86_400)) }
        try await fixture.seed(LibrarySnapshot(history: rows))
        fixture.defaults.set(HistoryRetention.ninetyDays.rawValue, forKey: "historyRetention")
        fixture.defaults.set(HistoryLimit.hundred.rawValue, forKey: "historyLimit")
        let player = FixturePlayer(), library = fixture.library(player: player)
        // Mutations during restoration cannot accidentally remove data or change settings.
        library.setHistoryLimit(.unlimited); library.requestClearHistory(); library.deleteHistoryEntry(rows[0].id)
        await library.restorationTask?.value
        #expect(library.history.map(\.id) == Array(rows.prefix(90)).map(\.id))
        #expect(library.historyLimit == .hundred); #expect(player.loads == 0); #expect(!library.isPlaying)
        #expect(await library.prepareToQuit())
        let store = SQLiteLibraryStore(url: fixture.url)
        #expect(try await store.load().history.count == 90)
        await store.close()
    }

    @Test(arguments: [HistoryLimit.hundred, .fiveHundred])
    func limitsKeepNewestAndApplyOnSubsequentPlayback(limit: HistoryLimit) async throws {
        let fixture = HistoryFixture(); defer { fixture.remove() }
        let rows = (0..<510).map { HistoryEntry(song: historySong($0), playedAt: historyNow.addingTimeInterval(-Double($0 + 1))) }
        try await fixture.seed(LibrarySnapshot(history: rows))
        let library = fixture.library(); await library.restorationTask?.value
        #expect(library.history.count == 510); #expect(library.historyLimit == .unlimited)
        library.setHistoryLimit(limit)
        let count = try #require(limit.count)
        #expect(library.history.map(\.id) == Array(rows.prefix(count)).map(\.id))
        library.play(historySong(999)); await library.playbackTask?.value
        #expect(library.history.count == count); #expect(library.history.first?.song == historySong(999))
        #expect(library.history.dropFirst().map(\.id) == Array(rows.prefix(count - 1)).map(\.id))
        library.setHistoryLimit(.unlimited)
        library.play(historySong(998)); await library.playbackTask?.value
        #expect(library.history.count == count + 1) // Increasing the limit does not resurrect deleted rows.
        #expect(await library.prepareToQuit())
        let restored = fixture.library(); await restored.restorationTask?.value
        #expect(restored.history.count == count + 1); #expect(restored.historyLimit == .unlimited)
        #expect(await restored.prepareToQuit())
    }

    @Test func unlimitedHistoryExceedsFormerSQLiteCapWithoutTruncation() async throws {
        let fixture = HistoryFixture(); defer { fixture.remove() }
        let now = Date()
        let rows = (0..<10_001).map { HistoryEntry(song: historySong($0), playedAt: now.addingTimeInterval(-Double($0))) }
        try await fixture.seed(LibrarySnapshot(history: rows))
        let library = fixture.library(); await library.restorationTask?.value
        library.cleanupHistory()
        #expect(library.historyRetention == .never); #expect(library.historyLimit == .unlimited)
        #expect(library.history.map(\.id) == rows.map(\.id))
        library.play(historySong(10_001)); await library.playbackTask?.value
        #expect(library.history.count == 10_002)
        #expect(await library.prepareToQuit())
        let store = SQLiteLibraryStore(url: fixture.url)
        #expect(try await store.load().history.count == 10_002)
        await store.close()
    }

    @Test func preferenceValuesRestoreAndInvalidValuesUseSafeDefaults() {
        let fixture = HistoryFixture(); defer { fixture.remove() }
        for value in HistoryRetention.allCases {
            let library = MusicLibrary(defaults: fixture.defaults, player: FixturePlayer())
            library.setHistoryRetention(value)
            #expect(MusicLibrary(defaults: fixture.defaults, player: FixturePlayer()).historyRetention == value)
            library.shutdown()
        }
        for value in HistoryLimit.allCases {
            let library = MusicLibrary(defaults: fixture.defaults, player: FixturePlayer())
            library.setHistoryLimit(value)
            #expect(MusicLibrary(defaults: fixture.defaults, player: FixturePlayer()).historyLimit == value)
            library.shutdown()
        }
        for invalid in ["invalid", "", "-1", "100000"] {
            fixture.defaults.set(invalid, forKey: "historyRetention")
            fixture.defaults.set(invalid, forKey: "historyLimit")
            let library = MusicLibrary(defaults: fixture.defaults, player: FixturePlayer())
            #expect(library.historyRetention == .never); #expect(library.historyLimit == .unlimited)
        }
    }

    @Test func failedHistoryWritePreservesCommittedRowsAndCanRetryClear() async throws {
        let fixture = HistoryFixture(); defer { fixture.remove() }
        let rows = (0..<2).map { HistoryEntry(song: historySong($0), playedAt: historyNow) }
        let favorite = FavoriteRecord(song: rows[0].song, addedAt: historyNow), queued = QueueEntry(song: rows[1].song)
        let original = LibrarySnapshot(favorites: [favorite], history: rows, queue: [queued])
        let store = HistoryFailingStore(data: original)
        let library = MusicLibrary(defaults: fixture.defaults, player: FixturePlayer(), store: store)
        await library.restorationTask?.value
        library.deleteHistoryEntry(rows[0].id)
        await library.persistenceTask?.value
        #expect(library.history == [rows[1]]); #expect(library.hasUnsavedChanges)
        #expect(library.persistenceError != nil)
        #expect(await store.load().history == rows)
        library.requestClearHistory(); library.confirmClearHistory()
        await store.allowWrites()
        library.retryPersistence()
        #expect(await library.flushPersistence())
        let saved = await store.load()
        #expect(saved.history.isEmpty); #expect(saved.favorites == [favorite]); #expect(saved.queue == [queued])
        #expect(await library.prepareToQuit())
    }

    @Test func idleCleanupExpiresHistoryWithoutPlayback() async throws {
        let fixture = HistoryFixture(); defer { fixture.remove() }
        let row = HistoryEntry(song: historySong(0), playedAt: Date().addingTimeInterval(-7 * 86_400 + 0.8))
        try await fixture.seed(LibrarySnapshot(history: [row]))
        fixture.defaults.set(HistoryRetention.sevenDays.rawValue, forKey: "historyRetention")
        let library = fixture.library(); await library.restorationTask?.value
        #expect(library.history.map(\.id) == [row.id])
        let deadline = Date().addingTimeInterval(5)
        while !library.history.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(library.history.isEmpty); #expect(!library.isPlaying)
        #expect(await library.prepareToQuit())
    }
}

private actor HistoryFailingStore: LibraryPersisting {
    var data: LibrarySnapshot
    var failing = true
    init(data: LibrarySnapshot) { self.data = data }
    func load() -> LibrarySnapshot { data }
    func save(_ snapshot: LibrarySnapshot, expecting revision: Int) throws -> Int {
        if failing { throw PersistenceError.writeFailed }
        data = snapshot; data.revision = revision + 1
        return data.revision
    }
    func allowWrites() { failing = false }
    func close() {}
}
