import Foundation
import Darwin
import Testing
@testable import MangoMusic

private func generatedWAV(seconds: Int = 4) -> Data {
    let samples = seconds * 8000
    var bytes = Data()
    func ascii(_ text: String) { bytes.append(contentsOf: text.utf8) }
    func integer<T: FixedWidthInteger>(_ number: T) {
        var number = number.littleEndian
        withUnsafeBytes(of: &number) { bytes.append(contentsOf: $0) }
    }
    ascii("RIFF"); integer(UInt32(36 + samples * 2)); ascii("WAVEfmt ")
    integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1)); integer(UInt32(8000))
    integer(UInt32(16000)); integer(UInt16(2)); integer(UInt16(16)); ascii("data"); integer(UInt32(samples * 2))
    bytes.append(Data(count: samples * 2)); return bytes
}
private final class DownloadHTTPFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MangoDownloadHTTP-\(UUID())")
    let process = Process()
    let base: URL
    init(hls: Bool = false) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try generatedWAV().write(to: directory.appendingPathComponent("fixture.wav"))
        if hls {
            let encoder = Process(); encoder.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            encoder.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", directory.appendingPathComponent("fixture.wav").path,
                "-c:a", "aac", "-hls_time", "1", "-hls_playlist_type", "vod", "-hls_segment_filename", directory.appendingPathComponent("segment%02d.ts").path,
                directory.appendingPathComponent("fixture.m3u8").path]
            encoder.standardOutput = FileHandle.nullDevice; encoder.standardError = FileHandle.nullDevice
            try encoder.run()
            let deadline = Date().addingTimeInterval(10)
            while encoder.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            if encoder.isRunning { encoder.terminate(); throw PlaybackError.timeout }
            guard encoder.terminationStatus == 0 else { throw DownloadError.invalidAudio }
            try "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=96000,CODECS=\"mp4a.40.2\"\nfixture.m3u8\n".write(to: directory.appendingPathComponent("master.m3u8"), atomically: true, encoding: .utf8)
        }
        let script = directory.appendingPathComponent("server.py")
        try """
        import http.server, pathlib, sys, time
        root=pathlib.Path(sys.argv[1])
        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self,*a,**kw): super().__init__(*a,directory=str(root),**kw)
            def log_message(self,*a): pass
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        (root/'port').write_text(str(server.server_port))
        server.serve_forever()
        """.write(to: script, atomically: true, encoding: .utf8)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, directory.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.environment = ["PATH":"/usr/bin:/bin", "HOME":directory.path, "PYTHONNOUSERSITE":"1"]
        try process.run()
        let portFile = directory.appendingPathComponent("port"), deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: portFile.path), process.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard let port = try? String(contentsOf: portFile, encoding: .utf8) else { process.terminate(); throw PlaybackError.timeout }
        base = URL(string: "http://127.0.0.1:\(port)")!
    }
    func stopServer() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
    }
    deinit { stopServer(); try? FileManager.default.removeItem(at: directory) }
}

struct DownloadProcessTests {
    @Test func processGroupCancellationReapsOwnedChildren() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MangoProcess-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = DownloadProcessRunner()
        let task = Task {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 30 & echo $! > child.pid; wait"], directory: directory, timeout: 10, progress: { _ in }, check: {})
        }
        let pidURL = directory.appendingPathComponent("child.pid"), deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: pidURL.path), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let text = try String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let child = try #require(Int32(text))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let cleanupDeadline = Date().addingTimeInterval(3)
        while Darwin.kill(child, 0) == 0, Date() < cleanupDeadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(Darwin.kill(child,0) == -1 && errno == ESRCH)
    }
    @Test func timeoutAndStorageFailureAreBounded() async throws {
        let directory = FileManager.default.temporaryDirectory
        let runner = DownloadProcessRunner()
        await #expect(throws: DownloadError.timeout) {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], directory: directory,
                                 timeout: 0.05, progress: { _ in }, check: {})
        }
        await #expect(throws: DownloadError.noSpace) {
            try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], directory: directory,
                                 timeout: 1, progress: { _ in }, check: { throw DownloadError.noSpace })
        }
    }
}

