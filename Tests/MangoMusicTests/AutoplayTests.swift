import Foundation
import Testing
@testable import MangoMusic

private func response(_ entries: [[String: Any]], id: String = "RDabcdefghij0") throws -> ProcessOutput {
    ProcessOutput(stdout: try JSONSerialization.data(withJSONObject: ["_type":"playlist", "id":id, "entries":entries]), stderr: Data(), status: 0)
}
private func entry(_ id: String, title: String = "Song") -> [String: Any] {
    ["id":id, "title":title, "channel":"Channel", "duration":100]
}
private actor RecommendationRunner: ProcessRunning {
    var calls: [[String]] = []
    let outputs: [ProcessOutput]
    init(_ outputs: [ProcessOutput]) { self.outputs = outputs }
    func run(executable: URL, arguments: [String]) async throws -> ProcessOutput {
        calls.append(arguments)
        return outputs[min(calls.count - 1, outputs.count - 1)]
    }
    func count() -> Int { calls.count }
    func arguments() -> [[String]] { calls }
}

struct MixProviderTests {
    @Test func argumentsAndURLAreBoundedAndSafe() throws {
        let url = try YouTubeMixProvider.mixURL("youtube:abcdefghij0")
        #expect(url == "https://www.youtube.com/watch?v=abcdefghij0&list=RDabcdefghij0&start_radio=1")
        #expect(throws: PlaybackError.invalidVideo) { try YouTubeMixProvider.mixURL("bad&list=evil") }
        let args = YouTubeMixProvider.arguments(url)
        #expect(args.contains("--flat-playlist")); #expect(args.contains("--yes-playlist"))
        #expect(args.contains("--playlist-end")); #expect(args.contains("20")); #expect(args.contains("--skip-download"))
        #expect(args.suffix(2) == ["--", url]); #expect(!args.contains("--cookies-from-browser"))
    }
    @Test func parserRejectsBadEntriesAndBoundsDeduplicatedSongs() throws {
        var entries: [[String:Any]] = [entry("abcdefghij1"), entry("abcdefghij1"), entry("invalid"), entry("abcdefghij2",title:" ")]
        var live = entry("abcdefghij3"); live["live_status"] = "is_live"; entries.append(live)
        var privateVideo = entry("abcdefghij4"); privateVideo["availability"] = "private"; entries.append(privateVideo)
        var invalidDuration = entry("abcdefghij5"); invalidDuration["duration"] = -2; entries.append(invalidDuration)
        entries += (0..<30).map { entry(String(format:"%011d",$0)) }
        let songs = try YouTubeMixProvider.decode(response(entries),expectedMix:"RDabcdefghij0")
        #expect(songs.count == 20); #expect(Set(songs.map(\.id)).count == 20)
        #expect(songs.first?.artist == "Channel"); #expect(songs.first?.duration == 100)
        #expect(!songs.contains { $0.id == "youtube:abcdefghij3" || $0.id == "youtube:abcdefghij4" })
        var unknown = entry("abcdefghij9"); unknown.removeValue(forKey:"duration")
        #expect(try YouTubeMixProvider.decode(response([unknown])).first?.durationKnown == false)
    }
    @Test func invalidObjectsAndWrongMixAreNotAccepted() throws {
        for text in ["null", "{}", "[]", "bad", "{\"_type\":\"video\",\"entries\":[]}"] {
            #expect(throws: RecommendationError.malformed) {
                try YouTubeMixProvider.decode(ProcessOutput(stdout:Data(text.utf8),stderr:Data(),status:0))
            }
        }
        #expect(throws: RecommendationError.malformed) { try YouTubeMixProvider.decode(response([entry("abcdefghij1")]),expectedMix:"RDother") }
    }
    @Test func mixUsesCacheAndRefiltersExclusions() async throws {
        let runner = RecommendationRunner([try response([entry("abcdefghij0"),entry("abcdefghij1"),entry("abcdefghij2")])])
        let provider = YouTubeMixProvider(executableURL: URL(fileURLWithPath:"/usr/bin/true"), runner:runner)
        let first = try await provider.recommendations(for:testSong(0),excluding:[testSong(1).id])
        #expect(first.source == .mix); #expect(first.songs.map(\.id) == [testSong(2).id])
        let second = try await provider.recommendations(for:testSong(0),excluding:[testSong(2).id])
        #expect(second.songs.map(\.id) == [testSong(1).id]); #expect(await runner.count() == 1)
    }
    @Test func genuineUnavailableMixUsesExactlyOneSearchFallback() async throws {
        let missing = ProcessOutput(stdout:Data("null".utf8),stderr:Data("This playlist type is unviewable".utf8),status:1)
        let runner = RecommendationRunner([missing,try response([entry("abcdefghij1")],id:"search")])
        let provider = YouTubeMixProvider(executableURL:URL(fileURLWithPath:"/usr/bin/true"),runner:runner)
        let batch = try await provider.recommendations(for:testSong(0),excluding:[])
        #expect(batch.source == .searchFallback); #expect(await runner.count() == 2)
        #expect(await runner.arguments().last?.last == "ytsearch20:Fixture official audio")
    }
    @Test(arguments:["HTTP Error 429: Too Many Requests", "Sign in to confirm you're not a bot"])
    func throttlingSuppressesFallbackAndFurtherRequests(message:String) async {
        let runner = RecommendationRunner([ProcessOutput(stdout:Data(),stderr:Data(message.utf8),status:1)])
        let provider = YouTubeMixProvider(executableURL:URL(fileURLWithPath:"/usr/bin/true"),runner:runner)
        await #expect(throws: RecommendationError.throttled) { try await provider.recommendations(for:testSong(0),excluding:[]) }
        await #expect(throws: RecommendationError.coolingDown) { try await provider.recommendations(for:testSong(1),excluding:[]) }
        #expect(await runner.count() == 1)
    }
    @Test func malformedAndTransportFailuresDoNotTriggerSearch() async {
        for output in [ProcessOutput(stdout:Data("null".utf8),stderr:Data(),status:0),ProcessOutput(stdout:Data(),stderr:Data("Network error".utf8),status:1)] {
            let runner = RecommendationRunner([output])
            let tested = YouTubeMixProvider(executableURL:URL(fileURLWithPath:"/usr/bin/true"),runner:runner)
            await #expect(throws:(any Error).self) { try await tested.recommendations(for:testSong(0),excluding:[]) }
            #expect(await runner.count() == 1)
        }
    }
}

