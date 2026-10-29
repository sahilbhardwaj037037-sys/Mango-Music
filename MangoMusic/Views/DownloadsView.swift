import SwiftUI

struct DownloadAction: View {
    let song: Song
    @Bindable var downloads: DownloadManager
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Group {
            if let record = downloads.record(for: song) {
                if record.status.active {
                    HStack(spacing: 4) {
                        if let fraction = downloads.progress[song.id]?.fraction {
                            ProgressView(value: fraction).frame(width: 30).help("\(Int(fraction * 100))% downloaded")
                        } else { ProgressView().controlSize(.small) }
                        Button { downloads.cancel(song.id) } label: { Image(systemName: "xmark.circle") }
                            .help("Cancel Download").accessibilityLabel("Cancel download of \(song.title)")
                    }
                } else if record.status == .complete {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(ThemePalette.success(for: colorScheme))
                        .help("Downloaded").accessibilityLabel("\(song.title) is downloaded")
                } else {
                    Button { Task { await downloads.retry(song.id) } } label: { Image(systemName: "arrow.clockwise.circle") }
                        .disabled(downloads.offline || downloads.busyIDs.contains(song.id))
                        .help("\(record.status.label): Retry Download").accessibilityLabel("Retry download of \(song.title)")
                }
            } else {
                Button { downloads.enqueue(song) } label: { Image(systemName: "arrow.down.circle") }
                    .disabled(downloads.offline || !downloads.canEdit)
                    .help("Download for offline playback").accessibilityLabel("Download \(song.title)")
            }
        }
        .buttonStyle(.borderless)
        .disabled(!downloads.canEdit)
    }
}

struct DownloadsView: View {
    @Bindable var library: MusicLibrary
    @Bindable var downloads: DownloadManager
    @State private var selection: String?
    @State private var deletion: Set<String> = []
    @State private var showDeletion = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(downloads.completed.count) downloaded · \(ByteCountFormatter.string(fromByteCount: downloads.bytesUsed, countStyle: .file)) used")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear Downloads…", role: .destructive) {
                    deletion = Set(downloads.records.map(\.id)); showDeletion = true
                }.disabled(downloads.records.isEmpty || !downloads.canEdit)
            }.padding(.horizontal, 24)
            if downloads.isRestoring { ProgressView("Restoring Downloads…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if downloads.records.isEmpty {
                ContentUnavailableView("Your offline library starts here", systemImage: "arrow.down.circle",
                    description: Text("Use the Download button beside a song. Downloaded files play without a connection."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(downloads.records) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            SongRow(song: record.song, library: library)
                            HStack {
                                Text(record.status.label)
                                if record.fileSize > 0 { Text(ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file)) }
                                if let fraction = downloads.progress[record.id]?.fraction { Text("\(Int(fraction * 100))%") }
                                Spacer()
                                Button("Play") { library.play(record.song) }.disabled(record.status != .complete)
                                Button("Delete Download…", role: .destructive) { deletion = [record.id]; showDeletion = true }
                            }.font(.caption).foregroundStyle(.secondary)
                            if let error = record.error { Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                        .tag(record.id)
                        .simultaneousGesture(TapGesture(count: 2).onEnded { if record.status == .complete { library.play(record.song) } })
                    }
                }.listStyle(.inset)
                .onKeyPress(.return) {
                    guard let record = downloads.records.first(where: { $0.id == selection && $0.status == .complete }) else { return .ignored }
                    library.play(record.song); return .handled
                }
            }
        }
        .confirmationDialog(deletion.count == 1 ? "Delete this download?" : "Clear all downloads?", isPresented: $showDeletion, titleVisibility: .visible) {
            Button(deletion.count == 1 ? "Delete Download" : "Clear Downloads", role: .destructive) {
                let ids = deletion
                if ids.contains(library.currentSong?.id ?? ""), library.isPlayingLocal { library.stop() }
                Task { await downloads.delete(ids) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Removes managed downloaded files. Favorites, History, and Queue are preserved.") }
    }
}