@MainActor
struct DownloadIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MANGO_DOWNLOAD_INTEGRATION"] == "1"))
    func generatedHTTPDownloadValidationAndOfflinePlayback() async throws {
        let fixture = try await DownloadHTTPFixture()
        let files = ManagedDownloadFiles(root: fixture.directory.appendingPathComponent("Downloads"))
        let attempt = UUID(), stage = try await files.stage(attempt)
        let service = YTAudioDownloadService(executable: PackagedIntegrationTools.ytDLP, conversionTools: nil)
        let source = fixture.base.appendingPathComponent("fixture.wav")
        let downloaded = try await service.download(source: source, stage: stage, existingBytes: 0, limits: DownloadLimits(timeout: 30), progress: { _ in })
        #expect(try Data(contentsOf: downloaded) == generatedWAV())
        let validator = MPVAudioFileValidator(executable: PackagedIntegrationTools.mpv)
        let audio = try await validator.validate(downloaded)
        #expect(audio.duration >= 3.9)
        var record = DownloadRecord(song: testSong(0), sourceURL: URL(string:"https://www.youtube.com/watch?v=abcdefghij0")!, attempt: attempt)
        let (size, hash) = try await files.inspectStage(attempt, name: downloaded.lastPathComponent, limit: 1_000_000)
        record.relativePath = try await files.relativePath(for: record, extension: downloaded.pathExtension)
        record.fileSize = size; record.checksum = hash; record.format = audio.format; record.downloadedAt = .now
        try await files.publish(record, name: downloaded.lastPathComponent); record.status = .complete
        try await files.cleanStage(attempt)
        let local = try await files.localFile(record, limit: 1_000_000)
        fixture.stopServer() // Playback no longer has even the source server available.
        let connection = MPVConnection(executable: PackagedIntegrationTools.mpv, audioOutput: "null")
        let player = MPVPlaybackEngine(connection: connection); defer { player.shutdown() }
        var playing = false
        player.onEvent = { _, event in if case .position(let value) = event, value > 0.1 { playing = true } }
        try await player.load(local, request: UUID(), volume: 0)
        let deadline = Date().addingTimeInterval(10)
        while !playing, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(playing)
        let localPID = connection.owner.processIdentifier
        // Per-file network restrictions must reset for the next ordinary streaming selection.
        let onlineFixture = try await DownloadHTTPFixture()
        playing = false
        try await player.load(onlineFixture.base.appendingPathComponent("fixture.wav"), request: UUID(), volume: 0)
        let streamDeadline = Date().addingTimeInterval(10)
        while !playing, Date() < streamDeadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(playing); #expect(connection.owner.processIdentifier == localPID)
        onlineFixture.stopServer()
        await connection.shutdown()
        let corrupt = fixture.directory.appendingPathComponent("bad.wav"); try Data([1,2,3]).write(to: corrupt)
        await #expect(throws: (any Error).self) { try await validator.validate(corrupt) }
        let remotePlaylist = fixture.directory.appendingPathComponent("playlist.m3u8")
        try "#EXTM3U\n#EXTINF:4,\nhttp://127.0.0.1:9/remote.wav\n".write(to: remotePlaylist, atomically: true, encoding: .utf8)
        await #expect(throws: (any Error).self) { try await validator.validate(remotePlaylist) }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MANGO_DOWNLOAD_INTEGRATION"] == "1" && FileManager.default.isExecutableFile(atPath:"/opt/homebrew/bin/ffmpeg")))
    func generatedHLSWithoutFFmpegInDownloadPath() async throws {
        let fixture = try await DownloadHTTPFixture(hls: true)
        let files = ManagedDownloadFiles(root: fixture.directory.appendingPathComponent("Downloads")), stage = try await files.stage(UUID())
        let service = YTAudioDownloadService(executable: PackagedIntegrationTools.ytDLP, conversionTools: nil)
        let file = try await service.download(source: fixture.base.appendingPathComponent("master.m3u8"), stage: stage,
            existingBytes: 0, limits: DownloadLimits(timeout: 30), progress: { _ in })
        fixture.stopServer()
        let validated = try await MPVAudioFileValidator(executable: PackagedIntegrationTools.mpv).validate(file)
        #expect(validated.duration >= 3.8)
    }
}
