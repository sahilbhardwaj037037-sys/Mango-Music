import AppKit
import SwiftUI
import Testing
@testable import MangoMusic

private actor SaveStatusSleeper {
    private var pending: [(Duration, CheckedContinuation<Void, any Error>)] = []
    func sleep(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { pending.append((duration, $0)) }
    }
    func count() -> Int { pending.count }
    func delay() -> Duration? { pending.first?.0 }
    func resume() { pending.removeFirst().1.resume() }
}

@MainActor
struct SaveStatusTests {
    private func waitForSleep(_ sleeper: SaveStatusSleeper) async throws {
        let deadline = Date().addingTimeInterval(2)
        while await sleeper.count() == 0, Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(await sleeper.count() > 0)
    }

    @Test func savingAndIdleKeepIdenticalLayoutHeight() async {
        // Offscreen native hosting only: no window or application is launched.
        let status = SaveStatusPresentation(sleep: { _ in })
        let host = NSHostingView(rootView: SaveStatusView(librarySaving: false, downloadsSaving: false, presentation: status).frame(width: 700))
        let idle = host.fittingSize
        #expect(idle.height == 22)
        for (library, downloads) in [(true, false), (false, true), (true, true), (false, false)] {
            await status.update(saving: library || downloads)
            host.rootView = SaveStatusView(librarySaving: library, downloadsSaving: downloads, presentation: status).frame(width: 700)
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize == idle)
        }
    }

    @Test func shortRepeatedSavesNeverAppearEvenWithLateTimerCompletion() async throws {
        let sleeper = SaveStatusSleeper(), status = SaveStatusPresentation(sleep: { try await sleeper.sleep($0) })
        for _ in 0..<3 {
            let task = Task { await status.update(saving: true) }
            try await waitForSleep(sleeper)
            #expect(await sleeper.delay() == .milliseconds(800))
            #expect(!status.isVisible)
            await status.update(saving: false)
            await sleeper.resume(); await task.value
            #expect(!status.isVisible)
        }
    }

    @Test func slowSaveAppearsAndHidesOnlyAfterIdleGrace() async throws {
        let sleeper = SaveStatusSleeper(), status = SaveStatusPresentation(sleep: { try await sleeper.sleep($0) })
        let start = Task { await status.update(saving: true) }
        try await waitForSleep(sleeper)
        #expect(!status.isVisible)
        await sleeper.resume(); await start.value
        #expect(status.isVisible)
        let end = Task { await status.update(saving: false) }
        try await waitForSleep(sleeper)
        #expect(await sleeper.delay() == .seconds(1))
        #expect(status.isVisible)
        await sleeper.resume(); await end.value
        #expect(!status.isVisible)
    }

    @Test func anotherSaveBridgesIdleGapWithoutFlashing() async throws {
        let sleeper = SaveStatusSleeper(), status = SaveStatusPresentation(sleep: { try await sleeper.sleep($0) })
        let start = Task { await status.update(saving: true) }
        try await waitForSleep(sleeper)
        await sleeper.resume(); await start.value
        let end = Task { await status.update(saving: false) }
        try await waitForSleep(sleeper)
        await status.update(saving: true) // The pending hide must not win later.
        await sleeper.resume(); await end.value
        #expect(status.isVisible)
        status.reset()
    }

    @Test func errorsAndDisappearanceImmediatelyResetAndInvalidateTimers() async throws {
        let sleeper = SaveStatusSleeper(), status = SaveStatusPresentation(sleep: { try await sleeper.sleep($0) })
        let pending = Task { await status.update(saving: true) }
        try await waitForSleep(sleeper)
        status.reset()
        await sleeper.resume(); await pending.value
        #expect(!status.isVisible)
        let slow = Task { await status.update(saving: true) }
        try await waitForSleep(sleeper)
        await sleeper.resume(); await slow.value
        #expect(status.isVisible)
        await status.update(saving: false, suppressed: true)
        #expect(!status.isVisible)
    }

    @Test func cancelledShowCannotPublishEvenIfSleepIgnoresCancellation() async throws {
        let sleeper = SaveStatusSleeper(), status = SaveStatusPresentation(sleep: { try await sleeper.sleep($0) })
        let pending = Task { await status.update(saving: true) }
        try await waitForSleep(sleeper)
        pending.cancel()
        await sleeper.resume(); await pending.value
        #expect(!status.isVisible)
    }

    @Test func alreadyCancelledUpdateCannotInvalidateNewerShow() async throws {
        let sleeper = SaveStatusSleeper(), staleGate = SaveStatusSleeper()
        let status = SaveStatusPresentation(sleep: { try await sleeper.sleep($0) })
        let stale = Task {
            try? await staleGate.sleep(.zero)
            await status.update(saving: false, suppressed: true)
        }
        try await waitForSleep(staleGate)
        stale.cancel()
        let fresh = Task { await status.update(saving: true) }
        try await waitForSleep(sleeper)
        await staleGate.resume(); await stale.value
        await sleeper.resume(); await fresh.value
        #expect(status.isVisible)
    }

    @Test func visibleLabelStaysGenericAndSuppressionHidesIt() async {
        let status = SaveStatusPresentation(sleep: { _ in })
        #expect(SaveStatusView(librarySaving: true, downloadsSaving: false, presentation: status).message == nil)
        await status.update(saving: true)
        for (library, downloads) in [(true, false), (false, true), (true, true)] {
            #expect(SaveStatusView(librarySaving: library, downloadsSaving: downloads, presentation: status).message == "Saving changes…")
        }
        #expect(SaveStatusView(librarySaving: true, downloadsSaving: false, suppressed: true, presentation: status).message == nil)
    }
}
