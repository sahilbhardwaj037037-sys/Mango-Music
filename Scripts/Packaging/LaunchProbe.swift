import AppKit
import Foundation

@main struct Probe {
    @MainActor static func main() async throws {
        let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let isolated = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: true)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.environment = ["PATH": "/usr/bin:/bin", "HOME": isolated.path, "CFFIXED_USER_HOME": isolated.path]
        let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        try await Task.sleep(for: .seconds(3))
        guard !app.isTerminated, app.bundleURL?.standardizedFileURL == appURL.standardizedFileURL else {
            fatalError("Packaged app did not remain running")
        }
        print("Launch Services launch: running; bundle path matches; restricted PATH supplied; PID \(app.processIdentifier)")
        guard app.terminate() else { fatalError("Quit request rejected") }
        for _ in 0..<100 {
            if app.isTerminated { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard app.isTerminated else { fatalError("Application did not quit") }
        print("Launch Services application quit: passed (no playback started in this probe)")
    }
}
