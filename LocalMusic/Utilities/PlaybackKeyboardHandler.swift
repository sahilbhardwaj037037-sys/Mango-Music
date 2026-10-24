import SwiftUI
import AppKit

/// A window-scoped shortcut that leaves text editing and native controls alone.
struct PlaybackKeyboardHandler: NSViewRepresentable {
    let library: MusicLibrary

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(library: library) }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor final class Coordinator {
        let library: MusicLibrary
        weak var view: NSView?
        var monitor: Any?
        init(library: MusicLibrary) { self.library = library }
        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.view?.window,
                      event.window === window, window.isKeyWindow,
                      event.keyCode == 49,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                      !(window.firstResponder is NSTextView),
                      !(window.firstResponder is NSControl) else { return event }
                guard !event.isARepeat else { return nil }
                self.library.togglePlayback()
                return nil
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
