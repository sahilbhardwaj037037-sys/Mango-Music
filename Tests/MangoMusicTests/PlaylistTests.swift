import Foundation
import Testing
@testable import MangoMusic

@MainActor
struct PlaylistTests {
    func make(_ player: FixturePlayer, resolver: any AudioStreamResolving = FixtureResolver()) -> MusicLibrary {
        MusicLibrary(defaults: UserDefaults(suiteName: "PlaylistTests.\(UUID())")!, resolver: resolver, player: player)
    }
    func addFavorites(_ library: MusicLibrary, count: Int = 3) {
        (0..<count).forEach { library.toggleFavorite(testSong($0)) }
    }
    func end(_ player: FixturePlayer, _ library: MusicLibrary) async {
        player.emit(.ended)
        await library.playbackTask?.value
    }

    @Test func playAllOffAndDuplicateEOF() async {
        let player = FixturePlayer(), library = make(player)
        addFavorites(library)
        library.playFavorites(); await library.playbackTask?.value
        #expect(library.currentSong == testSong(0))
        #expect(library.playbackCapabilities.contains(.next))
        let old = player.request
        player.emit(.ended)
        library.receive(old, .ended)
        library.receive(old, .failure("stale"))
        await library.playbackTask?.value
        #expect(library.currentSong == testSong(1)); #expect(player.loads == 2)
        await end(player, library)
        #expect(library.currentSong == testSong(2))
        #expect(!library.playbackCapabilities.contains(.next))
        await end(player, library)
        #expect(!library.isPlaying); #expect(player.loads == 3)
        #expect(library.mediaPlaybackSnapshot.phase == .stopped)
    }

    @Test func repeatOneNaturalEndAndManualNextPrevious() async {
        let player = FixturePlayer(), library = make(player)
        addFavorites(library)
        library.cycleRepeatMode()
        library.playFavorites(); await library.playbackTask?.value
        await end(player, library)
        #expect(library.currentSong == testSong(0)); #expect(player.loads == 2)
        #expect(library.history.first?.playCount == 2)
        library.next(); await library.playbackTask?.value
        #expect(library.currentSong == testSong(1))
        library.previous(); await library.playbackTask?.value
        #expect(library.currentSong == testSong(0))
        library.next(); await library.playbackTask?.value
        #expect(library.currentSong == testSong(1))
    }

    @Test func repeatAllNeverReplaysConsumedQueue() async {
        let player = FixturePlayer(), library = make(player)
        addFavorites(library, count: 2)
        library.cycleRepeatMode(); library.cycleRepeatMode()
        library.playFavorites(); await library.playbackTask?.value
        library.enqueue(testSong(8)); library.playNext(testSong(9))
        await end(player, library); #expect(library.currentSong == testSong(9))
        await end(player, library); #expect(library.currentSong == testSong(8))
        await end(player, library); #expect(library.currentSong == testSong(1))
        await end(player, library); #expect(library.currentSong == testSong(0))
        #expect(library.queue.isEmpty)
        #expect(library.history.first(where: { $0.song == testSong(8) })?.playCount == 1)
        library.play(testSong(7)); await library.playbackTask?.value
        #expect(!library.favoritesPlaybackActive)
        await end(player, library); #expect(!library.isPlaying)
    }

    @Test func repeatOnePrecedesManualQueue() async {
        let player = FixturePlayer(), library = make(player)
        library.cycleRepeatMode(); library.play(testSong(0))
        await library.playbackTask?.value
        library.enqueue(testSong(1))
        await end(player, library)
        #expect(library.currentSong == testSong(0)); #expect(library.queue.count == 1)
        library.handleMediaCommand(.next, generation: library.mediaPlaybackSnapshot.generation)
        await library.playbackTask?.value
        #expect(library.currentSong == testSong(1)); #expect(library.queue.isEmpty)
    }

