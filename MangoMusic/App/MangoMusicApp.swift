import SwiftUI
import AppKit

@main
struct MangoMusicApp: App {
    @NSApplicationDelegateAdaptor(MusicApplicationDelegate.self) private var delegate
    @State private var library = Self.makeLibrary()

    @MainActor private static func makeLibrary() -> MusicLibrary {
        let store = SQLiteLibraryStore()
        return MusicLibrary(store: store, downloadManager: DownloadManager(store: store))
    }

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
                delegate.attach(library)
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
    private var mediaIntegration: SystemMediaIntegration?
    func attach(_ library: MusicLibrary, integration suppliedIntegration: SystemMediaIntegration? = nil) {
        guard self.library == nil else { return }
        self.library = library
        let integration = suppliedIntegration ?? SystemMediaIntegration(library: library, adapter: NativeSystemMediaAdapter(), lifecycle: NativePlaybackLifecycle())
        mediaIntegration = integration
        integration.start()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let library else { return .terminateNow }
        if library.isClosing { return .terminateLater }
        Task {
            let saved = await library.prepareToQuit()
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { mediaIntegration?.stop(); library?.shutdown() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { reopenWindow?() }
        return true
    }
}
