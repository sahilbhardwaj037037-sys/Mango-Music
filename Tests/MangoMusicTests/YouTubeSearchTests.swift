import Foundation
import Testing
@testable import MangoMusic

struct YouTubeSearchTests {
    let service = YouTubeSearchService()

    @Test func decodeMetadataAndUnknownDuration() throws {
        let data = Data(#"{"entries":[{"id":"abcdefghijk","title":"A song","channel":"Channel","uploader":"Uploader","duration":123.5},{"id":"lmnopqrstuv","title":"Live","uploader":"Other","duration":null}]}"#.utf8)
        let songs = try service.decode(data)
        #expect(songs.count == 2)
        #expect(songs[0].id == "youtube:abcdefghijk")
        #expect(songs[0].artist == "Channel")
        #expect(songs[0].duration == 123.5)
        #expect(songs[1].artist == "Other")
        #expect(songs[1].durationLabel == "—")
    }

    @Test func emptyResults() throws {
        #expect(try service.decode(Data(#"{"entries":[]}"#.utf8)).isEmpty)
    }

    @Test(arguments: ["not json", "{}", #"{"entries":null}"#, #"{"entries":[{"id":"invalid","title":"x"}]}"#,
                      #"{"entries":[{"id":"abcdefghijk","title":"x","duration":"bad"}]}"#])
    func malformedOutput(_ json: String) {
        #expect(throws: SearchError.malformedOutput) { try service.decode(Data(json.utf8)) }
    }

    @Test func duplicateAndInvalidEntriesAreNotDisplayed() throws {
        let json = #"{"entries":[null,{"id":"abcdefghijk","title":"Song","duration":1e100},{"id":"abcdefghijk","title":"Duplicate"},{"id":"bad","title":"Invalid"}]}"#
        let songs = try service.decode(Data(json.utf8))
        #expect(songs.count == 1)
        #expect(!songs[0].durationKnown)
    }

    @Test func resultLimit() throws {
        let entries = (0..<15).map { ["id": String(format: "%011d", $0), "title": "Song \($0)"] }
        let data = try JSONSerialization.data(withJSONObject: ["entries": entries])
        #expect(try service.decode(data).count == 10)
    }

    @Test(arguments: ["", "   ", "a\nb", "a\u{0}b", String(repeating: "x", count: 201)])
    func invalidQuery(_ query: String) {
        #expect(throws: SearchError.invalidQuery) { try SearchQuery.validate(query) }
    }

    @Test func queryIsOneLiteralArgumentAndConfigsAreDisabled() async throws {
        let runner = StubRunner(status: 0, data: Data(#"{"entries":[]}"#.utf8))
        let search = YouTubeSearchService(executableURL: URL(fileURLWithPath: "/usr/bin/true"), runner: runner)
        let query = "--exec $(touch /tmp/never-created) ' ; 日本語"
        _ = try await search.search(query: query)
        let arguments = await runner.arguments
        #expect(arguments.last == "ytsearch10:\(query)")
        #expect(arguments[arguments.count - 2] == "--")
        #expect(arguments.contains("--ignore-config"))
        #expect(arguments.contains("--no-plugin-dirs"))
        #expect(arguments.contains("--skip-download"))
        #expect(arguments.contains("--simulate"))
        #expect(!arguments.contains(query))
    }

    @Test func missingExecutable() async {
        let search = YouTubeSearchService(executableURL: URL(fileURLWithPath: "/nonexistent/mangomusic-yt-dlp"))
        await #expect(throws: SearchError.missingExecutable) { try await search.search(query: "music") }
    }

    @Test func subprocessFailureIsSafe() async {
        let search = YouTubeSearchService(executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                                         runner: StubRunner(status: 1, data: Data()))
        await #expect(throws: SearchError.processFailed(1)) { try await search.search(query: "music") }
    }

    @Test func processRunnerDrainsBothPipes() async throws {
        let output = try await FoundationProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/awk"),
            arguments: ["BEGIN { for (i=0; i<20000; i++) { print \"out\"; print \"e\" > \"/dev/stderr\" } }"])
        #expect(output.status == 0)
        #expect(output.stdout.count == 80000)
        #expect(output.stderr.count == 40000)
    }

    @Test func processRunnerCancellation() async {
        let task = Task {
            try await FoundationProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func processRunnerTimeout() async {
        await #expect(throws: SearchError.timedOut) {
            try await FoundationProcessRunner(timeout: 0.05).run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        }
    }

    @Test func boundedOutput() async {
        await #expect(throws: SearchError.outputTooLarge) {
            try await FoundationProcessRunner(outputLimit: 16).run(executable: URL(fileURLWithPath: "/usr/bin/printf"),
                                                                  arguments: ["%s", String(repeating: "x", count: 100)])
        }
    }

    @Test func launchFailure() async {
        await #expect(throws: SearchError.launchFailed) {
            try await FoundationProcessRunner().run(executable: URL(fileURLWithPath: "/nonexistent/executable"), arguments: [])
        }
    }
}

actor StubRunner: ProcessRunning {
    let status: Int32
    let data: Data
    private(set) var arguments: [String] = []
    init(status: Int32, data: Data) { self.status = status; self.data = data }
    func run(executable: URL, arguments: [String]) async throws -> ProcessOutput {
        self.arguments = arguments
        return ProcessOutput(stdout: data, stderr: Data("untrusted server diagnostics".utf8), status: status)
    }
}

/// Deliberately ignores cancellation to prove that request identity protects the UI.
actor ControlledSearch: SongSearching {
    private var pending: [String: CheckedContinuation<[Song], Error>] = [:]
    private var startedWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    func search(query: String) async throws -> [Song] {
        try await withCheckedThrowingContinuation { continuation in
            pending[query] = continuation
            startedWaiters.removeValue(forKey: query)?.resume()
        }
    }
    func started(_ query: String) async {
        if pending[query] != nil { return }
        await withCheckedContinuation { startedWaiters[query] = $0 }
    }
    func finish(_ query: String, with result: Result<[Song], Error>) {
        pending.removeValue(forKey: query)?.resume(with: result)
    }
}

@MainActor struct SearchStateTests {
    func library(_ service: any SongSearching) -> MusicLibrary {
        MusicLibrary(defaults: UserDefaults(suiteName: "MangoMusicTests.\(UUID().uuidString)")!, searchService: service, resolver: FixtureResolver(), player: FixturePlayer())
    }

    @Test func noSearchOnInitializationOrTyping() async {
        let service = ControlledSearch()
        let library = library(service)
        library.query = "typed but not submitted"
        #expect(library.searchState == .idle)
        #expect(library.searchTask == nil)
        #expect(library.results.isEmpty)
    }

    @Test func staleResultsCannotReplaceNewerResults() async {
        let service = ControlledSearch()
        let library = library(service)
        library.query = "old"
        library.search()
        let old = library.searchTask
        await service.started("old")
        #expect(library.searchState == .loading)
        library.query = "new"
        library.search()
        await service.started("new")
        await service.finish("new", with: .success([Song.samples[1]]))
        await library.searchTask?.value
        #expect(library.searchState == .loaded)
        await service.finish("old", with: .success([Song.samples[0]]))
        await old?.value
        #expect(library.results == [Song.samples[1]])
        #expect(library.submittedQuery == "new")
    }

    @Test func cancellationAndClearIgnoreLateResponses() async {
        let service = ControlledSearch()
        let library = library(service)
        library.query = "pending"
        library.search()
        let task = library.searchTask
        await service.started("pending")
        library.cancelSearch()
        #expect(library.searchState == .cancelled)
        await service.finish("pending", with: .success([Song.samples[0]]))
        await task?.value
        #expect(library.results.isEmpty)
        library.clearSearch()
        #expect(library.searchState == .idle)
        #expect(library.query.isEmpty)
    }

    @Test func failureRetryAndEmptyTransitions() async {
        let service = ControlledSearch()
        let library = library(service)
        library.query = "music"
        library.search()
        await service.started("music")
        await service.finish("music", with: .failure(SearchError.timedOut))
        await library.searchTask?.value
        #expect(library.searchState == .failure(SearchError.timedOut.localizedDescription))
        library.query = "unsubmitted edit"
        library.retrySearch()
        #expect(library.query == "music")
        await service.started("music")
        await service.finish("music", with: .success([]))
        await library.searchTask?.value
        #expect(library.searchState == .empty)
    }

    @Test func invalidInputDoesNotRetryAnOlderQuery() async {
        let library = library(ControlledSearch())
        library.query = "\n"
        library.search()
        #expect(library.searchTask == nil)
        #expect(library.submittedQuery.isEmpty)
        #expect(library.searchState == .failure(SearchError.invalidQuery.localizedDescription))
        library.retrySearch()
        #expect(library.searchTask == nil)
    }

    @Test func staleErrorsCannotReplaceNewerSuccess() async {
        let service = ControlledSearch()
        let library = library(service)
        library.query = "old"
        library.search()
        let old = library.searchTask
        await service.started("old")
        library.query = "new"
        library.search()
        await service.started("new")
        await service.finish("new", with: .success([Song.samples[0]]))
        await library.searchTask?.value
        await service.finish("old", with: .failure(SearchError.timedOut))
        await old?.value
        #expect(library.searchState == .loaded)
        #expect(library.results == [Song.samples[0]])
    }

    @Test func realSongsRemainInFavoritesAfterNewSearch() async {
        let library = library(ControlledSearch())
        let song = Song(id: "youtube:abcdefghijk", title: "Real title", artist: "Channel", duration: 0, durationKnown: false)
        library.toggleFavorite(song)
        library.clearSearch()
        #expect(library.favorites == [song])
        library.enqueue(song)
        library.togglePlayback()
        library.stop()
        #expect(library.currentSong == song)
        #expect(library.progress == 0)
    }
}
