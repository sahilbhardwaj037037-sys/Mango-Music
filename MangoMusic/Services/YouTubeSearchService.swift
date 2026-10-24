import Foundation

protocol SongSearching: Sendable {
    func search(query: String) async throws -> [Song]
}

enum SearchError: Error, LocalizedError, Equatable {
    case invalidQuery, missingExecutable, malformedOutput, processFailed(Int32)
    case launchFailed, timedOut, outputTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidQuery: "Enter 1–200 characters without control characters."
        case .missingExecutable: "yt-dlp was not found. Install it in a supported location, then retry."
        case .malformedOutput: "YouTube returned an unreadable search response. Please retry."
        case .processFailed: "YouTube search failed. Check your connection and yt-dlp installation, then retry."
        case .launchFailed: "yt-dlp could not start. Check its executable permissions and Python installation."
        case .timedOut: "YouTube search timed out. Check your connection, then retry."
        case .outputTooLarge: "The search response exceeded the safety limit. Please retry."
        }
    }
}

enum SearchQuery {
    static func validate(_ input: String) throws -> String {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 200,
              query.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw SearchError.invalidQuery
        }
        return query
    }
}

struct YouTubeSearchService: SongSearching {
    /// Only fixed, trusted installation locations are considered; no shell or metadata-derived commands.
    static let supportedPaths = [
        "/Library/Frameworks/Python.framework/Versions/3.14/bin/yt-dlp",
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp"
    ]
    var executableURL: URL?
    var runner: any ProcessRunning = FoundationProcessRunner()

    func search(query: String) async throws -> [Song] {
        let query = try SearchQuery.validate(query)
        try Task.checkCancellation()
        let candidates = executableURL.map { [$0] }
            ?? Self.supportedPaths.map { URL(fileURLWithPath: $0) }
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else { throw SearchError.missingExecutable }
        let output = try await runner.run(executable: executable, arguments: Self.arguments(for: query))
        try Task.checkCancellation()
        guard output.status == 0 else { throw SearchError.processFailed(output.status) }
        return try decode(output.stdout)
    }

    static func arguments(for query: String) -> [String] {
        ["--ignore-config", "--no-plugin-dirs", "--no-cache-dir", "--simulate",
         "--skip-download", "--flat-playlist", "--dump-single-json", "--no-progress",
         "--socket-timeout", "15", "--retries", "1", "--extractor-retries", "1",
         "--", "ytsearch10:\(query)"]
    }

    func decode(_ data: Data) throws -> [Song] {
        let response: SearchResponse
        do { response = try JSONDecoder().decode(SearchResponse.self, from: data) }
        catch { throw SearchError.malformedOutput }
        var seen = Set<String>()
        let songs = response.entries.compactMap { entry -> Song? in
            guard let entry, let id = entry.id, id.count == 11,
                  id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                      || (97...122).contains($0) || $0 == 45 || $0 == 95 }),
                  let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty, seen.insert(id).inserted else { return nil }
            let duration = entry.duration.flatMap { $0.isFinite && $0 > 0 && $0 <= 31_536_000 ? $0 : nil }
            let artist = [entry.channel, entry.uploader, entry.artist]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "Unknown channel"
            return Song(id: "youtube:\(id)", title: title, artist: artist,
                        duration: duration ?? 0, durationKnown: duration != nil)
        }
        if !response.entries.isEmpty && songs.isEmpty { throw SearchError.malformedOutput }
        return Array(songs.prefix(10))
    }

    private struct SearchResponse: Decodable {
        let entries: [Video?]
    }
    private struct Video: Decodable {
        let id: String?
        let title: String?
        let channel: String?
        let uploader: String?
        let artist: String?
        let duration: Double?
    }
}
