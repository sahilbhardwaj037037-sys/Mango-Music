import Foundation
import MediaPlayer
import AppKit
import Testing
@testable import MangoMusic

@MainActor
private final class MediaAdapterFixture: SystemMediaAdapting {
    var handler: (@MainActor @Sendable (MediaCommand, UUID) -> Void)?
    var commands: Set<MediaCommandKind> = []
    var generation = UUID()
    var metadata: NowPlayingMetadata?
    var state: SystemPlaybackState = .stopped
    var registrations = 0, removals = 0, publications = 0
    func activate(_ handler: @escaping @MainActor @Sendable (MediaCommand, UUID) -> Void) { registrations += 1; self.handler = handler }
    func setCommands(_ commands: Set<MediaCommandKind>, generation: UUID) { self.commands = commands; self.generation = generation }
    func publish(_ metadata: NowPlayingMetadata?, state: SystemPlaybackState) { self.metadata = metadata; self.state = state; publications += 1 }
    func deactivate() { handler = nil; commands = []; metadata = nil; state = .stopped; removals += 1 }
    func send(_ command: MediaCommand, generation: UUID? = nil) { handler?(command, generation ?? self.generation) }
}
@MainActor
private final class LifecycleFixture: PlaybackLifecycleMonitoring {
    var handler: (@MainActor @Sendable (PlaybackInterruption) -> Void)?
    var registrations = 0, removals = 0
    func activate(_ handler: @escaping @MainActor @Sendable (PlaybackInterruption) -> Void) { self.handler = handler; registrations += 1 }
    func deactivate() { handler = nil; removals += 1 }
    func send(_ reason: PlaybackInterruption) { handler?(reason) }
}
@MainActor
private final class MediaPlayerFixture: AudioPlaying {
    var onEvent: ((UUID, PlaybackEvent) -> Void)?
    var request = UUID()
    var loads = 0, interrupts = 0, shutdowns = 0
    var initialPauses: [Bool] = [], pauses: [Bool] = [], seeks: [Double] = []
    var delayPauses = false
    func load(_ url: URL, request: UUID, volume: Double, paused: Bool) async throws {
        self.request = request; loads += 1; initialPauses.append(paused)
        emit(.loaded); emit(.duration(120)); emit(.paused(paused))
        if !paused { emit(.position(0.1)) }
    }
    func pause(_ paused: Bool) async throws {
        let id = request
        if delayPauses { try await Task.sleep(for: .milliseconds(3)) }
        pauses.append(paused); onEvent?(id, .paused(paused))
    }
    func seek(_ position: Double) async throws { seeks.append(position); emit(.position(position)); emit(.clockAnchor) }
    func volume(_ value: Double) async throws { emit(.volume(value)) }
    func stop() async {}
    func interrupt() { interrupts += 1 }
    func shutdown() { shutdowns += 1 }
    func emit(_ event: PlaybackEvent) { onEvent?(request, event) }
}
private actor MediaResolverFixture: AudioStreamResolving {
    var waiting: CheckedContinuation<URL, Never>?
    var didStart = false
    let delayed: Bool
    init(delayed: Bool = false) { self.delayed = delayed }
    func resolve(_ song: Song) async throws -> URL {
        didStart = true
        if delayed { return await withCheckedContinuation { waiting = $0 } }
        return URL(string: "https://example.com/fixture")!
    }
    func started() -> Bool { didStart }
    func release() { waiting?.resume(returning: URL(string: "https://example.com/fixture")!); waiting = nil }
}

