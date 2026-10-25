import SwiftUI
import AppKit

@main
struct MangoMusicApp: App {
    @NSApplicationDelegateAdaptor(MusicApplicationDelegate.self) private var delegate
    @State private var library = MusicLibrary()

    var body: some Scene {
        Window("Mango Music", id: "main") {
            MusicRootWindow(library: library, delegate: delegate)
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

private struct MusicRootWindow: View {
    let library: MusicLibrary
    let delegate: MusicApplicationDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        MainWindow(library: library)
            .onAppear {
                delegate.library = library
                delegate.reopenWindow = { openWindow(id: "main") }
            }
            .tint(.pink)
            .frame(minWidth: 700, minHeight: 480)
    }
}

@MainActor
final class MusicApplicationDelegate: NSObject, NSApplicationDelegate {
    var library: MusicLibrary?
    var reopenWindow: (() -> Void)?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { library?.shutdown() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { reopenWindow?() }
        return true
    }
}
