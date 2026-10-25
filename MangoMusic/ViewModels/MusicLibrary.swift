import SwiftUI
import Observation

enum SearchState: Equatable {
    case idle, loading, loaded, empty, cancelled, failure(String)
}

@MainActor @Observable
final class MusicLibrary {
    var destination: Destination = .search
    var query = ""
    private(set) var results: [Song] = []
    private(set) var searchState: SearchState = .idle
    private(set) var submittedQuery = ""
    @ObservationIgnored private let searchService: any SongSearching
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?
    private var searchID = UUID()
    private var knownSongs = Dictionary(uniqueKeysWithValues: Song.samples.map { ($0.id, $0) })
    var queue: [QueueEntry] = []
    var favoriteIDs: Set<String> = []
    var history: [HistoryEntry] = []
    var currentSong: Song?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var isBuffering = false
    private(set) var playbackError: String?
    private(set) var duration: TimeInterval = 0
    @ObservationIgnored private let resolver: any AudioStreamResolving
    @ObservationIgnored private let player: any AudioPlaying
    @ObservationIgnored private(set) var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var controlTask: Task<Void, Never>?
    private var playbackID = UUID()
    private var ended = true
    private var loaded = false
    var progress: TimeInterval = 0
    var volume: Double = 0.7
    var searchFocusRequest = 0
    private let defaults: UserDefaults
    private var previousSongs: [Song] = []
    var sidebarVisible: Bool {
        didSet { defaults.set(sidebarVisible, forKey: "sidebarVisible") }
    }

    init(defaults: UserDefaults = .standard, searchService: any SongSearching = YouTubeSearchService(),
         resolver: any AudioStreamResolving = AudioStreamResolver(), player: (any AudioPlaying)? = nil) {
        self.resolver = resolver
        self.player = player ?? MPVPlaybackEngine()
        self.searchService = searchService
        self.defaults = defaults
        sidebarVisible = defaults.object(forKey: "sidebarVisible") as? Bool ?? true
        self.player.onEvent = { [weak self] id, event in self?.receive(id, event) }
    }

