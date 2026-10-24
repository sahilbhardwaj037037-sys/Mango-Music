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
    var isPlaying = false
    var progress: TimeInterval = 0
    var volume: Double = 0.7
    var searchFocusRequest = 0
    private let defaults: UserDefaults
    private var previousSongs: [Song] = []
    var sidebarVisible: Bool {
        didSet { defaults.set(sidebarVisible, forKey: "sidebarVisible") }
    }

    init(defaults: UserDefaults = .standard, searchService: any SongSearching = YouTubeSearchService()) {
        self.searchService = searchService
        self.defaults = defaults
        sidebarVisible = defaults.object(forKey: "sidebarVisible") as? Bool ?? true
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

    private func beginPlayback(_ song: Song) {
        currentSong = song
        progress = 0
        isPlaying = true
        history.insert(HistoryEntry(song: song, playedAt: .now), at: 0)
        if history.count > 100 { history.removeLast(history.count - 100) }
    }

    func playQueueEntry(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        play(queue.remove(at: index).song)
    }

    func togglePlayback() {
        if let currentSong {
            if progress >= currentSong.duration { progress = 0 }
            isPlaying.toggle()
        }
        else if !queue.isEmpty { next() }
    }

    func next() {
        guard !queue.isEmpty else { isPlaying = false; return }
        play(queue.removeFirst().song)
    }

    func previous() {
        if progress > 3 { progress = 0 }
        else if let song = previousSongs.popLast() { beginPlayback(song) }
        else { progress = 0 }
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

    func tick() {
        guard isPlaying, let song = currentSong, song.duration > 0 else { return }
        progress = min(progress + 1, song.duration)
        if progress >= song.duration { next() }
    }
}
