import AppKit
import SwiftUI
import Testing
@testable import MangoMusic

@MainActor
struct SaveStatusTests {
    @Test func savingAndIdleKeepIdenticalLayoutHeight() {
        // Offscreen native hosting only: no window or application is launched.
        let host = NSHostingView(rootView: SaveStatusView(librarySaving: false, downloadsSaving: false).frame(width: 700))
        let idle = host.fittingSize
        #expect(idle.height == 22)
        for (library, downloads) in [(true, false), (false, true), (true, true), (false, false)] {
            host.rootView = SaveStatusView(librarySaving: library, downloadsSaving: downloads).frame(width: 700)
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize == idle)
        }
    }

    @Test func bothWritersHaveVisibleStatusAndIdleHasNone() {
        #expect(SaveStatusView(librarySaving: true, downloadsSaving: false).message == "Saving library…")
        #expect(SaveStatusView(librarySaving: false, downloadsSaving: true).message == "Saving Downloads…")
        #expect(SaveStatusView(librarySaving: true, downloadsSaving: true).message == "Saving library and Downloads…")
        #expect(SaveStatusView(librarySaving: false, downloadsSaving: false).message == nil)
    }
}