    var favorites: [Song] {
        knownSongs.values.filter { favoriteIDs.contains($0.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func search() {
        cancelSearch()
        let term: String
        do { term = try SearchQuery.validate(query) }
        catch {
            submittedQuery = ""
            searchState = .failure(SearchError.invalidQuery.localizedDescription)
            results = []
            return
        }
        submittedQuery = term
        results = []
        searchState = .loading
        let request = UUID()
        searchID = request
        let service = searchService
        searchTask = Task { [weak self] in
            do {
                let songs = try await service.search(query: term)
                guard let self, self.searchID == request, !Task.isCancelled else { return }
                self.results = songs
                self.searchState = songs.isEmpty ? .empty : .loaded
            } catch {
                guard let self, self.searchID == request else { return }
                if error is CancellationError || Task.isCancelled {
                    self.searchState = .cancelled
                } else {
                    self.searchState = .failure((error as? SearchError)?.localizedDescription
                        ?? "Search failed. Please retry.")
                }
            }
        }
    }

    func cancelSearch() {
        searchID = UUID()
        searchTask?.cancel()
        searchTask = nil
        if searchState == .loading { searchState = .cancelled }
    }

    func clearSearch() {
        cancelSearch()
        query = ""
        submittedQuery = ""
        results = []
        searchState = .idle
    }

    func retrySearch() {
        guard !submittedQuery.isEmpty else { return }
        query = submittedQuery
        search()
    }

    func focusSearch() {
        destination = .search
        searchFocusRequest += 1
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
    }

    func toggleFavorite(_ song: Song) {
        knownSongs[song.id] = song
        if !favoriteIDs.insert(song.id).inserted { favoriteIDs.remove(song.id) }
    }

    func enqueue(_ song: Song) { queue.append(QueueEntry(song: song)) }

    func play(_ song: Song) {
        if let currentSong { previousSongs.append(currentSong) }
        beginPlayback(song)
    }

    func playNext(_ song: Song) { queue.insert(QueueEntry(song: song), at: 0) }

    private func beginPlayback(_ song: Song) {
        let previousTask = playbackTask
        let previousControl = controlTask
        previousTask?.cancel()
        controlTask?.cancel()
        let request = UUID()
        playbackID = request
        currentSong = song
        progress = 0
        duration = 0
        isPlaying = false
        isLoading = true
        isBuffering = false
        playbackError = nil
        ended = false
        loaded = false
        let resolver = resolver, player = player
        playbackTask = Task { [weak self] in
            // Serialize transitions, including a cancelled mpv startup, to retain one owned process.
            await previousTask?.value
            await previousControl?.value
            guard !Task.isCancelled else { return }
            await player.stop()
            do {
                let url = try await resolver.resolve(song)
                try Task.checkCancellation()
                guard let self, self.playbackID == request else { return }
                try await player.load(url, request: request, volume: self.volume)
                try Task.checkCancellation()
            } catch {
                guard let self, self.playbackID == request, !Task.isCancelled else { return }
                self.fail((error as? PlaybackError)?.localizedDescription ?? PlaybackError.playback.localizedDescription)
            }
        }
    }

    func receive(_ request: UUID, _ event: PlaybackEvent) {
        guard request == playbackID, !ended, playbackError == nil else { return }
        switch event {
        case .loaded:
            guard !loaded else { return }
            loaded = true; isLoading = false; isPlaying = true
            if let currentSong {
                history.insert(HistoryEntry(song: currentSong, playedAt: .now), at: 0)
                if history.count > 100 { history.removeLast(history.count - 100) }
            }
        case .position(let value): progress = value
        case .duration(let value): duration = value
        case .paused(let value): if loaded { isPlaying = !value }
        case .buffering(let value): isBuffering = value
        case .volume(let value): volume = min(1, max(0, value))
        case .ended:
            ended = true; isPlaying = false; isLoading = false; isBuffering = false
            if !queue.isEmpty { next() }
        case .failure(let message): fail(message)
        }
    }

    private func fail(_ message: String) {
        playbackError = message
        isPlaying = false; isLoading = false; isBuffering = false
        let player = player
        controlTask = Task { await player.stop() }
    }

    func retryPlayback() {
        guard let currentSong else { return }
        beginPlayback(currentSong)
    }

    func playQueueEntry(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        play(queue.remove(at: index).song)
    }

    func togglePlayback() {
        if currentSong == nil { if !queue.isEmpty { next() }; return }
        if playbackError != nil || ended { retryPlayback(); return }
        guard loaded, !isLoading else { return }
        let pause = isPlaying
        performControl { try await $0.pause(pause) }
    }

    func seek(to value: Double) {
        guard loaded, duration > 0, value.isFinite else { return }
        let position = min(duration, max(0, value))
        performControl { try await $0.seek(position) }
    }

    func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        volume = min(1, max(0, value))
        guard loaded else { return }
        let volume = volume
        performControl { try await $0.volume(volume) }
    }

    private func performControl(_ action: @escaping @MainActor (any AudioPlaying) async throws -> Void) {
        let request = playbackID, previous = controlTask, player = player
        controlTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, self.playbackID == request else { return }
            do { try await action(player) }
            catch { if self.playbackID == request { self.fail(PlaybackError.command.localizedDescription) } }
        }
    }

    func stop() {
        playbackID = UUID(); playbackTask?.cancel(); controlTask?.cancel()
        isPlaying = false; isLoading = false; isBuffering = false; ended = true
        let previous = playbackTask, player = player
        playbackTask = Task { await previous?.value; await player.stop() }
    }

    func shutdown() {
        cancelSearch(); playbackID = UUID(); playbackTask?.cancel(); controlTask?.cancel()
        player.shutdown()
    }

    func next() {
        guard !queue.isEmpty else { stop(); return }
        play(queue.removeFirst().song)
    }

    func previous() {
        if progress > 3 { seek(to: 0) }
        else if let song = previousSongs.popLast() { beginPlayback(song) }
        else { seek(to: 0) }
    }

    func removeQueueEntry(_ id: UUID) { queue.removeAll { $0.id == id } }

    func moveQueueEntry(_ id: UUID, before target: UUID) {
        guard id != target,
              let source = queue.firstIndex(where: { $0.id == id }) else { return }
        let entry = queue.remove(at: source)
        guard let destination = queue.firstIndex(where: { $0.id == target }) else {
            queue.insert(entry, at: min(source, queue.count)); return
        }
        queue.insert(entry, at: destination)
    }

}