@MainActor
struct SystemMediaTests {
    private func make(player: MediaPlayerFixture, resolver: any AudioStreamResolving = MediaResolverFixture()) -> MusicLibrary {
        MusicLibrary(defaults: UserDefaults(suiteName: "MangoSystemMediaTests.\(UUID())")!, resolver: resolver, player: player)
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        #expect(condition())
        if !condition() { throw PlaybackError.timeout }
    }
    private func snapshot(_ phase: MediaPlaybackPhase = .playing, generation: UUID = UUID(),
                          title: String? = "Title", artist: String? = "Channel", duration: Double? = 100,
                          elapsed: Double = 2, revision: Int = 0) -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(generation: generation, phase: phase, title: title, artist: artist,
                              duration: duration, elapsed: elapsed, positionRevision: revision, commands: [])
    }

    @Test func ownedPlayerDoesNotRegisterCompetingSystemControlsOrPreventSleep() {
        let args = MPVConnection.arguments(socketPath: "/tmp/fixture-private/ipc")
        #expect(args.contains("--media-controls=no"))
        #expect(args.contains("--input-media-keys=no"))
        #expect(args.contains("--stop-screensaver=no"))
        #expect(args.contains("--idle=yes"))
    }
    @Test func metadataMappingUsesOnlyPublicFieldsAndActualClock() throws {
        let mapped = try #require(snapshot(elapsed: 12).metadata)
        let dictionary = NativeSystemMediaAdapter.dictionary(mapped)
        #expect(dictionary[MPMediaItemPropertyTitle] as? String == "Title")
        #expect(dictionary[MPMediaItemPropertyArtist] as? String == "Channel")
        #expect(dictionary[MPMediaItemPropertyPlaybackDuration] as? Double == 100)
        #expect(dictionary[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 12)
        #expect(dictionary[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        #expect(dictionary[MPMediaItemPropertyArtwork] == nil)
        #expect(dictionary.count == 7)
        #expect(snapshot(.paused).metadata?.rate == 0)
        #expect(snapshot(.buffering).metadata?.rate == 0)
        #expect(snapshot(.loading).systemState == .paused)
        #expect(snapshot(.failed).metadata == nil)
        #expect(snapshot(.stopped).metadata == nil)
    }
    @Test func metadataHandlesMissingAndInvalidValues() throws {
        let data = try #require(snapshot(title: " ", artist: "\n", duration: .nan, elapsed: .infinity).metadata)
        #expect(data.title == "Unknown title"); #expect(data.artist == nil); #expect(data.duration == nil); #expect(data.elapsed == 0)
        let dictionary = NativeSystemMediaAdapter.dictionary(data)
        #expect(dictionary[MPMediaItemPropertyArtist] == nil); #expect(dictionary[MPMediaItemPropertyPlaybackDuration] == nil)
        #expect(snapshot(duration: nil, elapsed: 4).metadata?.elapsed == 4)
        #expect(snapshot(duration: 2, elapsed: 9).metadata?.elapsed == 2)
        #expect(snapshot(title: nil).metadata == nil)
    }
    @Test func publicationThrottlesOrdinaryClockButPublishesSeekAndStateImmediately() {
        var policy = NowPlayingPublicationPolicy(); let id = UUID()
        func publish(_ value: MediaPlaybackSnapshot, now: Double) -> Bool { policy.shouldPublish(value, now: now) }
        #expect(publish(snapshot(generation: id, elapsed: 0), now: 0))
        for step in 1..<100 {
            let time = Double(step) / 100
            #expect(!publish(snapshot(generation: id, elapsed: time), now: time))
        }
        #expect(publish(snapshot(generation: id, elapsed: 5), now: 5))
        #expect(publish(snapshot(.paused, generation: id, elapsed: 5), now: 5.1))
        #expect(publish(snapshot(.paused, generation: id, elapsed: 5.2, revision: 1), now: 5.2))
        #expect(publish(snapshot(.stopped, generation: id), now: 5.3))
    }
    @Test func registrationsSurviveWindowCyclesAndTeardownIsIdempotent() async throws {
        let player = MediaPlayerFixture(), library = make(player: player), adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle)
        let delegate = MusicApplicationDelegate()
        delegate.attach(library, integration: integration)
        // Simulate repeated SwiftUI onAppear / Dock window reconstruction; no view owns handlers.
        delegate.attach(library, integration: integration); integration.start()
        #expect(adapter.registrations == 1); #expect(lifecycle.registrations == 1)
        library.play(testSong(0)); await library.playbackTask?.value
        adapter.send(.pause); try await wait { !library.isPlaying }
        #expect(delegate.library === library); #expect(adapter.metadata?.title == testSong(0).title)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        integration.stop()
        #expect(adapter.removals == 1); #expect(lifecycle.removals == 1)
        #expect(adapter.metadata == nil); #expect(player.shutdowns == 1)
        integration.start(); #expect(adapter.registrations == 2); integration.stop()
    }
    @Test func favoritesNavigationPublishesCommandsAcrossWindowCycles() async throws {
        let player = MediaPlayerFixture(), library = make(player: player), adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle)
        let delegate = MusicApplicationDelegate()
        delegate.attach(library, integration: integration)
        library.toggleFavorite(testSong(0)); library.toggleFavorite(testSong(1))
        library.playFavorites(); await library.playbackTask?.value
        delegate.attach(library, integration: integration) // A rebuilt window retains the playlist/controller.
        #expect(adapter.registrations == 1); #expect(adapter.commands.contains(.next))
        library.cycleRepeatMode()
        adapter.send(.pause); try await wait { !library.isPlaying }
        adapter.send(.next); await library.playbackTask?.value
        #expect(library.currentSong?.id == testSong(1).id); #expect(player.initialPauses.last == true)
        #expect(adapter.metadata?.title == testSong(1).title)
        #expect(!adapter.commands.contains(.next))
        adapter.send(.previous); await library.playbackTask?.value
        #expect(library.currentSong?.id == testSong(0).id); #expect(player.initialPauses.last == true)
        library.cycleRepeatMode() // Repeat All exposes Next even on the final favorite.
        adapter.send(.next); await library.playbackTask?.value
        #expect(adapter.commands.contains(.next))
        adapter.send(.stop); #expect(adapter.metadata == nil)
        integration.stop(); library.shutdown()
    }

    @Test func remotePlayPauseAreIdempotentAndUIFollowsEvents() async throws {
        let player = MediaPlayerFixture(), library = make(player: player), adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle); integration.start(); defer { integration.stop() }
        #expect(adapter.commands.isEmpty)
        library.enqueue(testSong(0)); #expect(adapter.commands.contains(.play))
        adapter.send(.play); await library.playbackTask?.value
        #expect(adapter.state == .playing); #expect(adapter.commands.contains(.pause))
        adapter.send(.pause); adapter.send(.pause)
        try await wait { player.pauses.count == 1 }
        #expect(!library.isPlaying); #expect(adapter.state == .paused)
        adapter.send(.play); adapter.send(.play)
        try await wait { player.pauses.count == 2 }
        #expect(library.isPlaying); #expect(player.pauses == [true, false]); #expect(player.loads == 1)
        adapter.send(.stop); #expect(adapter.metadata == nil); #expect(!adapter.commands.contains(.seek))
    }
    @Test func rapidTogglesUseIntentUntilDelayedAcknowledgementsArrive() async throws {
        let player = MediaPlayerFixture(); player.delayPauses = true
        let library = make(player: player), adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle); integration.start(); defer { integration.stop() }
        library.play(testSong(0)); await library.playbackTask?.value
        for _ in 0..<10 { adapter.send(.toggle) }
        try await wait { player.pauses.count == 10 }
        #expect(player.pauses == [true,false,true,false,true,false,true,false,true,false])
        #expect(library.isPlaying); #expect(player.loads == 1); #expect(library.history.first?.playCount == 1)
    }
    @Test func seekWhilePausedUsesActualPositionAndRemainsPaused() async throws {
        let player = MediaPlayerFixture(), library = make(player: player), adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle); integration.start(); defer { integration.stop() }
        library.play(testSong(0)); await library.playbackTask?.value
        adapter.send(.pause); try await wait { !library.isPlaying }
        adapter.send(.seek(20)); try await wait { library.progress == 20 }
        #expect(!library.isPlaying); #expect(adapter.metadata?.elapsed == 20); #expect(adapter.metadata?.rate == 0)
        let seekCount = player.seeks.count
        adapter.send(.seek(.nan)); adapter.send(.seek(-1))
        #expect(player.seeks.count == seekCount)
        #expect(library.history.first?.playCount == 1)
    }
    @Test func nextWhileBufferingAndOldCompletionAdvanceOnlyOnce() async throws {
        let player = MediaPlayerFixture(), library = make(player: player), adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle); integration.start(); defer { integration.stop() }
        library.play(testSong(0)); await library.playbackTask?.value
        library.enqueue(testSong(1)); library.enqueue(testSong(2)); let old = player.request
        player.emit(.buffering(true)); #expect(adapter.metadata?.rate == 0)
        adapter.send(.next); library.receive(old, .ended); adapter.send(.next, generation: old)
        await library.playbackTask?.value
        #expect(library.currentSong?.id == testSong(1).id); #expect(library.queue.map(\.song.id) == [testSong(2).id])
        let active = player.request
        player.emit(.ended); adapter.send(.next, generation: active); library.receive(active, .ended)
        await library.playbackTask?.value
        #expect(library.currentSong?.id == testSong(2).id); #expect(library.queue.isEmpty)
        player.emit(.ended); #expect(adapter.metadata == nil); #expect(!library.isPlaying)
    }
    @Test func previousAndNextPreservePauseWithoutBrieflyStartingAudio() async throws {
        let player = MediaPlayerFixture(), library = make(player: player), adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle); integration.start(); defer { integration.stop() }
        library.play(testSong(0)); await library.playbackTask?.value
        library.play(testSong(1)); await library.playbackTask?.value
        adapter.send(.pause); try await wait { !library.isPlaying }
        player.emit(.position(0)); adapter.send(.previous); await library.playbackTask?.value
        #expect(library.currentSong?.id == testSong(0).id); #expect(player.initialPauses.last == true); #expect(!library.isPlaying)
        library.enqueue(testSong(2)); adapter.send(.next); await library.playbackTask?.value
        #expect(player.initialPauses.last == true); #expect(!library.isPlaying)
    }
    @Test func pauseDuringResolutionPreventsLateStartAndKeepsManualItem() async throws {
        let resolver = MediaResolverFixture(delayed: true), player = MediaPlayerFixture()
        let library = make(player: player, resolver: resolver), adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle); integration.start(); defer { integration.stop() }
        library.enqueue(testSong(0)); let entry = library.queue[0]
        adapter.send(.play)
        let deadline = Date().addingTimeInterval(2)
        while !(await resolver.started()), Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        #expect(await resolver.started())
        #expect(adapter.commands.contains(.pause)); #expect(!adapter.commands.contains(.seek))
        adapter.send(.pause); await resolver.release(); await library.playbackTask?.value
        #expect(player.loads == 0); #expect(library.queue == [entry]); #expect(adapter.metadata == nil)
    }
    @Test func sleepWakeAndOutputChangesNeverAutoplayOrSkip() async throws {
        let player = MediaPlayerFixture(), library = make(player: player), adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle); integration.start(); defer { integration.stop() }
        library.play(testSong(0)); await library.playbackTask?.value
        library.enqueue(testSong(1)); let queue = library.queue, old = player.request
        lifecycle.send(.sleep)
        #expect(player.interrupts == 1); #expect(adapter.commands.isEmpty); #expect(adapter.metadata == nil)
        library.receive(old, .ended); lifecycle.send(.wake)
        #expect(player.loads == 1); #expect(!library.isPlaying); #expect(library.queue == queue)
        adapter.send(.play); await library.playbackTask?.value
        #expect(player.loads == 2); #expect(library.playbackNotice == nil)
        lifecycle.send(.outputChanged); #expect(player.interrupts == 2); #expect(!library.isPlaying)
        #expect(adapter.metadata == nil); #expect(library.queue == queue)
    }
    @Test func idleSleepInvalidatesPreSleepPlayAndReleasesTheOwnedPlayer() async throws {
        let player = MediaPlayerFixture(), library = make(player: player), adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle); integration.start(); defer { integration.stop() }
        library.play(testSong(0)); await library.playbackTask?.value
        adapter.send(.stop); await library.playbackTask?.value
        let old = adapter.generation
        lifecycle.send(.sleep); lifecycle.send(.wake)
        adapter.send(.play, generation: old)
        #expect(player.loads == 1); #expect(player.interrupts == 1); #expect(!library.isPlaying)
        adapter.send(.play); await library.playbackTask?.value
        #expect(player.loads == 2)
    }

    @Test func failureClearsMetadataRetryRepublishesAndRetainsQueue() async throws {
        let player = MediaPlayerFixture(), library = make(player: player), adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle); integration.start(); defer { integration.stop() }
        library.enqueue(testSong(1)); library.play(testSong(0)); await library.playbackTask?.value
        player.emit(.failure("Playback failed"))
        #expect(adapter.metadata == nil); #expect(adapter.commands.contains(.play)); #expect(library.queue.count == 1)
        adapter.send(.play); await library.playbackTask?.value
        #expect(adapter.metadata?.title == testSong(0).title); #expect(player.loads == 2)
        #expect(library.history.first?.playCount == 1)
        player.emit(.failure("Failed while playing")); adapter.send(.next); await library.playbackTask?.value
        #expect(player.initialPauses.last == false); #expect(library.isPlaying)
    }
    @Test func backgroundRemoteCallbackRunsControllerOnTheMainActor() async throws {
        let player = MediaPlayerFixture(), library = make(player: player), gate = MediaCommandGate()
        library.play(testSong(0)); await library.playbackTask?.value
        gate.activate { command, generation in
            #expect(Thread.isMainThread)
            library.handleMediaCommand(command, generation: generation)
        }
        gate.update(library.playbackCapabilities, generation: library.mediaPlaybackSnapshot.generation)
        #expect(await Task.detached { gate.submit(.pause) }.value)
        try await wait { !library.isPlaying }
        #expect(player.pauses == [true]); gate.deactivate()
    }

    @Test func commandGateValidatesAndCancelsOldRegistrationCallbacks() async throws {
        let gate = MediaCommandGate(), id = UUID()
        var calls = 0
        gate.activate { _, generation in #expect(generation == id); calls += 1 }
        gate.update([.play, .seek], generation: id)
        #expect(!gate.submit(.pause)); #expect(!gate.submit(.seek(.nan))); #expect(!gate.submit(.seek(-2)))
        #expect(gate.submit(.play)); try await wait { calls == 1 }
        #expect(gate.submit(.play)); gate.deactivate()
        gate.activate { _, _ in calls += 100 }; gate.update([.play], generation: id)
        try await Task.sleep(for: .milliseconds(10))
        #expect(calls == 1); gate.deactivate(); #expect(!gate.submit(.play))
    }

    @Test func sleepDuringPendingQueuePreservesSQLiteAndNeverStartsLateAudio() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MangoMediaStore-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.sqlite3")
        let player = MediaPlayerFixture(), resolver = MediaResolverFixture(delayed: true)
        let library = MusicLibrary(defaults: UserDefaults(suiteName: "MangoMediaStore.\(UUID())")!, resolver: resolver,
                                   player: player, store: SQLiteLibraryStore(url: url))
        let adapter = MediaAdapterFixture(), lifecycle = LifecycleFixture()
        let integration = SystemMediaIntegration(library: library, adapter: adapter, lifecycle: lifecycle)
        integration.start(); defer { integration.stop() }
        await library.restorationTask?.value
        library.enqueue(testSong(0)); library.enqueue(testSong(1)); let entries = library.queue
        library.next()
        let deadline = Date().addingTimeInterval(2)
        while !(await resolver.started()), Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        #expect(await resolver.started())
        lifecycle.send(.sleep); await resolver.release(); await library.playbackTask?.value
        #expect(player.loads == 0); #expect(library.queue == entries); #expect(library.history.isEmpty)
        lifecycle.send(.wake); #expect(await library.prepareToQuit())
        let reopened = SQLiteLibraryStore(url: url), snapshot = try await reopened.load()
        #expect(snapshot.queue == entries); #expect(snapshot.history.isEmpty)
        await reopened.close()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MANGO_NATIVE_MEDIA_INTEGRATION"] == "1"))
    func nativeOutputListenerRegistrationAndCleanup() {
        let monitor = NativePlaybackLifecycle()
        monitor.activate { _ in }
        #expect(monitor.isMonitoringOutput)
        monitor.activate { _ in }
        monitor.deactivate(); monitor.deactivate()
        #expect(!monitor.isMonitoringOutput)
        #expect(monitor.lastRemovalStatus == 0)
        // This checks listener installation only; physical routing and sleep/wake remain manual.
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MANGO_NATIVE_MEDIA_INTEGRATION"] == "1"))
    func nativeMediaPlayerAPIAcceptsMetadataCommandsAndCleanup() throws {
        let adapter = NativeSystemMediaAdapter(), center = MPNowPlayingInfoCenter.default(), commands = MPRemoteCommandCenter.shared()
        adapter.activate { _, _ in }; defer { adapter.deactivate() }
        adapter.activate { _, _ in }
        #expect(adapter.registeredHandlerCount == 7)
        adapter.setCommands([.pause,.next,.seek], generation: UUID())
        #expect(commands.pauseCommand.isEnabled); #expect(!commands.playCommand.isEnabled); #expect(commands.changePlaybackPositionCommand.isEnabled)
        let metadata = try #require(snapshot(elapsed: 3).metadata)
        adapter.publish(metadata, state: .playing)
        #expect(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Title")
        #expect(center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 3)
        #expect(center.playbackState == .playing)
        adapter.publish(snapshot(.paused).metadata, state: .paused); #expect(center.playbackState == .paused)
        adapter.deactivate(); #expect(adapter.registeredHandlerCount == 0); #expect(center.nowPlayingInfo == nil)
        #expect(!commands.pauseCommand.isEnabled)
        // Public API readback proves runtime acceptance, not Control Center rendering/hardware delivery.
    }
}