private actor FakeRelatedProvider: RelatedSongProviding {
    var calls = 0
    let songs: [Song]
    let delayed: Bool
    let source: RecommendationSource
    var continuations: [CheckedContinuation<RelatedSongs,Never>] = []
    init(_ songs:[Song] = [testSong(5),testSong(6),testSong(7)], delayed:Bool = false, source:RecommendationSource = .mix) {
        self.songs = songs; self.delayed = delayed; self.source = source
    }
    func recommendations(for seed:Song, excluding:Set<String>) async throws -> RelatedSongs {
        calls += 1
        if delayed { return await withCheckedContinuation { continuations.append($0) } }
        return RelatedSongs(songs:songs,source:source)
    }
    func count() -> Int { calls }
    func release() { let pending = continuations; continuations = []; pending.forEach { $0.resume(returning:RelatedSongs(songs:songs,source:source)) } }
}

@MainActor
struct AutoplayTests {
    func make(_ player:FixturePlayer, provider:any RelatedSongProviding, resolver:any AudioStreamResolving = FixtureResolver()) -> MusicLibrary {
        MusicLibrary(defaults:UserDefaults(suiteName:"MangoAutoplayTests.\(UUID())")!,resolver:resolver,player:player,relatedProvider:provider)
    }
    func ready(_ library:MusicLibrary) async {
        await library.playbackTask?.value
        await library.relatedTask?.value
    }
    func complete(_ library:MusicLibrary, _ player:FixturePlayer) async {
        player.emit(.ended); await ready(library)
        await library.playbackTask?.value
    }
    private func waitForRequest(_ provider:FakeRelatedProvider, count:Int = 1) async {
        let deadline = Date().addingTimeInterval(3)
        while await provider.count() < count, Date() < deadline { await Task.yield() }
        #expect(await provider.count() >= count)
    }

