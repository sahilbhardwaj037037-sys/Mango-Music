import SwiftUI
import Observation

enum RepeatMode: String, CaseIterable {
    case off, one, all
    var label: String { "Repeat " + rawValue.capitalized }
    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

enum HistoryRetention: String, CaseIterable, Identifiable {
    case never, sevenDays, thirtyDays, ninetyDays
    var id: Self { self }
    var days: Int? {
        switch self {
        case .never: nil
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        }
    }
    var label: String { days.map { "After \($0) days" } ?? "Never" }
}

enum HistoryLimit: String, CaseIterable, Identifiable {
    case unlimited, hundred, fiveHundred
    var id: Self { self }
    var count: Int? {
        switch self {
        case .unlimited: nil
        case .hundred: 100
        case .fiveHundred: 500
        }
    }
    var label: String { count.map { "\($0) songs" } ?? "Unlimited" }
}

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
    private(set) var queue: [QueueEntry] = []
    private(set) var favoriteIDs: Set<String> = []
    private(set) var history: [HistoryEntry] = []
    private(set) var historyRetention: HistoryRetention = .never
    private(set) var historyLimit: HistoryLimit = .unlimited
    private(set) var isClearHistoryConfirmationPresented = false
    @ObservationIgnored private var historyCleanupTask: Task<Void, Never>?
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
    @ObservationIgnored private let relatedProvider: any RelatedSongProviding
    @ObservationIgnored private(set) var relatedTask: Task<Void, Never>?
    private var relatedID = UUID()
    private var relatedBuffer: [Song] = []
    private var relatedSource: RecommendationSource = .mix
    private var requestedSeeds: [String] = []
    private var recentSelections: [String] = []
    private var autoplayArmed = false
    private var automaticFailures = 0
    private var waitingForAutoplay = false
    private var autoplayWaitPaused = false
    private(set) var isFindingRelatedSongs = false
    private(set) var autoplayNotice: String?
    private(set) var currentRecommendationSource: RecommendationSource?
    private(set) var autoplayEnabled = false

    func setAutoplayEnabled(_ enabled: Bool) {
        guard !isClosing else { return }
        autoplayEnabled = enabled
        defaults.set(enabled, forKey: "autoplayEnabled")
        if !enabled {
            let waiting = waitingForAutoplay
            resetAutoplaySession()
            if waiting { stop() }
        } else if !ended, playbackError == nil {
            autoplayArmed = true
            if historyRecorded { prefetchRelatedSongs() }
        }
        onMediaStateChange?()
    }

    private func resetAutoplaySession() {
        relatedID = UUID(); relatedTask?.cancel(); relatedTask = nil
        relatedBuffer = []; requestedSeeds = []; waitingForAutoplay = false
        isFindingRelatedSongs = false; autoplayArmed = false; autoplayNotice = nil
        automaticFailures = 0
    }

    private var recommendationExclusions: Set<String> {
        Set(recentSelections + history.prefix(50).map { $0.song.id } + queue.map { $0.song.id }
            + [currentSong?.id].compactMap { $0 })
    }

