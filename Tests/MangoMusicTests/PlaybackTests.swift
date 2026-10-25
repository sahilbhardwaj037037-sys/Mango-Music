import Foundation
import Testing
@testable import MangoMusic

struct AudioResolutionTests {
    @Test func identifiers() throws {
        #expect(try YouTubeVideoID.validate("youtube:dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(try YouTubeVideoID.validate("a_B-cD12345") == "a_B-cD12345")
        for input in ["", "123", "../abcdefgh", "https://youtu.be/dQw4w9WgXcQ", "abcdefghij;", "abcdefghijé"] {
            #expect(throws: PlaybackError.invalidVideo) { try YouTubeVideoID.validate(input) }
        }
    }
    @Test func outputValidation() throws {
        #expect(try AudioStreamResolver.decode(Data("https://example.com/audio?temporary=value\n".utf8)).host == "example.com")
        for input in ["", "http://example.com/a", "file:///tmp/a", "https://a.test/\nhttps://b.test/", "https://user:password@a.test/"] {
            #expect(throws: PlaybackError.invalidStream) { try AudioStreamResolver.decode(Data(input.utf8)) }
        }
    }
    @Test func missingTools() async {
        let missing = URL(fileURLWithPath: "/nonexistent/mango-test-tool")
        let resolver = AudioStreamResolver(executableURL: missing)
        await #expect(throws: PlaybackError.missingTool("yt-dlp")) { try await resolver.resolve(testSong(0)) }
        let connection = MPVConnection(executable: missing)
        await #expect(throws: PlaybackError.missingTool("mpv")) {
            try await connection.start(sink: { _, _ in }, failure: { _, _ in })
        }
        await connection.shutdown()
    }
    @Test func resolutionSuccessFailureAndTimeout() async throws {
        let executable = URL(fileURLWithPath: "/usr/bin/true")
        let success = AudioStreamResolver(executableURL: executable, runner: StreamRunner(status: 0))
        #expect(try await success.resolve(testSong(0)).host == "example.com")
        let failed = AudioStreamResolver(executableURL: executable, runner: StreamRunner(status: 1))
        await #expect(throws: PlaybackError.resolution) { try await failed.resolve(testSong(0)) }
        let timeout = AudioStreamResolver(executableURL: executable, runner: StreamRunner(status: -1))
        await #expect(throws: PlaybackError.timeout) { try await timeout.resolve(testSong(0)) }
        let args = AudioStreamResolver.arguments("dQw4w9WgXcQ")
        #expect(args.contains(AudioStreamResolver.preferredAudioFormat)); #expect(args.contains("--skip-download"))
        #expect(!args.contains("--cookies-from-browser"))
    }
    @Test func audioOnlyHLSPreferenceAndFallback() throws {
        let args = AudioStreamResolver.arguments("dQw4w9WgXcQ")
        let index = try #require(args.firstIndex(of: "--format"))
        #expect(args[index + 1] == "bestaudio[protocol^=m3u8]/bestaudio")
        #expect(args.contains("--get-url"))
        #expect(args.contains("--skip-download"))
        #expect(args.contains("--no-playlist"))
        #expect(args.contains("--ignore-config"))
        #expect(!args.contains("--extractor-args"))
        #expect(args.last == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    @Test func malformedIPC() throws {
        for input in ["", "[]", "{}", "not JSON", "{\"request_id\":\"bad\"}", "{\"request_id\":1}"] {
            #expect(throws: PlaybackError.protocolError) { try MPVMessage.decode(Data(input.utf8)) }
        }
        let event = try MPVMessage.decode(Data(#"{"event":"property-change","name":"time-pos","data":12.5}"#.utf8))
        #expect(event.number == 12.5)
        let failed = try MPVMessage.decode(Data(#"{"request_id":4,"error":"failure"}"#.utf8))
        #expect(!failed.success); #expect(failed.request == 4)
    }
    @Test func connectionFailureAndCleanup() async {
        let connection = MPVConnection(executable: URL(fileURLWithPath: "/usr/bin/true"))
        await #expect(throws: (any Error).self) {
            try await connection.start(sink: { _, _ in }, failure: { _, _ in })
        }
        await connection.shutdown()
        await #expect(throws: PlaybackError.connection) { try await connection.command(["get_property", "pause"]) }
    }
    @Test func ownedProcessShutdown() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["30"]
        let owner = OwnedMPVProcess()
        try owner.launch(child, directory: directory)
        #expect(child.isRunning)
        owner.shutdown(); owner.shutdown()
        #expect(!child.isRunning)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        owner.shutdown(permanent: true)
        let another = Process(); another.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        #expect(throws: CancellationError.self) { try owner.launch(another, directory: directory) }
    }
}

private struct StreamRunner: ProcessRunning {
    let status: Int32
    func run(executable: URL, arguments: [String]) async throws -> ProcessOutput {
        if status == -1 { throw SearchError.timedOut }
        return ProcessOutput(stdout: Data("https://example.com/audio\n".utf8), stderr: Data(), status: status)
    }
}

func testSong(_ index: Int) -> Song {
    Song(id: "youtube:abcdefghij\(index)", title: "Test \(index)", artist: "Fixture", duration: 100)
}
struct FixtureResolver: AudioStreamResolving {
    func resolve(_ song: Song) async throws -> URL { URL(string: "https://example.com/audio")! }
}

@MainActor
final class FixturePlayer: AudioPlaying {
    var onEvent: ((UUID, PlaybackEvent) -> Void)?
    var request = UUID()
    var pauses: [Bool] = []
    var seeks: [Double] = []
    var volumes: [Double] = []
    var stops = 0
    var shutdowns = 0
    var loads = 0
    func load(_ url: URL, request: UUID, volume: Double) async throws {
        self.request = request; loads += 1
        onEvent?(request, .loaded); onEvent?(request, .duration(100)); onEvent?(request, .position(0.1))
    }
    func pause(_ paused: Bool) async throws { pauses.append(paused); onEvent?(request, .paused(paused)) }
    func seek(_ position: Double) async throws { seeks.append(position); onEvent?(request, .position(position)) }
    func volume(_ value: Double) async throws { volumes.append(value); onEvent?(request, .volume(value)) }
    func stop() async { stops += 1 }
    func shutdown() { shutdowns += 1 }
    func emit(_ event: PlaybackEvent) { onEvent?(request, event) }
}

@MainActor
struct RealPlaybackModelTests {
    func make(_ player: FixturePlayer, resolver: any AudioStreamResolving = FixtureResolver()) -> MusicLibrary {
        MusicLibrary(defaults: UserDefaults(suiteName: UUID().uuidString)!, resolver: resolver, player: player)
    }
    func settle() async { for _ in 0..<30 { await Task.yield() } }
    @Test func loadingPauseSeekVolumeAndStop() async {
        let player = FixturePlayer(), library = make(player)
        library.play(testSong(0)); #expect(library.isLoading); #expect(!library.isPlaying)
        await library.playbackTask?.value
        #expect(library.isPlaying); #expect(library.duration == 100)
        library.togglePlayback(); await settle()
        #expect(!library.isPlaying); #expect(player.pauses == [true])
        library.togglePlayback(); await settle(); #expect(library.isPlaying)
        library.seek(to: 120); await settle(); #expect(player.seeks == [100]); #expect(library.progress == 100)
        library.setVolume(-2); await settle(); #expect(player.volumes.last == 0)
        library.setVolume(2); await settle(); #expect(player.volumes.last == 1)
        player.emit(.buffering(true)); #expect(library.isBuffering)
        library.stop(); await library.playbackTask?.value; #expect(!library.isPlaying)
        library.shutdown(); #expect(player.shutdowns == 1)
    }
    @Test func directPlayQueueCompletionAndDuplicateEvents() async {
        let player = FixturePlayer(), library = make(player)
        library.enqueue(testSong(1)); library.playNext(testSong(2)); library.play(testSong(0))
        await library.playbackTask?.value
        #expect(library.queue.map(\.song) == [testSong(2), testSong(1)])
        let old = player.request
        player.emit(.ended); library.receive(old, .ended)
        await library.playbackTask?.value
        #expect(library.currentSong == testSong(2)); #expect(library.queue.count == 1)
        player.emit(.ended); await library.playbackTask?.value
        #expect(library.currentSong == testSong(1)); #expect(library.queue.isEmpty)
        player.emit(.ended); #expect(!library.isPlaying); #expect(player.loads == 3)
        player.emit(.loaded); #expect(!library.isPlaying)
    }
    @Test func nextPreviousAndQueueEdits() async {
        let player = FixturePlayer(), library = make(player)
        library.play(testSong(0)); await library.playbackTask?.value
        library.enqueue(testSong(1)); library.next(); await library.playbackTask?.value
        player.emit(.position(5)); library.previous(); await settle(); #expect(player.seeks.last == 0)
        player.emit(.position(0)); library.previous(); await library.playbackTask?.value
        #expect(library.currentSong == testSong(0))
        library.next(); await library.playbackTask?.value; #expect(!library.isPlaying)
        library.enqueue(testSong(2)); library.removeQueueEntry(library.queue[0].id); #expect(library.queue.isEmpty)
    }
    @Test func failureRequiresRetryAndDoesNotSkip() async {
        let player = FixturePlayer(), library = make(player)
        library.enqueue(testSong(1)); library.play(testSong(0)); await library.playbackTask?.value
        player.emit(.failure("Audio unavailable")); await settle()
        #expect(library.playbackError == "Audio unavailable"); #expect(!library.isPlaying)
        player.emit(.ended); #expect(library.queue.count == 1)
        library.retryPlayback(); await library.playbackTask?.value
        #expect(library.playbackError == nil); #expect(library.isPlaying); #expect(player.loads == 2)
    }
    @Test func cancellationAndStaleResolution() async {
        let resolver = DelayedResolver(), player = FixturePlayer(), library = make(player, resolver: resolver)
        library.play(testSong(0)); await resolver.started()
        library.play(testSong(1)); await resolver.finish()
        await library.playbackTask?.value
        #expect(library.currentSong == testSong(1)); #expect(player.loads == 1)
        library.receive(UUID(), .failure("stale")); #expect(library.playbackError == nil)
        library.stop(); await library.playbackTask?.value
        #expect(!library.isPlaying)
    }
}
private actor DelayedResolver: AudioStreamResolving {
    private var didStart = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<URL, Never>?
    func resolve(_ song: Song) async throws -> URL {
        if song == testSong(0) {
            // Deliberately ignores cancellation: caller must reject stale results.
            return await withCheckedContinuation { continuation in
                pending = continuation; didStart = true
                waiting?.resume(); waiting = nil
            }
        }
        return URL(string: "https://example.com/audio")!
    }
    func started() async {
        if didStart { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func finish() { pending?.resume(returning: URL(string: "https://example.com/audio")!); pending = nil }
}
