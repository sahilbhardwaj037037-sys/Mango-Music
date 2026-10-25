import Foundation
import Testing
@testable import MangoMusic

@MainActor
struct MusicLibraryTests {
    @MainActor func makeLibrary(searchService: any SongSearching = FixtureSearch()) -> MusicLibrary {
        let defaults = UserDefaults(suiteName: "MangoMusicTests.\(UUID().uuidString)")!
        return MusicLibrary(defaults: defaults, searchService: searchService, resolver: FixtureResolver(), player: FixturePlayer())
    }

    @Test func testSearchMatchesArtistAndHandlesNoResults() async {
        let library = makeLibrary()
        library.query = "  mira sol "
        library.search()
        await library.searchTask?.value
        #expect(library.results.count == 2)
        library.query = "not a song"
        library.search()
        await library.searchTask?.value
        #expect(library.results.isEmpty)
        library.clearSearch()
        #expect(library.results.isEmpty)
        #expect(library.searchState == .idle)
    }

    @Test func testDuplicateQueueEntriesHaveIndependentIdentity() async {
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
        await library.playbackTask?.value
        #expect(library.isPlaying)
    }

    @Test func testQueueReorderingPreservesEntries() {
        let library = makeLibrary()
        Song.samples.prefix(3).forEach { library.enqueue($0) }
        let entries = library.queue
        library.moveQueueEntry(entries[2].id, before: entries[0].id)
        #expect(library.queue.map(\.id) == [entries[2].id, entries[0].id, entries[1].id])
    }

    @Test func testFavorites() {
        let library = makeLibrary()
        library.toggleFavorite(Song.samples[0])
        #expect(library.favorites == [Song.samples[0]])
        library.toggleFavorite(Song.samples[0])
        #expect(library.favorites.isEmpty)
    }

    @Test func testSidebarVisibilityPersists() {
        let suite = "MangoMusicTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = MusicLibrary(defaults: defaults)
        #expect(library.sidebarVisible)
        library.toggleSidebar()
        #expect(!(MusicLibrary(defaults: defaults).sidebarVisible))
    }
}

private struct FixtureSearch: SongSearching {
    func search(query: String) async throws -> [Song] {
        Song.samples.filter { $0.artist.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query) }
    }
}
