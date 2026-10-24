import SwiftUI

@main
struct LocalMusicApp: App {
    @State private var library = MusicLibrary()

    var body: some Scene {
        Window("LocalMusic", id: "main") {
            MainWindow(library: library)
                .tint(.pink)
                .frame(minWidth: 700, minHeight: 480)
        }
        .defaultSize(width: 800, height: 560)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { library.toggleSidebar() }
                    .keyboardShortcut("b", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Search Library") { library.focusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