    @Test func defaultOffAndPreferenceRestorationNeverStartsPlayback() async {
        let suite = "AutoplayPrefs.\(UUID())"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let provider = FakeRelatedProvider(), player = FixturePlayer()
        let library = MusicLibrary(defaults:defaults,resolver:FixtureResolver(),player:player,relatedProvider:provider)
        #expect(!library.autoplayEnabled)
        library.play(testSong(0)); await ready(library)
        #expect(await provider.count() == 0)
        library.stop(); library.setAutoplayEnabled(true)
        #expect(await provider.count() == 0)
        let restored = MusicLibrary(defaults:defaults,player:FixturePlayer(),relatedProvider:provider)
        #expect(restored.autoplayEnabled); #expect(!restored.isPlaying); #expect(restored.relatedTask == nil)
        defaults.set("true",forKey:"autoplayEnabled")
        #expect(!MusicLibrary(defaults:defaults,player:FixturePlayer()).autoplayEnabled)
        library.shutdown()
    }
    @Test func naturalEOFConsumesSnapshotAndRejectsDuplicateEvents() async {
        let provider = FakeRelatedProvider(), player = FixturePlayer(), library = make(player,provider:provider)
        library.setAutoplayEnabled(true); library.play(testSong(0)); await ready(library)
        let old = player.request
        player.emit(.ended); library.receive(old,.ended); await ready(library)
        #expect(library.currentSong == testSong(5)); #expect(library.currentRecommendationSource == .mix)
        await complete(library,player); #expect(library.currentSong == testSong(6))
        #expect(await provider.count() == 1); #expect(library.queue.isEmpty)
        library.stop()
    }
    @Test func queueAndFavoritesTakePriorityThenResumeRadio() async {
        let provider = FakeRelatedProvider(), player = FixturePlayer(), library = make(player,provider:provider)
        library.toggleFavorite(testSong(0)); library.toggleFavorite(testSong(1))
        library.setAutoplayEnabled(true); library.playFavorites(); await ready(library)
        library.enqueue(testSong(2)); library.playNext(testSong(3))
        await complete(library,player); #expect(library.currentSong == testSong(3))
        await complete(library,player); #expect(library.currentSong == testSong(2))
        await complete(library,player); #expect(library.currentSong == testSong(1))
        await complete(library,player); #expect(library.currentSong == testSong(5))
        #expect(library.queue.isEmpty); #expect(library.favoritesPlaybackActive)
        library.stop()
    }
    @Test func repeatOneAndAllRetainPriorityButManualNextBypassesOne() async {
        let provider = FakeRelatedProvider(), player = FixturePlayer(), library = make(player,provider:provider)
        library.toggleFavorite(testSong(0)); library.toggleFavorite(testSong(1))
        library.setAutoplayEnabled(true); library.cycleRepeatMode(); library.playFavorites(); await ready(library)
        await complete(library,player); #expect(library.currentSong == testSong(0))
        library.next(); await ready(library); #expect(library.currentSong == testSong(1))
        library.cycleRepeatMode()
        await complete(library,player); #expect(library.currentSong == testSong(0))
        library.cycleRepeatMode() // Off must still allow opted-in radio.
        library.next(); await ready(library); library.next(); await ready(library)
        #expect(library.currentSong == testSong(5)); library.stop()
    }
    @Test func pauseAndManualNextStayPausedOnRadio() async {
        let player = FixturePlayer(), library = make(player,provider:FakeRelatedProvider())
        library.setAutoplayEnabled(true); library.play(testSong(0)); await ready(library)
        library.pausePlayback(); library.next(); await ready(library)
        #expect(library.currentSong == testSong(5)); #expect(!library.isPlaying)
        library.stop()
    }
    @Test(arguments:["stop","off","sleep","output","shutdown","quit"])
    func cancellationRejectsLateProviderResponses(action:String) async {
        let provider = FakeRelatedProvider(delayed:true), player = FixturePlayer(), library = make(player,provider:provider)
        library.setAutoplayEnabled(true); library.play(testSong(0)); await library.playbackTask?.value
        await waitForRequest(provider)
        let task = library.relatedTask
        player.emit(.ended)
        #expect(library.playPauseShowsPause)
        switch action {
        case "off": library.setAutoplayEnabled(false)
        case "sleep": library.handleInterruption(.sleep)
        case "output": library.handleInterruption(.outputChanged)
        case "shutdown": library.shutdown()
        case "quit": #expect(await library.prepareToQuit())
        default: library.stop()
        }
        await provider.release(); await task?.value; await library.playbackTask?.value
        #expect(player.loads == 1); #expect(!library.isPlaying); #expect(!library.isFindingRelatedSongs)
        library.shutdown()
    }
    @Test func manualNextStopsOldAudioWhileWaitingForPrefetch() async {
        let provider = FakeRelatedProvider(delayed:true), player = FixturePlayer(), library = make(player,provider:provider)
        library.setAutoplayEnabled(true); library.play(testSong(0)); await library.playbackTask?.value
        await waitForRequest(provider)
        let old = player.request, stops = player.stops
        library.next(); await library.playbackTask?.value
        #expect(player.stops > stops); #expect(!library.isPlaying)
        library.receive(old,.loaded); library.receive(old,.position(5))
        #expect(!library.isPlaying)
        await provider.release(); await library.relatedTask?.value; await library.playbackTask?.value
        #expect(library.currentSong == testSong(5)); #expect(library.isPlaying)
        library.stop()
    }
    @Test func pendingFetchYieldsImmediatelyToNewManualQueue() async {
        let provider = FakeRelatedProvider(delayed:true), player = FixturePlayer(), library = make(player,provider:provider)
        library.setAutoplayEnabled(true); library.play(testSong(0)); await library.playbackTask?.value
        await waitForRequest(provider); player.emit(.ended)
        let oldGeneration = library.mediaPlaybackSnapshot.generation
        library.enqueue(testSong(2)); await library.playbackTask?.value
        #expect(library.currentSong == testSong(2))
        library.handleMediaCommand(.next,generation:oldGeneration)
        await provider.release(); await library.relatedTask?.value
        #expect(library.currentSong == testSong(2))
        await complete(library,player); #expect(library.currentSong == testSong(5)); library.stop()
    }
    @Test func lateOldSelectionCannotStartAfterDirectPlayOrPrevious() async {
        let provider = FakeRelatedProvider(delayed:true), player = FixturePlayer(), library = make(player,provider:provider)
        library.setAutoplayEnabled(true); library.play(testSong(0)); await library.playbackTask?.value
        await waitForRequest(provider); let old = library.relatedTask
        player.emit(.ended); library.play(testSong(1)); await library.playbackTask?.value
        await waitForRequest(provider,count:2)
        await provider.release(); await old?.value
        #expect(library.currentSong == testSong(1))
        library.previous(); await library.playbackTask?.value
        #expect(library.currentSong == testSong(0))
        await waitForRequest(provider,count:3)
        library.stop(); await provider.release()
    }
    @Test func dedupRechecksQueueRecentAndCurrentAtConsumption() async {
        let player = FixturePlayer(), provider = FakeRelatedProvider([testSong(0),testSong(1),testSong(1),testSong(2),testSong(5)])
        let library = make(player,provider:provider)
        library.play(testSong(1)); await ready(library)
        library.setAutoplayEnabled(true); library.play(testSong(0)); await ready(library)
        library.enqueue(testSong(2))
        await complete(library,player); #expect(library.currentSong == testSong(2))
        await complete(library,player); #expect(library.currentSong == testSong(5)); library.stop()
    }
    @Test func emptyRecommendationsStopWithoutRepeatedRequests() async {
        let provider = FakeRelatedProvider([]), player = FixturePlayer(), library = make(player,provider:provider)
        library.setAutoplayEnabled(true); library.play(testSong(0)); await ready(library)
        await complete(library,player)
        #expect(!library.isPlaying); #expect(library.autoplayNotice != nil); #expect(await provider.count() == 1)
    }
    @Test func automaticStreamErrorsAreBoundedAndManualFailuresStillRequireRetry() async {
        let provider = FakeRelatedProvider(), player = FixturePlayer(), library = make(player,provider:provider,resolver:FailedAutomaticResolver())
        library.setAutoplayEnabled(true); library.play(testSong(0)); await ready(library)
        player.emit(.ended)
        for _ in 0..<15 { await ready(library) }
        #expect(!library.isPlaying); #expect(library.playbackError != nil); #expect(library.autoplayNotice?.contains("three") == true)
        #expect(player.loads == 1)
        library.play(testSong(1)); await ready(library)
        #expect(library.currentSong == testSong(1)); #expect(library.playbackError != nil)
        #expect(player.loads == 1); library.stop()
    }
    @Test func providerFailureLeavesCurrentAudioPlayingThenStopsGracefully() async {
        let player = FixturePlayer(), library = make(player,provider:FailingRelatedProvider())
        library.setAutoplayEnabled(true); library.play(testSong(0)); await ready(library)
        #expect(library.isPlaying); #expect(library.playbackError == nil)
        #expect(library.autoplayNotice?.contains("cooling") == true)
        await complete(library,player)
        #expect(!library.isPlaying); #expect(library.autoplayNotice?.contains("cooling") == true)
    }
    @Test func pauseWhileWaitingCancelsTransitionAndToggleOnAloneDoesNotRestart() async {
        let provider = FakeRelatedProvider(delayed:true), player = FixturePlayer(), library = make(player,provider:provider)
        library.setAutoplayEnabled(true); library.play(testSong(0)); await library.playbackTask?.value
        await waitForRequest(provider); let pending = library.relatedTask
        player.emit(.ended); library.togglePlayback()
        await provider.release(); await pending?.value; await library.playbackTask?.value
        #expect(!library.isPlaying); #expect(player.loads == 1)
        library.setAutoplayEnabled(false); library.setAutoplayEnabled(true)
        #expect(library.relatedTask == nil); #expect(player.loads == 1)
        library.stop()
    }
    @Test func manualNextWaitsForRecommendationsWithoutLosingPause() async {
        let provider = FakeRelatedProvider(delayed:true), player = FixturePlayer(), library = make(player,provider:provider)
        library.setAutoplayEnabled(true); library.play(testSong(0)); await library.playbackTask?.value
        await waitForRequest(provider)
        library.pausePlayback(); library.next()
        await provider.release(); await library.relatedTask?.value; await library.playbackTask?.value
        #expect(library.currentSong == testSong(5)); #expect(!library.isPlaying)
        library.stop()
    }
    @Test func rapidOffOnDiscardsTheOldRequestAndKeepsOnlyNewResults() async {
        let provider = FakeRelatedProvider(delayed:true), player = FixturePlayer(), library = make(player,provider:provider)
        library.setAutoplayEnabled(true); library.play(testSong(0)); await library.playbackTask?.value
        await waitForRequest(provider); let old = library.relatedTask
        library.setAutoplayEnabled(false); library.setAutoplayEnabled(true)
        await waitForRequest(provider,count:2); let new = library.relatedTask
        await provider.release(); await old?.value; await new?.value
        #expect(library.isPlaying); #expect(player.loads == 1)
        library.next(); await ready(library)
        #expect(library.currentSong == testSong(5)); #expect(player.loads == 2); library.stop()
    }
    @Test func nextAndPreviousDuringResolutionRejectStaleLoads() async {
        let player = FixturePlayer(), library = make(player,provider:FakeRelatedProvider(),resolver:SlowAutoplayResolver())
        library.setAutoplayEnabled(true); library.play(testSong(0)); await ready(library)
        let old = library.mediaPlaybackSnapshot.generation
        library.next(); library.next(); library.previous()
        library.receive(old,.ended); library.handleMediaCommand(.next,generation:old)
        await ready(library)
        #expect(library.currentSong == testSong(5)); #expect(player.loads == 2)
        library.stop()
    }
    @Test func sqliteFavoritesQueueAndHistorySurviveAutomaticPlayback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MangoAutoplaySQLite-\(UUID())")
        let suite = "MangoAutoplaySQLite.\(UUID())", defaults:UserDefaults
        defaults = UserDefaults(suiteName:suite)!
        defer { try? FileManager.default.removeItem(at:directory); defaults.removePersistentDomain(forName:suite) }
        let url = directory.appendingPathComponent("library.sqlite3"), player = FixturePlayer()
        let library = MusicLibrary(defaults:defaults,resolver:FixtureResolver(),player:player,
                                   store:SQLiteLibraryStore(url:url),relatedProvider:FakeRelatedProvider())
        await library.restorationTask?.value
        library.toggleFavorite(testSong(0)); library.setAutoplayEnabled(true)
        library.playFavorites(); await ready(library); await complete(library,player)
        #expect(library.currentSong == testSong(5)); #expect(library.currentRecommendationSource == .mix)
        library.enqueue(testSong(2)); let queue = library.queue
        #expect(await library.prepareToQuit())
        let store = SQLiteLibraryStore(url:url), data = try await store.load()
        #expect(data.favorites.map(\.song) == [testSong(0)]); #expect(data.queue == queue)
        #expect(Set(data.history.map { $0.song.id }) == [testSong(0).id,testSong(5).id])
        await store.close()
        let restoredPlayer = FixturePlayer(), restored = MusicLibrary(defaults:defaults,resolver:FixtureResolver(),player:restoredPlayer,
            store:SQLiteLibraryStore(url:url),relatedProvider:FakeRelatedProvider())
        await restored.restorationTask?.value
        #expect(restored.autoplayEnabled); #expect(restored.relatedTask == nil); #expect(restoredPlayer.loads == 0)
        #expect(restored.currentRecommendationSource == nil)
        #expect(await restored.prepareToQuit())
    }
    @Test func fallbackTracksHaveDistinctProvenanceAndToggleOffPreservesCurrentSong() async {
        let player = FixturePlayer(), library = make(player,provider:FakeRelatedProvider(source:.searchFallback))
        library.setAutoplayEnabled(true); library.play(testSong(0)); await ready(library)
        await complete(library,player)
        #expect(library.currentRecommendationSource == .searchFallback)
        library.setAutoplayEnabled(false); #expect(library.isPlaying)
        await complete(library,player); #expect(!library.isPlaying)
    }
}
private struct FailedAutomaticResolver: AudioStreamResolving {
    func resolve(_ song:Song) async throws -> URL {
        if song.id != testSong(0).id { throw PlaybackError.resolution }
        return URL(string:"https://example.com/audio")!
    }
}

