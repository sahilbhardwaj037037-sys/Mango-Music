import Foundation
import SQLite3
import Testing
@testable import MangoMusic

private struct DownloadFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MangoDownloads-\(UUID())")
    var db: URL { root.appendingPathComponent("library.sqlite3") }
    var media: URL { root.appendingPathComponent("Downloads") }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
private func downloadSQL(_ url: URL, _ sql: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw PersistenceError.unavailable }
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw PersistenceError.writeFailed }
}
private actor FixtureDownloadService: AudioDownloading {
    let delay: Duration
    let failFirst: Bool
    let ignoreCancellation: Bool
    var calls = 0, active = 0, maximumActive = 0
    init(delay: Duration = .milliseconds(10), failFirst: Bool = false, ignoreCancellation: Bool = false) {
        self.delay = delay; self.failFirst = failFirst; self.ignoreCancellation = ignoreCancellation
    }
    func download(source: URL, stage: URL, existingBytes: Int64, limits: DownloadLimits,
                  progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        calls += 1; active += 1; maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        progress(DownloadProgress(bytes: 32, total: 64))
        if ignoreCancellation { try? await Task.sleep(for: delay) }
        else { try await Task.sleep(for: delay); try Task.checkCancellation() }
        if failFirst && calls == 1 {
            try Data([1,2,3]).write(to: stage.appendingPathComponent("audio.wav.part"))
            throw DownloadError.unavailable
        }
        let output = stage.appendingPathComponent("audio.wav")
        try Data(repeating: 7, count: 64).write(to: output)
        return output
    }
    func count() -> Int { calls }
    func maxActive() -> Int { maximumActive }
}
private struct FixtureAudioValidator: AudioFileValidating {
    var fail = false
    var delay: Duration = .zero
    func validate(_ url: URL) async throws -> ValidatedAudio {
        try await Task.sleep(for: delay)
        if fail { throw DownloadError.invalidAudio }
        return ValidatedAudio(duration: 8, format: "wav")
    }
}
private actor StreamingDownloadSpy: AudioStreamResolving, SongSearching, RelatedSongProviding {
    var resolutions = 0, searches = 0, recommendations = 0
    func resolve(_ song: Song) async throws -> URL { resolutions += 1; return URL(string: "https://example.com/audio")! }
    func search(query: String) async throws -> [Song] { searches += 1; return [] }
    func recommendations(for seed: Song, excluding: Set<String>) async throws -> RelatedSongs { recommendations += 1; return RelatedSongs(songs: [], source: .mix) }
    func counts() -> [Int] { [resolutions, searches, recommendations] }
}

private actor FailingDownloadStore: DownloadPersisting {
    var failing = true
    var snapshot = DownloadSnapshot()
    func loadDownloads() async throws -> DownloadSnapshot { snapshot }
    func saveDownloads(_ records: [DownloadRecord], expecting revision: Int) async throws -> Int {
        if failing { throw PersistenceError.writeFailed }
        guard revision == snapshot.revision else { throw PersistenceError.conflict }
        snapshot = DownloadSnapshot(records: records, revision: revision + 1)
        return snapshot.revision
    }
    func allowWrites() { failing = false }
}

