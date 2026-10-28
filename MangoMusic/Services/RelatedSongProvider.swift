import Foundation
import CoreFoundation

enum RecommendationSource: String, Sendable {
    case mix, searchFallback
    var label: String { self == .mix ? "YouTube Mix" : "Related search" }
}

struct RelatedSongs: Sendable {
    let songs: [Song]
    let source: RecommendationSource
}

protocol RelatedSongProviding: Sendable {
    func recommendations(for seed: Song, excluding: Set<String>) async throws -> RelatedSongs
}

enum RecommendationError: Error, Equatable {
    case unavailable, malformed, failed, throttled, coolingDown
}

/// Separate from stream resolution: only stable public metadata crosses this boundary.
actor YouTubeMixProvider: RelatedSongProviding {
    static let batchLimit = 20
    private let executableURL: URL?
    private let runner: any ProcessRunning
    private var cooldownUntil = Date.distantPast
    private var isFetching = false
    private var cached: (seed: String, batch: RelatedSongs, date: Date)?

    init(executableURL: URL? = nil, runner: any ProcessRunning = FoundationProcessRunner(timeout: 30)) {
        self.executableURL = executableURL
        self.runner = runner
    }

    static func mixURL(_ seed: String) throws -> String {
        let id = try YouTubeVideoID.validate(seed)
        return "https://www.youtube.com/watch?v=\(id)&list=RD\(id)&start_radio=1"
    }

    static func arguments(_ target: String) -> [String] {
        ["--ignore-config", "--no-plugin-dirs", "--no-cache-dir", "--simulate", "--skip-download",
         "--yes-playlist", "--flat-playlist", "--playlist-end", String(batchLimit), "--dump-single-json",
         "--no-progress", "--socket-timeout", "10", "--retries", "1", "--extractor-retries", "1", "--", target]
    }

    func recommendations(for seed: Song, excluding: Set<String>) async throws -> RelatedSongs {
        try Task.checkCancellation()
        guard Date() >= cooldownUntil else { throw RecommendationError.coolingDown }
        let id = try YouTubeVideoID.validate(seed.id)
        if let cached, cached.seed == id, Date().timeIntervalSince(cached.date) < 60 {
            return RelatedSongs(songs: cached.batch.songs.filter { !excluding.contains($0.id) && $0.id != seed.id }, source: cached.batch.source)
        }
        guard !isFetching else { throw RecommendationError.coolingDown }
        isFetching = true
        defer { isFetching = false }
        let executable = try ToolLocator.locate("yt-dlp", override: executableURL)
        do {
            let output = try await runner.run(executable: executable, arguments: Self.arguments(try Self.mixURL(id)))
            try Task.checkCancellation()
            let songs = try Self.decode(output, expectedMix: "RD\(id)")
            cached = (id, RelatedSongs(songs: songs, source: .mix), Date())
            return RelatedSongs(songs: songs.filter { !excluding.contains($0.id) && $0.id != seed.id }, source: .mix)
        } catch RecommendationError.unavailable {
            // Only an explicitly unavailable/empty Mix gets one search. Transport/parse failures do not.
            try Task.checkCancellation()
            let artist = seed.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let term = try SearchQuery.validate(String((artist.isEmpty ? seed.title : artist).prefix(150)) + " official audio")
            do {
                let output = try await runner.run(executable: executable, arguments: Self.arguments("ytsearch20:\(term)"))
                try Task.checkCancellation()
                let songs = try Self.decode(output)
                cached = (id, RelatedSongs(songs: songs, source: .searchFallback), Date())
                return RelatedSongs(songs: songs.filter { !excluding.contains($0.id) && $0.id != seed.id }, source: .searchFallback)
            } catch {
                applyCooldown(error)
                throw error
            }
        } catch {
            applyCooldown(error)
            throw error
        }
    }

    private func applyCooldown(_ error: any Error) {
        guard !(error is CancellationError) else { return }
        cooldownUntil = Date().addingTimeInterval(error as? RecommendationError == .throttled ? 120 : 30)
    }

    static func decode(_ output: ProcessOutput, expectedMix: String? = nil) throws -> [Song] {
        let diagnostic = String(decoding: output.stderr, as: UTF8.self).lowercased()
        if diagnostic.contains("429") || diagnostic.contains("too many requests") || diagnostic.contains("confirm you’re not a bot")
            || diagnostic.contains("confirm you're not a bot") || diagnostic.contains("sign in") {
            throw RecommendationError.throttled
        }
        if output.status != 0 {
            if diagnostic.contains("unviewable") || diagnostic.contains("unavailable") || diagnostic.contains("does not exist") {
                throw RecommendationError.unavailable
            }
            throw RecommendationError.failed
        }
        guard let root = (try? JSONSerialization.jsonObject(with: output.stdout)) as? [String: Any],
              root["_type"] as? String == "playlist", let entries = root["entries"] as? [Any] else {
            throw RecommendationError.malformed
        }
        if let expectedMix, root["id"] as? String != expectedMix { throw RecommendationError.malformed }
        if entries.isEmpty { throw RecommendationError.unavailable }
        var seen = Set<String>(), songs: [Song] = []
        for value in entries.prefix(100) {
            guard let entry = value as? [String: Any], let raw = entry["id"] as? String,
                  let id = try? YouTubeVideoID.validate(raw),
                  let title = entry["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !["[deleted video]", "[private video]"].contains(title.lowercased()),
                  !["is_live", "is_upcoming", "post_live"].contains(entry["live_status"] as? String ?? ""),
                  entry["is_live"] as? Bool != true,
                  entry["availability"] == nil || entry["availability"] is NSNull
                    || ["public", "unlisted"].contains(entry["availability"] as? String ?? "") else { continue }
            var duration: Double?
            if let number = entry["duration"], !(number is NSNull) {
                guard let numeric = number as? NSNumber, CFGetTypeID(numeric) != CFBooleanGetTypeID(),
                      numeric.doubleValue.isFinite, numeric.doubleValue > 0, numeric.doubleValue <= 31_536_000 else { continue }
                duration = numeric.doubleValue
            }
            guard seen.insert(id).inserted else { continue }
            let channel = [entry["channel"], entry["uploader"]].compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? "Unknown channel"
            songs.append(Song(id: "youtube:\(id)", title: String(title.prefix(500)), artist: String(channel.prefix(300)),
                              duration: duration ?? 0, durationKnown: duration != nil))
            if songs.count == batchLimit { break }
        }
        // A malformed batch cannot masquerade as an empty genuine Mix to trigger extra requests.
        guard !songs.isEmpty else { throw RecommendationError.malformed }
        return songs
    }
}
