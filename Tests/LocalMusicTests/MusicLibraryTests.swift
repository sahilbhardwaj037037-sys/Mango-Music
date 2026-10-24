import Foundation
import Testing
@testable import LocalMusic

@MainActor
struct MusicLibraryTests {
    @MainActor func makeLibrary() -> MusicLibrary {
        let defaults = UserDefaults(suiteName: "LocalMusicTests.\(UUID().uuidString)")!
        return MusicLibrary(defaults: defaults)
    }

    @Test func testSearchMatchesArtistAndHandlesNoResults() {
        let library = makeLibrary()
        library.query = "  mira sol "
        library.search()
        #expect(library.results.count == 2)
        library.query = "not a song"
        library.search()
        #expect(library.results.isEmpty)
        library.query = ""
        library.search()
        #expect(library.results.count == 10)
    }

    @Test func testDuplicateQueueEntriesHaveIndependentIdentity() {
        let library = makeLibrary()
        let song = Song.samples[0]
        library.enqueue(song)
        library.enqueue(song)
        #expect(library.queue[0].id != library.queue[1].id)
        library.removeQueueEntry(library.queue[0].id)
        #expect(library.queue.count == 1)
        library.playQueueEntry(library.queue[0].id)
        #expect(library.queue.isEmpty)
        #expect(library.currentSong == song)
        #expect(library.isPlaying)
    }

    @Test func testQueueReorderingPreservesEntries() {
        let library = makeLibrary()
        Song.samples.prefix(3).forEach { library.enqueue($0) }
        let entries = library.queue
        library.moveQueueEntry(entries[2].id, before: entries[0].id)
        #expect(library.queue.map(\.id) == [entries[2].id, entries[0].id, entries[1].id])
    }

    @Test func testPlaybackAdvancesQueueAndStopsAtEnd() {
        let library = makeLibrary()
        library.enqueue(Song.samples[1])
        library.play(Song.samples[0])
        library.progress = Song.samples[0].duration - 1
        library.tick()
        #expect(library.currentSong == Song.samples[1])
        #expect(library.progress == 0)
        #expect(library.history.count == 2)
        library.progress = Song.samples[1].duration - 1
        library.tick()
        #expect(!(library.isPlaying))
        #expect(library.progress == Song.samples[1].duration)
    }

    @Test func testPauseFavoritesAndPrevious() {
        let library = makeLibrary()
        library.toggleFavorite(Song.samples[0])
        #expect(library.favorites == [Song.samples[0]])
        library.toggleFavorite(Song.samples[0])
        #expect(library.favorites.isEmpty)
        library.play(Song.samples[0])
        library.play(Song.samples[1])
        library.previous()
        #expect(library.currentSong == Song.samples[0])
        library.togglePlayback()
        library.tick()
        #expect(library.progress == 0)
    }

    @Test func testSidebarVisibilityPersists() {
        let suite = "LocalMusicTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = MusicLibrary(defaults: defaults)
        #expect(library.sidebarVisible)
        library.toggleSidebar()
        #expect(!(MusicLibrary(defaults: defaults).sidebarVisible))
    }
}