@MainActor
struct DownloadManagerTests {
    private func manager(_ fixture: DownloadFixture, service: any AudioDownloading = FixtureDownloadService(),
                         validator: any AudioFileValidating = FixtureAudioValidator(), limits: DownloadLimits = DownloadLimits()) -> DownloadManager {
        DownloadManager(store: SQLiteLibraryStore(url: fixture.db), files: ManagedDownloadFiles(root: fixture.media),
                        service: service, validator: validator, limits: limits)
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition())
        if !condition() { throw PlaybackError.timeout }
    }
    @Test func lifecycleProgressOneWorkerAndDuplicates() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let service = FixtureDownloadService(delay: .milliseconds(60)), downloads = manager(fixture, service: service)
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); downloads.enqueue(testSong(0)); downloads.enqueue(testSong(1))
        #expect(downloads.records.count == 2)
        try await wait { downloads.progress[testSong(0).id]?.fraction == 0.5 }
        await downloads.workerTask?.value
        #expect(downloads.completed.count == 2); #expect(downloads.bytesUsed == 128)
        #expect(await service.count() == 2); #expect(await service.maxActive() == 1)
        downloads.enqueue(testSong(0)); #expect(await service.count() == 2)
        #expect(try await downloads.localFile(for: testSong(0))?.isFileURL == true)
        #expect(await downloads.prepareToQuit())
    }
    @Test func failureCleanupAndFreshRetry() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let service = FixtureDownloadService(failFirst: true), downloads = manager(fixture, service: service)
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); await downloads.workerTask?.value
        #expect(downloads.records.first?.status == .failed)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.media.appendingPathComponent("staging").path).isEmpty)
        let old = downloads.records.first?.attempt
        await downloads.retry(testSong(0).id); await downloads.workerTask?.value
        #expect(downloads.records.first?.status == .complete); #expect(downloads.records.first?.attempt != old)
        #expect(await downloads.prepareToQuit())
    }
    @Test func cancellationRejectsLateServiceDataAndStartsNextJob() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let service = FixtureDownloadService(delay: .milliseconds(80), ignoreCancellation: true), downloads = manager(fixture, service: service)
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); downloads.enqueue(testSong(1))
        try await wait { downloads.progress[testSong(0).id] != nil }
        downloads.cancel(testSong(0).id)
        try await wait { downloads.record(for: testSong(1))?.status == .complete }
        #expect(downloads.record(for: testSong(0))?.status == .cancelled)
        #expect(try await downloads.localFile(for: testSong(0)) == nil)
        #expect(downloads.progress[testSong(0).id] == nil)
        #expect(await service.maxActive() == 1)
        #expect(await downloads.prepareToQuit())
    }
    @Test func invalidAudioNeverPublishes() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let downloads = manager(fixture, validator: FixtureAudioValidator(fail: true))
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); await downloads.workerTask?.value
        #expect(downloads.completed.isEmpty); #expect(downloads.records.first?.status == .failed)
        #expect(try await downloads.files.usage() == 0)
        #expect(await downloads.prepareToQuit())
    }
    @Test func publicationConflictPreservesExistingFile() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let downloads = manager(fixture, service: FixtureDownloadService(delay: .milliseconds(100)))
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0))
        let record = try #require(downloads.records.first)
        let path = try await downloads.files.relativePath(for: record, extension: "wav")
        let existing = fixture.media.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("existing file must survive".utf8); try original.write(to: existing)
        await downloads.workerTask?.value
        #expect(downloads.records.first?.status == .failed)
        #expect(try Data(contentsOf: existing) == original)
        #expect(await downloads.prepareToQuit())
    }
    @Test func missingAndCorruptFilesAreNotPlayable() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let downloads = manager(fixture)
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); downloads.enqueue(testSong(1)); await downloads.workerTask?.value
        let first = try #require(try await downloads.localFile(for: testSong(0)))
        try Data(repeating: 8, count: 64).write(to: first) // Same length; checksum must catch corruption.
        #expect(try await downloads.localFile(for: testSong(0)) == nil)
        #expect(downloads.record(for: testSong(0))?.status == .missing)
        let second = try #require(try await downloads.localFile(for: testSong(1))); try FileManager.default.removeItem(at: second)
        #expect(try await downloads.localFile(for: testSong(1)) == nil)
        #expect(downloads.bytesUsed == 0)
        #expect(await downloads.prepareToQuit())
    }
    @Test func deletionAndClearRemoveOnlyManagedDownloads() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let store = SQLiteLibraryStore(url: fixture.db)
        let original = LibrarySnapshot(favorites: [FavoriteRecord(song: testSong(0), addedAt: Date(timeIntervalSince1970: 1))],
            history: [HistoryEntry(song: testSong(1), playedAt: Date(timeIntervalSince1970: 2))], queue: [QueueEntry(song: testSong(0))], currentSong: testSong(0))
        _ = try await store.load(); let revision = try await store.save(original, expecting: 0)
        let downloads = manager(fixture)
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); downloads.enqueue(testSong(1)); await downloads.workerTask?.value
        await downloads.delete([testSong(0).id]); #expect(downloads.bytesUsed == 64)
        await downloads.delete(Set(downloads.records.map(\.id)))
        #expect(downloads.records.isEmpty); #expect(try await downloads.files.usage() == 0)
        var expected = original; expected.revision = revision
        #expect(try await store.load() == expected)
        #expect(await downloads.prepareToQuit()); await store.close()
    }
    @Test func restartReconcilesIncompleteAndDeletedFilesWithoutAutodownload() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let downloads = manager(fixture)
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); await downloads.workerTask?.value
        let file = try #require(try await downloads.localFile(for: testSong(0)))
        #expect(await downloads.prepareToQuit()); try FileManager.default.removeItem(at: file)
        let store = SQLiteLibraryStore(url: fixture.db); let snapshot = try await store.loadDownloads()
        var pending = DownloadRecord(song: testSong(1), sourceURL: URL(string: "https://www.youtube.com/watch?v=abcdefghij1")!)
        pending.status = .downloading
        let files = ManagedDownloadFiles(root: fixture.media), stage = try await files.stage(pending.attempt)
        try Data([1]).write(to: stage.appendingPathComponent("audio.wav.part"))
        _ = try await store.saveDownloads(snapshot.records + [pending], expecting: snapshot.revision)
        await store.close(); await files.close()
        let service = FixtureDownloadService(), restored = manager(fixture, service: service)
        await restored.restorationTask?.value
        #expect(restored.record(for: testSong(0))?.status == .missing)
        #expect(restored.record(for: testSong(1))?.status == .interrupted)
        #expect(await service.count() == 0); #expect(!FileManager.default.fileExists(atPath: stage.path))
        #expect(await restored.prepareToQuit())
    }
    @Test func localFirstAndOfflineModeBlockEveryOnlineBoundary() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let downloads = manager(fixture)
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); await downloads.workerTask?.value
        let suite = "MangoOfflineTests.\(UUID())", defaults: UserDefaults
        defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let spy = StreamingDownloadSpy(), player = FixturePlayer()
        let library = MusicLibrary(defaults: defaults, searchService: spy, resolver: spy, player: player, relatedProvider: spy, downloadManager: downloads)
        library.play(testSong(0)); await library.playbackTask?.value
        #expect(library.isPlayingLocal); #expect(await spy.counts() == [0,0,0])
        library.setAutoplayEnabled(true); await library.relatedTask?.value
        let before = await spy.counts()
        library.setOfflineMode(true); library.play(testSong(0)); await library.playbackTask?.value
        library.query = "music"; library.search(); library.next(); await library.playbackTask?.value
        #expect(await spy.counts() == before); #expect(library.relatedTask == nil)
        library.play(testSong(1)); await library.playbackTask?.value
        #expect(library.playbackError != nil); #expect(await spy.counts() == before)
        let restored = MusicLibrary(defaults: defaults, resolver: spy, player: FixturePlayer(), relatedProvider: spy)
        #expect(restored.offlineMode); #expect(restored.playbackTask == nil)
        library.setOfflineMode(false); library.play(testSong(1)); await library.playbackTask?.value
        #expect(await spy.counts().first == 1)
        #expect(await library.prepareToQuit())
    }
    @Test func offlineCancelsDownloadsAndDoesNotResumeOnModeExit() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let service = FixtureDownloadService(delay: .milliseconds(100)), downloads = manager(fixture, service: service)
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); try await wait { downloads.progress[testSong(0).id] != nil }
        downloads.setOffline(true); await downloads.workerTask?.value
        downloads.enqueue(testSong(1)); #expect(downloads.record(for: testSong(1)) == nil)
        downloads.setOffline(false); #expect(await service.count() == 1)
        #expect(downloads.records.first?.status == .cancelled)
        #expect(await downloads.prepareToQuit())
    }
    @Test func failedPersistenceBlocksDownloadsAndQuitUntilRetry() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let store = FailingDownloadStore(), service = FixtureDownloadService()
        let downloads = DownloadManager(store: store, files: ManagedDownloadFiles(root: fixture.media),
            service: service, validator: FixtureAudioValidator())
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); await downloads.workerTask?.value
        #expect(downloads.persistenceError != nil); #expect(downloads.hasUnsavedChanges)
        #expect(await service.count() == 0)
        #expect(!(await downloads.prepareToQuit())); #expect(!downloads.isClosing)
        await store.allowWrites()
        #expect(await downloads.flush()); #expect(downloads.persistenceError == nil)
        await downloads.retry(testSong(0).id); await downloads.workerTask?.value
        #expect(downloads.completed.count == 1); #expect(await downloads.prepareToQuit())
    }
    @Test func offlineQueueFavoritesRepeatAndShuffleUseLocalFilesWithoutRadio() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let downloads = manager(fixture)
        await downloads.restorationTask?.value
        for index in 0..<3 { downloads.enqueue(testSong(index)) }
        await downloads.workerTask?.value
        let suite = "MangoOfflineOrder.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let player = FixturePlayer(), spy = StreamingDownloadSpy()
        let library = MusicLibrary(defaults: defaults, searchService: spy, resolver: spy, player: player,
            relatedProvider: spy, downloadManager: downloads)
        library.setOfflineMode(true); library.setAutoplayEnabled(true)
        library.toggleFavorite(testSong(0)); library.toggleFavorite(testSong(1))
        library.cycleRepeatMode() // Repeat One wins over the manual queue on EOF.
        library.playFavorites(); await library.playbackTask?.value
        library.enqueue(testSong(2)); player.emit(.ended); await library.playbackTask?.value
        #expect(library.currentSong?.id == testSong(0).id); #expect(library.queue.count == 1)
        library.next(); await library.playbackTask?.value
        #expect(library.currentSong?.id == testSong(2).id); #expect(library.queue.isEmpty)
        library.cycleRepeatMode() // Repeat All returns to Favorites and wraps.
        player.emit(.ended); await library.playbackTask?.value
        #expect(library.currentSong?.id == testSong(1).id)
        player.emit(.ended); await library.playbackTask?.value
        #expect(library.currentSong?.id == testSong(0).id); #expect(library.isPlayingLocal)
        library.cycleRepeatMode() // Off finishes the finite playlist without Autoplay.
        player.emit(.ended); await library.playbackTask?.value
        player.emit(.ended); await library.playbackTask?.value
        #expect(!library.isPlaying); #expect(await spy.counts() == [0,0,0])
        library.playFavorites(shuffled: true); await library.playbackTask?.value
        #expect(Set(library.favoritesSequence.map(\.id)) == Set([testSong(0).id, testSong(1).id]))
        #expect(library.isPlayingLocal); #expect(library.history.count == 3)
        #expect(await library.prepareToQuit())
    }
    @Test func quitCancelsWorkerAndFlushesRecoverableState() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let downloads = manager(fixture, service: FixtureDownloadService(delay: .milliseconds(100)))
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); downloads.enqueue(testSong(1))
        try await wait { downloads.progress[testSong(0).id] != nil }
        #expect(await downloads.prepareToQuit()); #expect(downloads.workerTask == nil)
        let store = SQLiteLibraryStore(url: fixture.db), data = try await store.loadDownloads()
        #expect(data.records.allSatisfy { $0.status == .cancelled }); await store.close()
    }
    @Test func cancelDuringValidationCannotPublish() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let downloads = manager(fixture, validator: FixtureAudioValidator(delay: .milliseconds(100)))
        await downloads.restorationTask?.value
        downloads.enqueue(testSong(0)); try await wait { downloads.records.first?.status == .validating }
        downloads.cancel(testSong(0).id); await downloads.workerTask?.value
        #expect(downloads.records.first?.status == .cancelled); #expect(try await downloads.files.usage() == 0)
        #expect(await downloads.prepareToQuit())
    }
}

