import SwiftUI
import Combine
import AppKit

struct MainWindow: View {
    @Bindable var library: MusicLibrary

    var body: some View {
        VStack(spacing: 0) {
            // This region always occupies the same height, including while idle.
            // Ordinary asynchronous saves must not move the library at every EOF.
            SaveStatusView(librarySaving: library.hasUnsavedChanges && library.persistenceError == nil && !library.isRestoring,
                           downloadsSaving: library.downloads.map { $0.hasUnsavedChanges && $0.persistenceError == nil } == true)
            if library.isRestoring || library.persistenceError != nil {
                HStack {
                    Text(library.persistenceError ?? "Restoring library…")
                        .font(.caption).foregroundStyle(.secondary)
                    if library.persistenceError != nil { Button("Retry", action: library.retryPersistence) }
                    Spacer()
                }.padding(10)
            }
            if let downloads = library.downloads, let error = downloads.persistenceError {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry", action: downloads.retryPersistence)
                    Spacer()
                }.padding(10)
            }
            HStack(spacing: 0) {
                if library.sidebarVisible {
                    sidebar
                        .frame(width: 172)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }
                LibraryContent(library: library)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .disabled(!library.canEditLibrary)
            Divider()
            PlaybackBar(library: library).disabled(!library.canEditLibrary)
        }
        .background(.background)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: library.toggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar (⌘B)")
                .accessibilityLabel("Toggle sidebar")
            }
            ToolbarItem(placement: .primaryAction) {
                Text(library.isLoading ? "Loading audio…" : library.isBuffering ? "Buffering…" : "")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .background(PlaybackKeyboardHandler(library: library))
        .onDisappear { library.cancelSearch() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Mango Music").font(.title3.weight(.semibold)).padding(.horizontal, 14)
            List(selection: $library.destination) {
                Section("Library") {
                    ForEach(Destination.allCases) { destination in
                        Label(destination.rawValue, systemImage: destination.symbol)
                            .tag(destination)
                            .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.sidebar)
            Spacer(minLength: 0)
            Text("A little space for your music.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.bottom, 16)
        }
        .padding(.top, 24)
        .background(.bar)
    }
}

/// Ordinary saves have a reserved line; errors/restoration retain their full banners.
/// There are no controls here to capture mouse or keyboard input during a transition.
struct SaveStatusView: View {
    let librarySaving: Bool
    let downloadsSaving: Bool

    var message: String? {
        switch (librarySaving, downloadsSaving) {
        case (true, true): "Saving library and Downloads…"
        case (true, false): "Saving library…"
        case (false, true): "Saving Downloads…"
        case (false, false): nil
        }
    }

    var body: some View {
        HStack {
            Text(message ?? " ")
                .lineLimit(1)
                .opacity(message == nil ? 0 : 1)
                .accessibilityHidden(message == nil)
            Spacer(minLength: 0)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .allowsHitTesting(false)
    }
}
