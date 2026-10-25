import Foundation
import Testing
@testable import MangoMusic

@MainActor
struct YouTubePlaybackIntegrationTests {
    /// Canonical public IDs avoid search-ranking changes; only explicit opt-in contacts YouTube.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MANGO_YOUTUBE_DIAGNOSTICS"] == "1"),
          arguments: ["dQw4w9WgXcQ", "9bZkp7q19f0", "jNQXAC9IVRw"])
    func publicVideoPlayback(_ videoID: String) async throws {
        let connection = MPVConnection(audioOutput: "null")
        let player = MPVPlaybackEngine(connection: connection)
        let library = MusicLibrary(player: player)
        defer { library.shutdown() }
        let song = Song(id: "youtube:\(videoID)", title: "Public integration fixture", artist: "YouTube", duration: 0, durationKnown: false)
        library.play(song)
        await library.playbackTask?.value
        try await wait("load", seconds: 50) { !library.isLoading || library.playbackError != nil }
        #expect(library.playbackError == nil)
        guard library.playbackError == nil else { return }
        try await wait("position/duration") { library.isPlaying && library.progress > 0.1 && library.duration > 6 }
        library.togglePlayback(); try await wait("pause") { !library.isPlaying }
        library.togglePlayback(); try await wait("resume") { library.isPlaying }
        var observedVolume = false
        let original = player.onEvent
        player.onEvent = { id, event in
            if case .volume(let volume) = event, abs(volume - 0.25) < 0.01 { observedVolume = true }
            original?(id, event)
        }
        library.setVolume(0.25)
        try await wait("observed volume") { observedVolume }
        if library.duration > 6 {
            library.seek(to: 4); try await wait("seek") { library.progress >= 3 && library.progress < 7 }
        }
        library.stop(); await library.playbackTask?.value
        #expect(!library.isPlaying)
        await connection.shutdown()
    }
    private func wait(_ stage: String, seconds: Double = 15, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
        #expect(condition(), "Timed out: \(stage)")
        if !condition() { throw PlaybackError.timeout }
    }
}