struct DownloadStorageTests {
    @Test func traversalAndSymlinksCannotEscapeManagedRoot() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let files = ManagedDownloadFiles(root: fixture.media), attempt = UUID()
        let stage = try await files.stage(attempt)
        let outside = fixture.root.appendingPathComponent("outside"); try Data("keep".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: stage.appendingPathComponent("audio.wav"), withDestinationURL: outside)
        await #expect(throws: (any Error).self) { try await files.inspectStage(attempt, name: "audio.wav", limit: 1000) }
        for path in ["../outside", "/tmp/file", "media/../../outside", "media/wrong.wav"] {
            #expect(!ManagedDownloadFiles.validRelativePath(path, attempt: attempt, videoID: "abcdefghij0"))
        }
        try await files.cleanStage(attempt)
        #expect(try String(contentsOf: outside, encoding: .utf8) == "keep")
        let badRoot = fixture.root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: badRoot, withDestinationURL: fixture.media)
        await #expect(throws: DownloadError.unsafePath) { try await ManagedDownloadFiles(root: badRoot).stage(UUID()) }
    }
    @Test func exclusiveLeasePreventsAnotherInstanceFromDeletingLiveStaging() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let first = ManagedDownloadFiles(root: fixture.media), second = ManagedDownloadFiles(root: fixture.media)
        let attempt = UUID(), stage = try await first.stage(attempt)
        let partial = stage.appendingPathComponent("audio.wav.part")
        try Data([1,2,3]).write(to: partial)
        await #expect(throws: DownloadError.conflict) { try await second.cleanStage(attempt) }
        #expect(FileManager.default.fileExists(atPath: partial.path))
        await first.close()
        try await second.cleanStage(attempt)
        #expect(!FileManager.default.fileExists(atPath: stage.path))
        await second.close()
    }
    @Test func budgetsRejectOversizedAndLowSpaceBeforeNetwork() throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.media, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 20).write(to: fixture.media.appendingPathComponent("partial"))
        #expect(throws: DownloadError.storageLimit) { try ManagedDownloadFiles.checkSpace(stage: fixture.media, limits: DownloadLimits(perFile: 10), existingBytes: 0) }
        #expect(throws: DownloadError.storageLimit) { try ManagedDownloadFiles.checkSpace(stage: fixture.media, limits: DownloadLimits(total: 25), existingBytes: 10) }
        #expect(throws: DownloadError.noSpace) { try ManagedDownloadFiles.checkSpace(stage: fixture.media, limits: DownloadLimits(freeReserve: Int64.max), existingBytes: 0) }
    }
    @Test func v2MigrationAndIndependentRevisionsPreserveCollections() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let store = SQLiteLibraryStore(url: fixture.db)
        _ = try await store.load()
        var library = LibrarySnapshot(favorites: [FavoriteRecord(song: testSong(0), addedAt: Date(timeIntervalSince1970: 100))], history: [HistoryEntry(song: testSong(1), playedAt: Date(timeIntervalSince1970: 200))], queue: [QueueEntry(song: testSong(0))], currentSong: testSong(0))
        library.revision = try await store.save(library, expecting: 0); await store.close()
        try downloadSQL(fixture.db, "DROP TABLE downloads; DROP TABLE download_state; PRAGMA user_version=2;")
        let migrated = SQLiteLibraryStore(url: fixture.db)
        #expect(try await migrated.load() == library)
        #expect(try await migrated.loadDownloads().records.isEmpty)
        let record = DownloadRecord(song: testSong(0), sourceURL: URL(string: "https://www.youtube.com/watch?v=abcdefghij0")!)
        _ = try await migrated.saveDownloads([record], expecting: 0)
        library.revision = try await migrated.save(library, expecting: library.revision)
        #expect(try await migrated.load() == library); #expect(try await migrated.loadDownloads().records == [record])
        await #expect(throws: PersistenceError.conflict) { try await migrated.saveDownloads([], expecting: 0) }
        #expect(try await migrated.loadDownloads().records == [record]); await migrated.close()
    }
    @Test func invalidDownloadPathsRollBack() async throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let store = SQLiteLibraryStore(url: fixture.db); _ = try await store.load()
        var record = DownloadRecord(song: testSong(0), sourceURL: URL(string: "https://www.youtube.com/watch?v=abcdefghij0")!)
        record.relativePath = "../../outside"
        await #expect(throws: PersistenceError.invalidData) { try await store.saveDownloads([record], expecting: 0) }
        #expect(try await store.loadDownloads().records.isEmpty); await store.close()
    }
    @Test func restrictedPackagedDiscoveryNeverUsesHomebrewConversion() throws {
        let fixture = DownloadFixture(); defer { fixture.remove() }
        let bundle = fixture.root.appendingPathComponent("Mock.app")
        let binaries = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
        #expect(VerifiedConversionTools.discover(bundleURL: bundle, bundled: true) == nil)
        for name in ["ffmpeg", "ffprobe"] {
            let file = binaries.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        #expect(VerifiedConversionTools.discover(bundleURL: bundle, bundled: true) == nil)
        let args = YTAudioDownloadService.arguments(source: URL(string: "https://www.youtube.com/watch?v=abcdefghij0")!, stage: fixture.media, limits: DownloadLimits(), tools: nil)
        #expect(!args.contains("--ffmpeg-location")); #expect(args.contains("never")); #expect(!args.contains("--extract-audio"))
        #expect(args.contains("bestaudio[protocol^=m3u8]/bestaudio[ext=m4a]/bestaudio")); #expect(args.contains("--no-continue"))
    }
}