private struct SlowAutoplayResolver: AudioStreamResolving {
    func resolve(_ song:Song) async throws -> URL {
        try? await Task.sleep(for:.milliseconds(15))
        return URL(string:"https://example.com/audio")!
    }
}

@MainActor
struct MixAutoplayIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MANGO_MIX_INTEGRATION"] == "1"))
    func liveMixSelectionAndPersistentMPV() async throws {
        let suite = "MangoLiveMix.\(UUID())", defaults:UserDefaults
        defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let connection = MPVConnection(executable:PackagedIntegrationTools.mpv,audioOutput:"null")
        let player = MPVPlaybackEngine(connection:connection)
        let library = MusicLibrary(defaults:defaults,resolver:PackagedIntegrationTools.resolver,player:player,
            relatedProvider:YouTubeMixProvider(executableURL:PackagedIntegrationTools.ytDLP))
        defer { library.shutdown() }
        func wait(_ condition:() -> Bool) async throws {
            let deadline = Date().addingTimeInterval(40)
            while !condition(), Date() < deadline { try await Task.sleep(for:.milliseconds(30)) }
            #expect(condition())
            if !condition() { throw PlaybackError.timeout }
        }
        let seed = Song(id:"youtube:dQw4w9WgXcQ",title:"Never Gonna Give You Up",artist:"Rick Astley",duration:0,durationKnown:false)
        library.setAutoplayEnabled(true); library.play(seed); await library.playbackTask?.value
        try await wait { library.progress > 0 && library.duration > 0 && library.relatedTask != nil }
        let pid = connection.owner.processIdentifier
        await library.relatedTask?.value
        // One bounded batch, then real mpv EOF triggers just-in-time automatic selection.
        library.seek(to:max(0,library.duration - 1))
        try await wait { library.currentSong?.id != seed.id && library.progress > 0 && library.isPlaying }
        #expect(library.currentRecommendationSource == .mix)
        #expect(connection.owner.processIdentifier == pid)
        #expect(library.queue.isEmpty)
        library.stop(); await library.playbackTask?.value
        await connection.shutdown()
    }
}

private struct FailingRelatedProvider: RelatedSongProviding {
    func recommendations(for seed:Song,excluding:Set<String>) async throws -> RelatedSongs {
        throw RecommendationError.throttled
    }
}
