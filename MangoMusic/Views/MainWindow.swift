import SwiftUI
import Combine
import AppKit

struct MainWindow: View {
    @Bindable var library: MusicLibrary

    var body: some View {
        VStack(spacing: 0) {
            if library.isRestoring || library.hasUnsavedChanges || library.persistenceError != nil {
                HStack {
                    Text(library.persistenceError ?? (library.isRestoring ? "Restoring library…" : "Saving library…"))
                        .font(.caption).foregroundStyle(.secondary)
                    if library.persistenceError != nil { Button("Retry", action: library.retryPersistence) }
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
