import Foundation
import Testing
@testable import MangoMusic

/// Explicitly opt in: ordinary `swift test` never requires installed tools or the network.
@MainActor
struct MPVIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MANGO_MPV_INTEGRATION"] == "1"))
    func localAudioIPC() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mango-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: file) }
        // Eight seconds of PCM silence exercises actual demuxing and the playback clock, without an audible claim.
        let samples = 8 * 8000
        var bytes = Data()
        func ascii(_ text: String) { bytes.append(contentsOf: text.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) }
        }
        ascii("RIFF"); integer(UInt32(36 + samples * 2)); ascii("WAVEfmt ")
        integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1)); integer(UInt32(8000))
        integer(UInt32(16000)); integer(UInt16(2)); integer(UInt16(16))
        ascii("data"); integer(UInt32(samples * 2)); bytes.append(Data(count: samples * 2))
        try bytes.write(to: file)
        let connection = MPVConnection(audioOutput: "null"), player = MPVPlaybackEngine(connection: connection)
        defer { player.shutdown() }
        var events: [PlaybackEvent] = []
        player.onEvent = { _, event in events.append(event) }
        try await player.load(file, request: UUID(), volume: 0.3)
        try await wait { events.contains(.loaded) && events.contains(where: { if case .position(let p) = $0 { return p > 0.1 }; return false }) }
        #expect(events.contains(where: { if case .duration(let d) = $0 { return d >= 7.9 }; return false }))
        try await player.pause(true); try await wait { events.contains(.paused(true)) }
        try await player.pause(false); try await wait { events.contains(.paused(false)) }
        try await player.volume(0.2); try await wait { events.contains(.volume(0.2)) }
        try await player.seek(7.5); try await wait { events.contains(.ended) }
        #expect(events.filter { $0 == .ended }.count == 1)
        // Reuse the same connection/process for another load.
        events.removeAll()
        try await player.load(file, request: UUID(), volume: 0.4)
        try await wait { events.contains(.loaded) }
        await player.stop()
        #expect(!events.contains(.ended))
        // Exercise production manual queue transitions against real mpv events using local audio.
        let library = MusicLibrary(resolver: LocalResolver(url: file), player: player)
        library.enqueue(testSong(0)); library.enqueue(testSong(1)); library.next()
        await library.playbackTask?.value
        try await wait { library.isPlaying && library.duration > 0 }
        library.seek(to: 7.5)
        try await wait { library.queue.isEmpty }
        await library.playbackTask?.value
        try await wait { library.isPlaying && library.duration > 0 }
        library.seek(to: 7.5)
        try await wait { !library.isPlaying }
        #expect(library.history.count == 2); #expect(library.queue.isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!library.isPlaying); #expect(library.currentSong == testSong(1))
        library.shutdown()
        await connection.shutdown()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MANGO_YOUTUBE_INTEGRATION"] == "1"))
    func youtubeManualQueue() async throws {
        let connection = MPVConnection(audioOutput: "null")
        let player = MPVPlaybackEngine(connection: connection)
        let library = MusicLibrary(player: player)
        defer { library.shutdown() }
        library.query = "Rick Astley Never Gonna Give You Up official"
        library.search(); await library.searchTask?.value
        let song = try #require(library.results.first)
        library.enqueue(song); library.enqueue(song)
        library.next(); await library.playbackTask?.value
        try await wait(seconds: 55) { !library.isLoading || library.playbackError != nil }
        #expect(library.playbackError == nil)
        guard library.playbackError == nil else { return }
        try await wait(seconds: 20) { library.duration > 0 && library.progress > 0 }
        library.togglePlayback(); try await wait { !library.isPlaying }
        library.togglePlayback(); try await wait { library.isPlaying }
        library.setVolume(0.2)
        library.seek(to: max(0, library.duration - 1))
        try await wait(seconds: 55) { library.queue.isEmpty || library.playbackError != nil }
        await library.playbackTask?.value
        try await wait(seconds: 55) { library.duration > 0 && !library.isLoading || library.playbackError != nil }
        #expect(library.playbackError == nil)
        guard library.playbackError == nil else { return }
        library.seek(to: max(0, library.duration - 1))
        try await wait(seconds: 20) { !library.isPlaying }
        #expect(library.queue.isEmpty); #expect(library.history.count == 2)
        await connection.shutdown()
    }

    private func wait(seconds: Double = 12, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
        #expect(condition())
        if !condition() { throw PlaybackError.timeout }
    }
}

private struct LocalResolver: AudioStreamResolving {
    let url: URL
    func resolve(_ song: Song) async throws -> URL { url }
}
