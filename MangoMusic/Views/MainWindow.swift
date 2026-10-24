import SwiftUI
import Combine
import AppKit

struct MainWindow: View {
    @Bindable var library: MusicLibrary
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
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
            Divider()
            PlaybackBar(library: library)
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
                Text("Mock Playback")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .background(PlaybackKeyboardHandler(library: library))
        .onReceive(timer) { _ in library.tick() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            library.cancelSearch()
        }
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
