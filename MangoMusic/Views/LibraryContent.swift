import SwiftUI
import UniformTypeIdentifiers

struct LibraryContent: View {
    @Bindable var library: MusicLibrary
    @State private var selection: String?
    @State private var queueSelection: UUID?
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(library.destination.rawValue).font(.largeTitle.bold())
                Spacer()
                if library.destination == .queue && !library.queue.isEmpty {
                    Button("Clear Queue", role: .destructive) { library.queue.removeAll() }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 24).padding(.top, 22)

            if library.destination == .search {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search songs or artists", text: $library.query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit { library.search(); searchFocused = false; listFocused = true }
                        .accessibilityLabel("Search songs or artists")
                    if !library.query.isEmpty {
                        Button { library.clearSearch() } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 24)
            }

            switch library.destination {
            case .search:
                searchContent
            case .favorites:
                songList(library.favorites, emptyTitle: "Keep your favorites close", symbol: "heart",
                         detail: "Tap a heart beside a song to save it here.")
            case .history:
                historyList
            case .queue:
                queueList
            }
        }
        .onChange(of: library.searchFocusRequest) { _, _ in searchFocused = true }
        .onChange(of: library.searchState) { _, state in
            if state == .loaded && library.destination == .search && !searchFocused { listFocused = true }
        }
        .onChange(of: library.destination) { _, _ in selection = nil; queueSelection = nil }
    }

    @ViewBuilder private var searchContent: some View {
        switch library.searchState {
        case .idle:
            emptyState("Search YouTube", symbol: "magnifyingglass",
                       detail: "Enter a song or artist and press Return.")
        case .loading:
            VStack(spacing: 16) {
                ProgressView("Searching YouTube…")
                Button("Cancel", action: library.cancelSearch)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let message):
            VStack {
                ContentUnavailableView("Search unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
                if !library.submittedQuery.isEmpty { Button("Retry", action: library.retrySearch) }
            }.padding(.bottom, 24).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .cancelled:
            VStack {
                ContentUnavailableView("Search cancelled", systemImage: "xmark.circle",
                                       description: Text("No new search runs until you press Return or Retry."))
                Button("Retry", action: library.retrySearch)
            }.padding(.bottom, 24).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            emptyState("No songs found", symbol: "magnifyingglass",
                       detail: "No results for \(library.submittedQuery). Try another search.")
        case .loaded:
            VStack(alignment: .leading, spacing: 4) {
                Text("YouTube results for “\(library.submittedQuery)”")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 24)
                songList(library.results, emptyTitle: "No songs found", symbol: "magnifyingglass", detail: "Try another search.")
            }
        }
    }

    @ViewBuilder
    private func songList(_ songs: [Song], emptyTitle: String, symbol: String, detail: String) -> some View {
        if songs.isEmpty {
            emptyState(emptyTitle, symbol: symbol, detail: detail)
        } else {
            List(selection: $selection) {
                ForEach(songs) { song in
                    SongRow(song: song, library: library)
                        .tag(song.id)
                        .simultaneousGesture(TapGesture(count: 2).onEnded { library.play(song) })
                }
            }
            .listStyle(.inset)
            .focused($listFocused)
            .onKeyPress(.return) {
                guard let song = songs.first(where: { $0.id == selection }) else { return .ignored }
                library.play(song); return .handled
            }
            .overlay(alignment: .bottomLeading) {
                Text("\(songs.count) songs · Double-click to play")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading).background(.bar)
                    .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 30) }
        }
    }

    @ViewBuilder private var historyList: some View {
        if library.history.isEmpty {
            emptyState("Your listening story starts here", symbol: "clock", detail: "Songs you play will appear here.")
        } else {
            List(selection: $selection) {
                ForEach(library.history) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        SongRow(song: entry.song, library: library)
                        Text(entry.playedAt, format: .dateTime.hour().minute())
                            .font(.caption2).foregroundStyle(.secondary).padding(.leading, 28)
                    }
                    .tag(entry.id.uuidString)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { library.play(entry.song) })
                }
            }
            .listStyle(.inset).focused($listFocused)
            .onKeyPress(.return) {
                guard let entry = library.history.first(where: { $0.id.uuidString == selection }) else { return .ignored }
                library.play(entry.song); return .handled
            }
        }
    }

    private var queueList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let song = library.currentSong {
                Text("NOW PLAYING").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 24).padding(.bottom, 6)
                SongRow(song: song, library: library).padding(.horizontal, 24)
                Divider().padding(.vertical, 12).padding(.horizontal, 24)
            }
            if library.queue.isEmpty {
                emptyState("Make room for your next favorite", symbol: "text.badge.plus",
                           detail: "Add songs with the + button in Search or Favorites.")
            } else {
                Text("UPCOMING · \(library.queue.count)").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 4)
                List(selection: $queueSelection) {
                    ForEach(library.queue) { entry in
                        SongRow(song: entry.song, library: library, remove: {
                            library.removeQueueEntry(entry.id)
                        })
                        .tag(entry.id)
                        .simultaneousGesture(TapGesture(count: 2).onEnded { library.playQueueEntry(entry.id) })
                        .onDrag { NSItemProvider(object: entry.id.uuidString as NSString) }
                        .dropDestination(for: String.self) { items, _ in
                            guard let value = items.first, let id = UUID(uuidString: value),
                                  library.queue.contains(where: { $0.id == id }) else { return false }
                            library.moveQueueEntry(id, before: entry.id)
                            return true
                        }
                        .contextMenu {
                            Button("Play Now") { library.playQueueEntry(entry.id) }
                            Button("Move to Top") {
                                if let first = library.queue.first { library.moveQueueEntry(entry.id, before: first.id) }
                            }
                            Button("Remove from Queue", role: .destructive) { library.removeQueueEntry(entry.id) }
                        }
                    }
                    .onMove { library.queue.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset).focused($listFocused)
                .onKeyPress(.return) {
                    guard let id = queueSelection else { return .ignored }
                    library.playQueueEntry(id); return .handled
                }
                .onDeleteCommand {
                    if let id = queueSelection { library.removeQueueEntry(id); queueSelection = nil }
                }
            }
        }
    }

    private func emptyState(_ title: String, symbol: String, detail: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(detail))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