    @Test func emptySingleAndRemovedFavorites() async {
        let player = FixturePlayer(), library = make(player)
        library.playFavorites(); library.playFavorites(shuffled: true)
        #expect(player.loads == 0); #expect(!library.isLoading)
        addFavorites(library, count: 1)
        library.playFavorites(); await library.playbackTask?.value
        await end(player, library); #expect(!library.isPlaying)
        library.cycleRepeatMode(); library.cycleRepeatMode()
        library.playFavorites(); await library.playbackTask?.value
        await end(player, library); #expect(library.isPlaying)
        library.toggleFavorite(testSong(0))
        await end(player, library); #expect(!library.isPlaying)
        addFavorites(library)
        library.playFavorites(); await library.playbackTask?.value
        library.toggleFavorite(testSong(1)); library.toggleFavorite(testSong(8))
        await end(player, library); #expect(library.currentSong == testSong(2))
        await end(player, library); #expect(library.currentSong == testSong(0))
        #expect(!library.favoritesSequence.contains(testSong(8)))
    }

    @Test func shuffleUsesExactlyOneSnapshotAndRepeatsSameOrder() async {
        let player = FixturePlayer(), library = make(player)
        addFavorites(library, count: 8)
        library.cycleRepeatMode(); library.cycleRepeatMode()
        library.playFavorites(shuffled: true)
        let order = library.favoritesSequence
        #expect(order.count == 8); #expect(Set(order) == Set(library.favorites))
        await library.playbackTask?.value
        for song in order {
            #expect(library.currentSong == song)
            await end(player, library)
        }
        #expect(library.currentSong == order[0]); #expect(library.favoritesSequence == order)
    }

    @Test func errorsNeverAutomaticallyRetryOrSkip() async {
        let player = FixturePlayer(), library = make(player, resolver: UnavailableFavorite())
        addFavorites(library)
        library.cycleRepeatMode()
        library.playFavorites(); await library.playbackTask?.value
        player.emit(.failure("Unavailable")); player.emit(.ended)
        #expect(library.playbackError != nil); #expect(player.loads == 1)
        library.next(); await library.playbackTask?.value
        #expect(library.currentSong == testSong(1)); #expect(library.playbackError != nil)
        #expect(player.loads == 1)
        library.receive(library.mediaPlaybackSnapshot.generation, .ended)
        #expect(library.currentSong == testSong(1))
        library.next(); await library.playbackTask?.value
        #expect(library.currentSong == testSong(2)); #expect(library.isPlaying)
        library.stop(); await library.playbackTask?.value
        #expect(player.loads == 2)
    }

    @Test func repeatPreferenceIsValidatedAndRestored() {
        let suite = "PlaylistPreferences.\(UUID())", defaults: UserDefaults
        defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for invalid in ["invalid", "", "ONE"] {
            defaults.set(invalid, forKey: "repeatMode")
            #expect(MusicLibrary(defaults: defaults, player: FixturePlayer()).repeatMode == .off)
        }
        let library = MusicLibrary(defaults: defaults, player: FixturePlayer())
        for mode in [RepeatMode.one, .all, .off] {
            library.cycleRepeatMode()
            let restored = MusicLibrary(defaults: defaults, player: FixturePlayer())
            #expect(restored.repeatMode == mode)
            #expect(!restored.favoritesPlaybackActive); #expect(!restored.isPlaying)
        }
    }

    @Test func manualNextRejectsOldEOFAndRemoteCommandDuringResolution() async {
        let player = FixturePlayer(), library = make(player, resolver: SlowFavorite())
        addFavorites(library)
        library.playFavorites()
        let old = library.mediaPlaybackSnapshot.generation
        library.next()
        library.receive(old, .ended)
        library.handleMediaCommand(.next, generation: old)
        await library.playbackTask?.value
        #expect(library.currentSong == testSong(1)); #expect(player.loads == 1)
        library.next(); library.stop()
        await library.playbackTask?.value
        #expect(!library.isPlaying); #expect(player.loads == 1)
    }
}

private struct UnavailableFavorite: AudioStreamResolving {
    func resolve(_ song: Song) async throws -> URL {
        if song == testSong(1) { throw PlaybackError.resolution }
        return URL(string: "https://example.com/audio")!
    }
}

private struct SlowFavorite: AudioStreamResolving {
    func resolve(_ song: Song) async throws -> URL {
        try? await Task.sleep(for: .milliseconds(20)) // Deliberately ignore cancellation.
        return URL(string: "https://example.com/audio")!
    }
}
