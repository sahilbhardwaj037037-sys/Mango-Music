import Foundation

enum PlaybackError: Error, LocalizedError, Equatable {
    case invalidVideo, missingTool(String), resolution, invalidStream, connection, protocolError, command, playback, timeout
    var errorDescription: String? {
        switch self {
        case .invalidVideo: "This song has an invalid YouTube identifier. Choose another result."
        case .missingTool(let tool): "\(tool) is missing or damaged. Rebuild the packaged app, or check your development tool installation."
        case .resolution: "Audio could not be resolved. Check your connection and yt-dlp version. The video may be unavailable or restricted."
        case .invalidStream: "YouTube returned an invalid audio stream. Retry to request a fresh stream."
        case .connection: "Could not connect to the audio player. Retry to restart it."
        case .protocolError: "The audio player returned an unreadable response. Retry to restart it."
        case .command: "The audio player could not perform that action. Retry playback."
        case .playback: "Audio playback failed. Check your connection or audio output, then Retry for a fresh stream."
        case .timeout: "The audio request timed out. Check your connection and retry."
        }
    }
}

enum ToolLocator {
    static func locate(_ name: String, override: URL? = nil,
                       bundleURL: URL = Bundle.main.bundleURL,
                       requiresBundledTools: Bool = Bundle.main.object(forInfoDictionaryKey: "MangoBundledTools") as? Bool == true) throws -> URL {
        if override == nil, requiresBundledTools {
            let tool = bundleURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
            let values = try? tool.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true,
                  FileManager.default.isExecutableFile(atPath: tool.path),
                  let handle = try? FileHandle(forReadingFrom: tool) else { throw PlaybackError.missingTool(name) }
            defer { try? handle.close() }
            // Helpers must be native Mach-O files (including a verified universal executable), not scripts.
            let magic = (try? handle.read(upToCount: 32)) ?? Data()
            guard magic.count == 32, [Data([0xcf, 0xfa, 0xed, 0xfe]), Data([0xca, 0xfe, 0xba, 0xbe]),
                   Data([0xca, 0xfe, 0xba, 0xbf])].contains(magic.prefix(4)) else { throw PlaybackError.missingTool(name) }
            return tool
        }
        let paths = override.map { [$0.path] } ?? candidates(name)
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw PlaybackError.missingTool(name)
        }
        return URL(fileURLWithPath: path)
    }
    static func runtimePath(for executable: URL) -> String {
        if executable.deletingLastPathComponent().path.hasSuffix(".app/Contents/MacOS") {
            return executable.deletingLastPathComponent().path + ":/usr/bin:/bin"
        }
        return "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    }
    static func candidates(_ name: String) -> [String] {
        var paths = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        if name == "yt-dlp" {
            let root = "/Library/Frameworks/Python.framework/Versions"
            let versions = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            paths += versions.sorted(by: >).map { "\(root)/\($0)/bin/yt-dlp" }
        }
        // GUI applications need fixed installation candidates; accept absolute PATH entries too.
        paths += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .filter { $0.hasPrefix("/") }.map { "\($0)/\(name)" }
        return paths
    }
}

enum YouTubeVideoID {
    static func validate(_ input: String) throws -> String {
        let id = input.hasPrefix("youtube:") ? String(input.dropFirst(8)) : input
        guard id.utf8.count == 11, id.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }) else { throw PlaybackError.invalidVideo }
        return id
    }
}

protocol AudioStreamResolving: Sendable {
    func resolve(_ song: Song) async throws -> URL
}

struct AudioStreamResolver: AudioStreamResolving {
    // Some public YouTube videos reject fresh direct HTTPS audio URLs (403) while
    // their advertised audio-only HLS streams play. Prefer HLS; retain audio-only
    // fallback for videos without HLS. No client override, cookies, or retry loop.
    static let preferredAudioFormat = "bestaudio[protocol^=m3u8]/bestaudio"
    var executableURL: URL?
    var runner: any ProcessRunning = FoundationProcessRunner()

    func resolve(_ song: Song) async throws -> URL {
        let id = try YouTubeVideoID.validate(song.id)
        let executable = try ToolLocator.locate("yt-dlp", override: executableURL)
        do {
            let output = try await runner.run(executable: executable, arguments: Self.arguments(id))
            try Task.checkCancellation()
            guard output.status == 0 else { throw PlaybackError.resolution }
            return try Self.decode(output.stdout)
        } catch is CancellationError { throw CancellationError() }
        catch SearchError.timedOut { throw PlaybackError.timeout }
        catch let error as PlaybackError { throw error }
        catch { throw PlaybackError.resolution }
    }

    static func arguments(_ id: String) -> [String] {
        ["--ignore-config", "--no-plugin-dirs", "--no-cache-dir", "--no-playlist", "--skip-download",
         "--no-progress", "--socket-timeout", "15", "--retries", "1", "--extractor-retries", "1",
         "--format", preferredAudioFormat, "--get-url", "--", "https://www.youtube.com/watch?v=\(id)"]
    }
    static func decode(_ data: Data) throws -> URL {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains("\n"), !text.contains("\r"),
              let url = URL(string: text), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { throw PlaybackError.invalidStream }
        return url
    }
}
