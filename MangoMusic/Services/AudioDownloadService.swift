import Foundation

protocol AudioDownloading: Sendable {
    func download(source: URL, stage: URL, existingBytes: Int64, limits: DownloadLimits,
                  progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL
}

struct VerifiedConversionTools: Sendable {
    let ffmpeg: URL
    let ffprobe: URL
    static func discover(bundleURL: URL = Bundle.main.bundleURL,
                         bundled: Bool = Bundle.main.object(forInfoDictionaryKey: "MangoBundledTools") as? Bool == true) -> Self? {
        func tool(_ name: String) -> URL? {
            guard let found = try? ToolLocator.locate(name, bundleURL: bundleURL, requiresBundledTools: bundled) else { return nil }
            let url = bundled ? found : found.resolvingSymlinksInPath()
            guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? file.close() }
            let magic = (try? file.read(upToCount: 4)) ?? Data()
            guard [Data([0xcf,0xfa,0xed,0xfe]),Data([0xca,0xfe,0xba,0xbe]),Data([0xca,0xfe,0xba,0xbf])].contains(magic) else { return nil }
            return url
        }
        guard let ffmpeg = tool("ffmpeg"), let ffprobe = tool("ffprobe"),
              ffmpeg.deletingLastPathComponent() == ffprobe.deletingLastPathComponent() else { return nil }
        return Self(ffmpeg: ffmpeg, ffprobe: ffprobe)
    }
}
struct YTAudioDownloadService: AudioDownloading {
    var executable: URL?
    var runner: any DownloadProcessRunning = DownloadProcessRunner()
    var conversionTools: VerifiedConversionTools? = VerifiedConversionTools.discover()

    static func arguments(source: URL, stage: URL, limits: DownloadLimits, tools: VerifiedConversionTools?) -> [String] {
        var args = ["--ignore-config", "--no-plugin-dirs", "--no-cache-dir", "--no-playlist",
                    "--format", "bestaudio[protocol^=m3u8]/bestaudio[ext=m4a]/bestaudio", "--max-filesize", String(limits.perFile),
                    "--part", "--no-continue", "--no-overwrites", "--hls-prefer-native", "--hls-use-mpegts",
                    "--socket-timeout", "15", "--retries", "1", "--fragment-retries", "1", "--extractor-retries", "1",
                    "--newline", "--progress", "--progress-delta", "0.5", "--progress-template", "download:MANGO_PROGRESS:%(progress)j",
                    "--paths", stage.path, "--output", "audio.%(ext)s"]
        if let tools { args += ["--ffmpeg-location", tools.ffmpeg.deletingLastPathComponent().path, "--fixup", "detect_or_warn"] }
        else { args += ["--fixup", "never"] }
        return args + ["--", source.absoluteString]
    }
    func download(source: URL, stage: URL, existingBytes: Int64, limits: DownloadLimits,
                  progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        try Task.checkCancellation()
        let executable = try ToolLocator.locate("yt-dlp", override: executable)
        let check: @Sendable () throws -> Void = { try ManagedDownloadFiles.checkSpace(stage: stage, limits: limits, existingBytes: existingBytes) }
        try await runner.run(executable: executable, arguments: Self.arguments(source: source, stage: stage, limits: limits, tools: conversionTools),
                             directory: stage, timeout: limits.timeout, progress: progress, check: check)
        try Task.checkCancellation()
        let candidates = try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            .filter { $0.lastPathComponent.hasPrefix("audio.") && !$0.lastPathComponent.contains(".part") && !$0.lastPathComponent.contains(".ytdl") }
        guard candidates.count == 1, let file = candidates.first else { throw DownloadError.invalidAudio }
        let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true else { throw DownloadError.unsafePath }
        if ManagedDownloadFiles.extensions.contains(file.pathExtension) { return file }
        // Unneeded conversions never run; unsupported containers need verified native helper executables.
        guard let tools = conversionTools else { throw DownloadError.tools }
        let info = try await FoundationProcessRunner(timeout: 15).run(executable: tools.ffprobe,
            arguments: ["-v", "error", "-show_entries", "stream=codec_type", "-of", "json", file.path])
        guard info.status == 0, let data = try? JSONSerialization.jsonObject(with: info.stdout) as? [String: Any],
              let streams = data["streams"] as? [[String: Any]], !streams.isEmpty,
              streams.allSatisfy({ $0["codec_type"] as? String == "audio" }) else { throw DownloadError.invalidAudio }
        let output = stage.appendingPathComponent("audio.m4a")
        try await runner.run(executable: tools.ffmpeg,
            arguments: ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-i", file.path, "-vn", "-c:a", "aac", "-b:a", "192k", output.path],
            directory: stage, timeout: min(120, limits.timeout), progress: { _ in }, check: check)
        try Task.checkCancellation()
        try FileManager.default.removeItem(at: file)
        return output
    }
}
