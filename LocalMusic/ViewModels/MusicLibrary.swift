import SwiftUI
import Observation

@MainActor @Observable
final class MusicLibrary {
    var destination: Destination = .search
    var query = ""
    var results = Song.samples
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sidebarVisible = defaults.object(forKey: "sidebarVisible") as? Bool ?? true
    }

    var favorites: [Song] { Song.samples.filter { favoriteIDs.contains($0.id) } }

    func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = Array(Song.samples.filter {
            term.isEmpty || $0.title.localizedCaseInsensitiveContains(term)
                || $0.artist.localizedCaseInsensitiveContains(term)
        }.prefix(10))
    }

    func focusSearch() {
        destination = .search
        searchFocusRequest += 1
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
    }

    func toggleFavorite(_ song: Song) {
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
        guard isPlaying, let song = currentSong else { return }
        progress = min(progress + 1, song.duration)
        if progress >= song.duration { next() }
    }
}
