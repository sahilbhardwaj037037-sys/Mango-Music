import SwiftUI

struct SongRow: View {
    let song: Song
    @Bindable var library: MusicLibrary
    var remove: (() -> Void)?
    var deleteFromHistory: (() -> Void)?
    @State private var hovered = false
    @Environment(\.colorScheme) private var colorScheme
    private var isCurrent: Bool { library.currentSong?.id == song.id }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCurrent ? "speaker.wave.2.fill" : "music.note")
                .font(.caption).foregroundStyle(isCurrent ? ThemePalette.accent(for: colorScheme) : Color.secondary)
                .frame(width: 16)
                .accessibilityLabel(isCurrent ? "Current song" : "Song")
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.body.weight(.medium))
                    .foregroundStyle(isCurrent ? ThemePalette.accent(for: colorScheme) : Color.primary).lineLimit(1)
                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(song.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if let downloads = library.downloads { DownloadAction(song: song, downloads: downloads) }
            Button { library.toggleFavorite(song) } label: {
                Image(systemName: library.favoriteIDs.contains(song.id) ? "heart.fill" : "heart")
                    .foregroundStyle(library.favoriteIDs.contains(song.id) ? ThemePalette.accent(for: colorScheme) : Color.secondary)
            }
            .help(library.favoriteIDs.contains(song.id) ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel("\(library.favoriteIDs.contains(song.id) ? "Unfavorite" : "Favorite") \(song.title)")
            Button {
                if let remove { remove() } else { library.enqueue(song) }
            } label: {
                Image(systemName: remove == nil ? "plus" : "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .help(remove == nil ? "Add to Queue" : "Remove from Queue")
            .accessibilityLabel("\(remove == nil ? "Add to queue:" : "Remove from queue:") \(song.title)")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 9).padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(hovered ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Play") { library.play(song) }
            Button("Play Next") { library.playNext(song) }
            Button("Add to Queue") { library.enqueue(song) }
            if let deleteFromHistory {
                Divider()
                Button("Delete from History", role: .destructive, action: deleteFromHistory)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