    private func prefetchRelatedSongs() {
        guard autoplayEnabled, autoplayArmed, canEditLibrary, !systemSleeping,
              relatedTask == nil, relatedBuffer.isEmpty, let seed = currentSong,
              !requestedSeeds.contains(seed.id) else { return }
        requestedSeeds.append(seed.id)
        if requestedSeeds.count > 50 { requestedSeeds.removeFirst() }
        let request = UUID(); relatedID = request
        let provider = relatedProvider, exclusions = recommendationExclusions
        isFindingRelatedSongs = true; autoplayNotice = nil
        relatedTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let batch = try await provider.recommendations(for: seed, excluding: exclusions)
                guard let self, self.relatedID == request, !Task.isCancelled,
                      self.autoplayEnabled, self.autoplayArmed, self.canEditLibrary, !self.systemSleeping else { return }
                var seen = self.recommendationExclusions
                self.relatedBuffer = Array(batch.songs.filter {
                    (try? YouTubeVideoID.validate($0.id)) != nil && seen.insert($0.id).inserted
                }.prefix(YouTubeMixProvider.batchLimit))
                self.relatedSource = batch.source
                self.autoplayNotice = self.relatedBuffer.isEmpty ? "No new related songs available." : nil
                self.finishRelatedRequest()
            } catch {
                guard let self, self.relatedID == request, !Task.isCancelled else { return }
                self.autoplayNotice = error as? RecommendationError == .throttled || error as? RecommendationError == .coolingDown
                    ? "Autoplay is cooling down. Try again later."
                    : "Related songs are unavailable. Choose a song to continue."
                self.finishRelatedRequest()
            }
        }
    }

    private func finishRelatedRequest() {
        relatedTask = nil; isFindingRelatedSongs = false
        if waitingForAutoplay {
            waitingForAutoplay = false
            advance(paused: autoplayWaitPaused) // Recheck queue, playlist and mode after the asynchronous request.
        }
        onMediaStateChange?()
    }

    private func advanceAutoplay(paused: Bool) {
        guard autoplayEnabled, autoplayArmed, currentSong != nil, automaticFailures < 3 else { stop(); return }
        let exclusions = recommendationExclusions
        relatedBuffer.removeAll { exclusions.contains($0.id) }
        if !relatedBuffer.isEmpty {
            let song = relatedBuffer.removeFirst()
            rememberCurrent()
            beginPlayback(song, paused: paused, recommendation: relatedSource)
            return
        }
        prefetchRelatedSongs()
        if relatedTask != nil {
            waitingForAutoplay = true; autoplayWaitPaused = paused
            playbackID = UUID() // Discard the completed track's EOF and queued remote commands.
            loaded = false; ended = true; isPlaying = false; isLoading = false; isBuffering = false
            // Manual Next may reach this state while the old song is still audible/resolving.
            // Stop it through the same serialized task chain before any later candidate load.
            let previous = playbackTask, previousControl = controlTask, player = player
            previous?.cancel(); previousControl?.cancel()
            playbackTask = Task {
                await previous?.value
                await previousControl?.value
                guard !Task.isCancelled else { return }
                await player.stop()
            }
            onMediaStateChange?()
        } else {
            let notice = autoplayNotice ?? "No new related songs available."
            stop(); autoplayNotice = notice
        }
    }

    private var desiredPaused = false
    private var systemSleeping = false
    private var mediaPositionRevision = 0
    private(set) var playbackNotice: String?
    @ObservationIgnored var onMediaStateChange: (() -> Void)?
    private var pendingQueueEntry: QueueEntry?
    private var historyRecorded = false
    @ObservationIgnored private let store: (any LibraryPersisting)?
    @ObservationIgnored private(set) var restorationTask: Task<Void, Never>?
    @ObservationIgnored private(set) var persistenceTask: Task<Void, Never>?
    private var favoriteDates: [String: Date] = [:]
    private var storeRevision = 0
    private var editVersion = 0
    private var dataLoaded = true
    private(set) var isRestoring = false
    private(set) var hasUnsavedChanges = false
    private(set) var persistenceError: String?
    private(set) var isClosing = false
    var canEditLibrary: Bool { dataLoaded && !isClosing }
    private var ended = true
    private var loaded = false
    var progress: TimeInterval = 0
    private(set) var volume: Double = 0.7 {
        didSet { defaults.set(volume, forKey: "volume") }
    }
    var searchFocusRequest = 0
    private let defaults: UserDefaults
    private struct NavigationEntry {
        let song: Song
        let sequenceID: UUID
        let position: Int
    }
    private var previousSongs: [NavigationEntry] = []
    private var sequenceID = UUID()
    private(set) var favoritesSequence: [Song] = []
    private var playlistPosition = -1
    private(set) var repeatMode: RepeatMode = .off {
        didSet { defaults.set(repeatMode.rawValue, forKey: "repeatMode") }
    }
    var favoritesPlaybackActive: Bool { !favoritesSequence.isEmpty }

    func cycleRepeatMode() {
        guard !isClosing else { return }
        switch repeatMode {
        case .off: repeatMode = .one
        case .one: repeatMode = .all
        case .all: repeatMode = .off
        }
        onMediaStateChange?()
    }

    private func rememberCurrent() {
        if let currentSong {
            previousSongs.append(NavigationEntry(song: currentSong, sequenceID: sequenceID, position: playlistPosition))
            if previousSongs.count > 100 { previousSongs.removeFirst() }
        }
    }

    private func clearPlaylist() {
        favoritesSequence = []; playlistPosition = -1; sequenceID = UUID()
    }

    func playFavorites(shuffled: Bool = false) {
        guard canEditLibrary, !systemSleeping, !favorites.isEmpty else { return }
        rememberCurrent()
        resetAutoplaySession()
        sequenceID = UUID()
        favoritesSequence = shuffled ? favorites.shuffled() : favorites
        playlistPosition = 0
        beginPlayback(favoritesSequence[0])
    }

    // Snapshot order is stable; additions wait until the next Play All/Shuffle.
    // Removal excludes future occurrences, but never interrupts the current song.
    private var nextPlaylistPosition: Int? {
        let remaining = favoritesSequence.indices.dropFirst(playlistPosition + 1)
        if let next = remaining.first(where: { favoriteIDs.contains(favoritesSequence[$0].id) }) { return next }
        if repeatMode == .all {
            return favoritesSequence.indices.first(where: { favoriteIDs.contains(favoritesSequence[$0].id) })
        }
        return nil
    }
    var sidebarVisible: Bool {
        didSet { defaults.set(sidebarVisible, forKey: "sidebarVisible") }
    }

    init(defaults: UserDefaults = .standard, searchService: any SongSearching = YouTubeSearchService(),
         resolver: any AudioStreamResolving = AudioStreamResolver(), player: (any AudioPlaying)? = nil,
         store: (any LibraryPersisting)? = nil, relatedProvider: any RelatedSongProviding = YouTubeMixProvider()) {
        self.relatedProvider = relatedProvider
        self.store = store
        self.resolver = resolver
        self.player = player ?? MPVPlaybackEngine()
        self.searchService = searchService
        self.defaults = defaults
        autoplayEnabled = (defaults.object(forKey: "autoplayEnabled") as? NSNumber)
            .flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil } ?? false
        repeatMode = defaults.string(forKey: "repeatMode").flatMap(RepeatMode.init(rawValue:)) ?? .off
        historyRetention = defaults.string(forKey: "historyRetention").flatMap(HistoryRetention.init(rawValue:)) ?? .never
        historyLimit = defaults.string(forKey: "historyLimit").flatMap(HistoryLimit.init(rawValue:)) ?? .unlimited
        sidebarVisible = (defaults.object(forKey: "sidebarVisible") as? NSNumber)
            .flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil } ?? true
        if let stored = defaults.object(forKey: "volume") as? NSNumber,
           CFGetTypeID(stored) != CFBooleanGetTypeID(), stored.doubleValue.isFinite {
            volume = min(1, max(0, stored.doubleValue))
        } else { volume = 0.7 }
        self.player.onEvent = { [weak self] id, event in self?.receive(id, event) }
        if store != nil { restoreLibrary() }
    }

    var favorites: [Song] {
        knownSongs.values.filter { favoriteIDs.contains($0.id) }
            .sorted {
                let order = $0.title.localizedStandardCompare($1.title)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
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
        guard canEditLibrary else { return }
        knownSongs[song.id] = song
        if !favoriteIDs.insert(song.id).inserted { favoriteIDs.remove(song.id); favoriteDates.removeValue(forKey: song.id) }
        else { favoriteDates[song.id] = .now }
        scheduleSave()
    }

    func enqueue(_ song: Song) {
        defer { onMediaStateChange?() }
        guard canEditLibrary else { return }
        queue.append(QueueEntry(song: song)); scheduleSave()
        if waitingForAutoplay { next() }
    }

    func play(_ song: Song) {
        guard canEditLibrary, !systemSleeping else { return }
        rememberCurrent()
        resetAutoplaySession()
        clearPlaylist()
        beginPlayback(song)
    }

    func playNext(_ song: Song) {
        defer { onMediaStateChange?() }
        guard canEditLibrary else { return }
        queue.insert(QueueEntry(song: song), at: 0); scheduleSave()
        if waitingForAutoplay { next() }
    }

    private func beginPlayback(_ song: Song, queueEntry: QueueEntry? = nil, retry: Bool = false, paused: Bool = false, recommendation: RecommendationSource? = nil) {
        defer { onMediaStateChange?() }
        waitingForAutoplay = false; autoplayArmed = true
        currentRecommendationSource = recommendation
        if recommendation == nil { automaticFailures = 0 }
        if !retry {
            recentSelections.removeAll { $0 == song.id }
            recentSelections.append(song.id)
            if recentSelections.count > 50 { recentSelections.removeFirst() }
        }
        desiredPaused = paused; playbackNotice = nil
        returnPendingEntry()
        if let queueEntry { queue.removeAll { $0.id == queueEntry.id } }
        pendingQueueEntry = queueEntry
        if !retry { historyRecorded = false }
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
        scheduleSave()
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
                try await player.load(url, request: request, volume: self.volume, paused: paused)
                try Task.checkCancellation()
            } catch {
                guard let self, self.playbackID == request, !Task.isCancelled else { return }
                self.fail((error as? PlaybackError)?.localizedDescription ?? PlaybackError.playback.localizedDescription)
            }
        }
    }

    func receive(_ request: UUID, _ event: PlaybackEvent) {
        guard request == playbackID, !ended, playbackError == nil else { return }
        defer { onMediaStateChange?() }
        switch event {
        case .loaded:
            guard !loaded else { return }
            loaded = true; isLoading = false; isPlaying = !desiredPaused
        case .position(let value):
            guard value.isFinite, value >= 0 else { return }
            progress = value
            if loaded, isPlaying, value > 0, !historyRecorded { recordStartedPlayback() }
        case .duration(let value):
            guard value.isFinite, value > 0, value <= 31_536_000 else { return }
            duration = value
            if let song = currentSong, !song.durationKnown || abs(song.duration - value) > 0.1 {
                currentSong = Song(id: song.id, title: song.title, artist: song.artist, duration: value)
                knownSongs[song.id] = currentSong
                scheduleSave()
            }
        case .paused(let value): if loaded { isPlaying = !value }
        case .buffering(let value): isBuffering = value
        case .volume(let value): if value.isFinite { volume = min(1, max(0, value)) }
        case .clockAnchor: mediaPositionRevision += 1
        case .ended:
            guard historyRecorded else { fail("Playback ended before audio started. Retry or choose another song."); return }
            ended = true; isPlaying = false; isLoading = false; isBuffering = false
            automaticFailures = 0
            if repeatMode == .one, let currentSong {
                beginPlayback(currentSong, recommendation: currentRecommendationSource)
            } else { next() }
        case .failure(let message): fail(message)
        }
    }

    private func fail(_ message: String) {
        defer { onMediaStateChange?() }
        desiredPaused = true
        playbackError = message
        isPlaying = false; isLoading = false; isBuffering = false
        let player = player
        controlTask = Task { await player.stop() }
        if currentRecommendationSource != nil, autoplayEnabled, autoplayArmed {
            automaticFailures += 1
            if automaticFailures < 3 { advance(paused: false) }
            else {
                resetAutoplaySession()
                autoplayNotice = "Autoplay stopped after three playback failures. Choose a song or Retry."
            }
        }
    }

    func retryPlayback() {
        guard canEditLibrary, !systemSleeping, let currentSong else { return }
        beginPlayback(currentSong, queueEntry: pendingQueueEntry, retry: !ended, recommendation: currentRecommendationSource)
    }

    func playQueueEntry(_ id: UUID, paused: Bool = false) {
        guard canEditLibrary, !systemSleeping, let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let entry = queue.remove(at: index)
        rememberCurrent()
        beginPlayback(entry.song, queueEntry: entry, paused: paused)
    }

    func playPlayback() {
        guard canEditLibrary, !systemSleeping, !isLoading else { return }
        if currentSong == nil { if !queue.isEmpty { next() }; return }
        if playbackError != nil || ended { retryPlayback(); return }
        guard loaded, desiredPaused else { return }
        desiredPaused = false
        performControl { try await $0.pause(false) }
        onMediaStateChange?()
    }

    func pausePlayback() {
        guard canEditLibrary, !systemSleeping else { return }
        if waitingForAutoplay { stop(); return }
        if isLoading { stop(); return } // A pause during resolution must prevent a late autoplay.
        guard loaded, !ended, playbackError == nil, !desiredPaused else { return }
        desiredPaused = true
        performControl { try await $0.pause(true) }
        onMediaStateChange?()
    }

    func togglePlayback() {
        guard canEditLibrary, !systemSleeping else { return }
        if isLoading || waitingForAutoplay { pausePlayback() }
        else if ended || playbackError != nil || currentSong == nil || desiredPaused { playPlayback() }
        else { pausePlayback() }
    }

    func seek(to value: Double) {
        guard playbackCapabilities.contains(.seek), value.isFinite else { return }
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
        resetAutoplaySession()
        defer { onMediaStateChange?() }
        desiredPaused = true; loaded = false
        let needsRecovery = pendingQueueEntry.map { entry in !queue.contains(where: { $0.id == entry.id }) } ?? false
        returnPendingEntry()
        if needsRecovery { scheduleSave() }
        playbackID = UUID(); playbackTask?.cancel(); controlTask?.cancel()
        isPlaying = false; isLoading = false; isBuffering = false; ended = true
        let previous = playbackTask, player = player
        playbackTask = Task { await previous?.value; await player.stop() }
    }

    func shutdown() {
        resetAutoplaySession()
        historyCleanupTask?.cancel()
        defer { onMediaStateChange?() }
        desiredPaused = true; loaded = false; ended = true
        isPlaying = false; isLoading = false; isBuffering = false
        let needsRecovery = pendingQueueEntry.map { entry in !queue.contains(where: { $0.id == entry.id }) } ?? false
        returnPendingEntry()
        if needsRecovery { scheduleSave() }
        cancelSearch(); playbackID = UUID(); playbackTask?.cancel(); controlTask?.cancel()
        player.shutdown()
    }

    func next() {
        guard canEditLibrary, !systemSleeping else { return }
        let keepPaused = waitingForAutoplay ? autoplayWaitPaused : loaded && !ended && playbackError == nil && desiredPaused
        waitingForAutoplay = false
        advance(paused: keepPaused)
    }

    private func advance(paused keepPaused: Bool) {
        guard canEditLibrary, !systemSleeping else { return }
        if let entry = queue.first {
            playQueueEntry(entry.id, paused: keepPaused)
        } else if let position = nextPlaylistPosition {
            rememberCurrent()
            playlistPosition = position
            beginPlayback(favoritesSequence[position], paused: keepPaused)
        } else { advanceAutoplay(paused: keepPaused) }
    }

    func previous() {
        guard playbackCapabilities.contains(.previous) else { return }
        let keepPaused = loaded && !ended && playbackError == nil && desiredPaused
        if progress > 3, !waitingForAutoplay { seek(to: 0) }
        else if let entry = previousSongs.popLast() {
            resetAutoplaySession()
            if entry.sequenceID == sequenceID { playlistPosition = entry.position }
            else { clearPlaylist() }
            beginPlayback(entry.song, paused: keepPaused)
        }
        else { seek(to: 0) }
    }

    func removeQueueEntry(_ id: UUID) {
        defer { onMediaStateChange?() }
        guard canEditLibrary else { return }
        if pendingQueueEntry?.id == id { pendingQueueEntry = nil }
        queue.removeAll { $0.id == id }; scheduleSave()
    }
    func clearQueue() {
        defer { onMediaStateChange?() }
        guard canEditLibrary else { return }
        if let pending = pendingQueueEntry, queue.contains(where: { $0.id == pending.id }) { pendingQueueEntry = nil }
        queue.removeAll(); scheduleSave()
    }
    func moveQueueEntries(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        defer { onMediaStateChange?() }
        guard canEditLibrary else { return }
        queue.move(fromOffsets: offsets, toOffset: destination); scheduleSave()
    }

    func moveQueueEntry(_ id: UUID, before target: UUID) {
        defer { onMediaStateChange?() }
        guard canEditLibrary, id != target,
              let source = queue.firstIndex(where: { $0.id == id }) else { return }
        let entry = queue.remove(at: source)
        guard let destination = queue.firstIndex(where: { $0.id == target }) else {
            queue.insert(entry, at: min(source, queue.count)); return
        }
        queue.insert(entry, at: destination)
        scheduleSave()
    }

    private func returnPendingEntry() {
        if let entry = pendingQueueEntry, !queue.contains(where: { $0.id == entry.id }) { queue.insert(entry, at: 0) }
        // Retain the reference while stopped so Play consumes this exact restored queue entry.
    }

    func deleteHistoryEntry(_ id: UUID) {
        guard canEditLibrary, history.contains(where: { $0.id == id }) else { return }
        history.removeAll { $0.id == id }
        if history.isEmpty { cancelClearHistory() }
        scheduleSave()
        scheduleHistoryCleanup()
    }

    func requestClearHistory() {
        guard canEditLibrary, !history.isEmpty else { return }
        isClearHistoryConfirmationPresented = true
    }

    func cancelClearHistory() { isClearHistoryConfirmationPresented = false }

    func confirmClearHistory() {
        guard isClearHistoryConfirmationPresented, canEditLibrary else { return }
        cancelClearHistory()
        history.removeAll()
        scheduleSave()
        scheduleHistoryCleanup()
    }

    func setHistoryRetention(_ value: HistoryRetention) {
        guard canEditLibrary else { return }
        historyRetention = value
        defaults.set(value.rawValue, forKey: "historyRetention")
        cleanupHistory()
    }

    func setHistoryLimit(_ value: HistoryLimit) {
        guard canEditLibrary else { return }
        historyLimit = value
        defaults.set(value.rawValue, forKey: "historyLimit")
        cleanupHistory()
    }

    // Entries are already newest-first; filtering preserves stable row identities and order.
    func cleanupHistory(now: Date = .now) {
        guard canEditLibrary else { return }
        let oldCount = history.count
        if let days = historyRetention.days {
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            history.removeAll { $0.playedAt <= cutoff }
        }
        if let limit = historyLimit.count, history.count > limit {
            history.removeLast(history.count - limit)
        }
        if history.isEmpty { cancelClearHistory() }
        if history.count != oldCount { scheduleSave() }
        scheduleHistoryCleanup()
    }

    private func scheduleHistoryCleanup() {
        historyCleanupTask?.cancel()
        historyCleanupTask = nil
        guard canEditLibrary, let days = historyRetention.days, let oldest = history.last else { return }
        let expiry = oldest.playedAt.addingTimeInterval(Double(days) * 86_400)
        // Recheck at least daily, also bounding sleeps after wall-clock changes.
        let delay = min(86_400, max(0.05, expiry.timeIntervalSinceNow))
        historyCleanupTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.cleanupHistory()
        }
    }

    private func recordStartedPlayback() {
        guard let song = currentSong else { return }
        historyRecorded = true
        pendingQueueEntry = nil
        cleanupHistory()
        let old = history.first(where: { $0.song.id == song.id })
        history.removeAll { $0.song.id == song.id }
        history.insert(HistoryEntry(id: old?.id ?? UUID(), song: song, playedAt: .now,
                                   playCount: min(old?.playCount ?? 0, Int.max - 1) + 1), at: 0)
        cleanupHistory()
        scheduleSave()
        prefetchRelatedSongs()
    }

    private func snapshot() -> LibrarySnapshot {
        LibrarySnapshot(favorites: favoriteIDs.sorted().compactMap { id in
            knownSongs[id].map { FavoriteRecord(song: $0, addedAt: favoriteDates[id] ?? .now) }
        }, history: history, queue: queue, currentSong: currentSong, pendingQueueEntry: pendingQueueEntry, revision: storeRevision)
    }

    private func restoreLibrary() {
        guard let store, !isRestoring, !isClosing else { return }
        dataLoaded = false; isRestoring = true; persistenceError = nil
        onMediaStateChange?()
        restorationTask = Task { [weak self] in
            defer { self?.onMediaStateChange?() }
            do {
                let data = try await store.load()
                guard let self else { return }
                self.favoriteIDs = Set(data.favorites.map { $0.song.id })
                self.favoriteDates = Dictionary(uniqueKeysWithValues: data.favorites.map { ($0.song.id, $0.addedAt) })
                self.history = data.history
                self.queue = data.queue
                self.currentSong = data.currentSong
                self.pendingQueueEntry = data.pendingQueueEntry
                self.storeRevision = data.revision
                let songs = data.favorites.map(\.song) + data.history.map(\.song) + data.queue.map(\.song)
                for song in songs { self.knownSongs[song.id] = song }
                if let song = data.currentSong { self.knownSongs[song.id] = song }
                // Restoration only populates metadata. No engine or resolver call is made.
                self.isRestoring = false; self.dataLoaded = true
                self.cleanupHistory()
                if let pending = data.pendingQueueEntry {
                    let needsRecovery = !self.queue.contains(where: { $0.id == pending.id })
                    self.returnPendingEntry()
                    if needsRecovery { self.scheduleSave() }
                }
            } catch {
                guard let self else { return }
                self.isRestoring = false
                self.persistenceError = (error as? PersistenceError)?.localizedDescription ?? PersistenceError.unavailable.localizedDescription
            }
        }
    }

    private func scheduleSave() {
        guard store != nil, dataLoaded else { return }
        editVersion += 1; hasUnsavedChanges = true
        if persistenceTask == nil { startWriter() }
    }

    private func startWriter() {
        guard let store else { return }
        persistenceTask = Task { [weak self] in
            while let self, self.hasUnsavedChanges {
                let version = self.editVersion, data = self.snapshot()
                do {
                    let revision = try await store.save(data, expecting: self.storeRevision)
                    self.storeRevision = revision
                    if self.editVersion == version { self.hasUnsavedChanges = false }
                    self.persistenceError = nil
                } catch {
                    self.persistenceError = (error as? PersistenceError)?.localizedDescription ?? PersistenceError.writeFailed.localizedDescription
                    self.persistenceTask = nil
                    return
                }
            }
            self?.persistenceTask = nil
        }
    }

    func retryPersistence() {
        guard !isClosing else { return }
        if !dataLoaded { restoreLibrary() }
        else if hasUnsavedChanges, persistenceTask == nil { startWriter() }
    }

    func flushPersistence() async -> Bool {
        await restorationTask?.value
        guard dataLoaded else { return true } // No editable state exists to flush after a failed load.
        if hasUnsavedChanges, persistenceTask == nil { startWriter() }
        await persistenceTask?.value
        return !hasUnsavedChanges
    }

    func prepareToQuit() async -> Bool {
        defer { onMediaStateChange?() }
        guard !isClosing else { return false }
        isClosing = true
        cancelClearHistory(); historyCleanupTask?.cancel()
        cancelSearch(); stop()
        guard await flushPersistence() else { isClosing = false; scheduleHistoryCleanup(); return false }
        player.shutdown()
        await store?.close()
        pendingQueueEntry = nil // Teardown only; the durable recovery reference is retained.
        return true
    }

    var playPauseShowsPause: Bool { waitingForAutoplay || isLoading || (loaded && !ended && playbackError == nil && !desiredPaused) }

    var playbackCapabilities: Set<MediaCommandKind> {
        guard canEditLibrary, !systemSleeping else { return [] }
        if waitingForAutoplay {
            var commands: Set<MediaCommandKind> = [.pause, .toggle, .stop, .next]
            if !previousSongs.isEmpty { commands.insert(.previous) }
            return commands
        }
        var commands: Set<MediaCommandKind> = []
        if !isLoading, (currentSong != nil || !queue.isEmpty), (ended || playbackError != nil || !loaded || desiredPaused) { commands.insert(.play) }
        if isLoading || (loaded && !ended && playbackError == nil && !desiredPaused) { commands.insert(.pause) }
        if commands.contains(.play) || commands.contains(.pause) { commands.insert(.toggle) }
        if !queue.isEmpty || nextPlaylistPosition != nil || (autoplayEnabled && autoplayArmed && currentSong != nil) { commands.insert(.next) }
        if !previousSongs.isEmpty || (loaded && !ended && duration > 0 && playbackError == nil) { commands.insert(.previous) }
        if loaded && !ended && playbackError == nil && duration.isFinite && duration > 0 { commands.insert(.seek) }
        if !ended { commands.insert(.stop) }
        return commands
    }

    var mediaPlaybackSnapshot: MediaPlaybackSnapshot {
        let phase: MediaPlaybackPhase
        if systemSleeping || isClosing { phase = .stopped }
        else if waitingForAutoplay { phase = .loading }
        else if ended { phase = .stopped }
        else if playbackError != nil { phase = .failed }
        else if isLoading { phase = .loading }
        else if isBuffering && isPlaying { phase = .buffering }
        else { phase = isPlaying ? .playing : .paused }
        return MediaPlaybackSnapshot(generation: playbackID, phase: phase, title: currentSong?.title,
                                     artist: currentSong?.artist, duration: duration > 0 ? duration : nil,
                                     elapsed: progress, positionRevision: mediaPositionRevision, commands: playbackCapabilities)
    }

    func handleMediaCommand(_ command: MediaCommand, generation: UUID) {
        guard generation == playbackID, playbackCapabilities.contains(command.kind) else { return }
        switch command {
        case .play: playPlayback()
        case .pause: pausePlayback()
        case .toggle: togglePlayback()
        case .next: next()
        case .previous: previous()
        case .stop: stop()
        case .seek(let position): if position.isFinite, position >= 0 { seek(to: position) }
        }
    }

    func handleInterruption(_ reason: PlaybackInterruption) {
        defer { onMediaStateChange?() }
        if case .wake = reason { systemSleeping = false; return } // Never resume on wake.
        let active = waitingForAutoplay || (!ended && (isLoading || loaded))
        if case .sleep = reason {
            systemSleeping = true
            // Invalidate even a stopped generation: a command queued before sleep must
            // not become actionable again merely because wake re-enables Play.
            stop(); player.interrupt()
            if active { playbackNotice = "Playback stopped for Mac sleep. Press Play to continue." }
            return
        }
        guard active else { return }
        stop()
        player.interrupt()
        playbackNotice = "Audio output changed. Press Play to continue."
    }

}
