import AppKit
import Foundation
import SQLite3

/// Launch the actual packaged executable with kernel write protection for the real home.
/// No UI commands or playback are synthesized; those remain separate manual checks.
@main struct IsolatedLaunchProbe {
    @MainActor static func main() async throws {
        let arguments = CommandLine.arguments
        let manual = arguments.count == 4 && arguments[3] == "--manual"
        guard arguments.count == 3 || manual else { throw ProbeError.failed("Expected app, isolated home and optional --manual") }
        let app = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
        let isolated = URL(fileURLWithPath: CommandLine.arguments[2]).resolvingSymlinksInPath()
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let allowed = project.appendingPathComponent(".build").resolvingSymlinksInPath().path + "/"
        guard app.path.hasPrefix(allowed), isolated.path.hasPrefix(allowed),
              !app.path.hasPrefix(isolated.path + "/"), !isolated.path.hasPrefix(app.path + "/"),
              NSRunningApplication.runningApplications(withBundleIdentifier: "com.localmusic.MangoMusic").isEmpty else {
            throw ProbeError.failed("Use separate project .build paths and quit other Mango Music instances first")
        }
        try FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let realHome = FileManager.default.homeDirectoryForCurrentUser.path
        func literal(_ path: String) -> String { "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let profile = """
        (version 1)
        (allow default)
        (deny file-write* (subpath "/Applications"))
        (deny file-write* (require-all (subpath \(literal(realHome))) (require-not (subpath \(literal(isolated.path))))))
        (deny file-read* (subpath \(literal(realHome + "/Library/Application Support/MangoMusic"))))
        (deny file-read* (literal \(literal(realHome + "/Library/Preferences/com.localmusic.MangoMusic.plist"))))
        """
        let log = isolated.appendingPathComponent("launch.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        for attempt in 1...(manual ? 1 : 2) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-p", profile, app.appendingPathComponent("Contents/MacOS/MangoMusic").path]
            process.environment = ["PATH": "/usr/bin:/bin", "HOME": isolated.path, "CFFIXED_USER_HOME": isolated.path]
            process.standardOutput = handle; process.standardError = handle
            try process.run()
            defer { if process.isRunning { process.terminate() } }
            let database = isolated.appendingPathComponent("Library/Application Support/MangoMusic/library.sqlite3")
            for _ in 0..<100 {
                if FileManager.default.fileExists(atPath: database.path) { break }
                guard process.isRunning else { throw ProbeError.failed("Isolated app exited during startup") }
                try await Task.sleep(for: .milliseconds(100))
            }
            try await Task.sleep(for: .seconds(2))
            guard process.isRunning, let running = NSRunningApplication(processIdentifier: process.processIdentifier),
                  running.bundleURL?.resolvingSymlinksInPath() == app else { throw ProbeError.failed("App bundle/PID mismatch") }
            var db: OpaquePointer?
            guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw ProbeError.failed("Isolated database missing") }
            var statement: OpaquePointer?
            let prepared = sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
            let schema = prepared == SQLITE_OK && sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : -1
            sqlite3_finalize(statement); sqlite3_close(db)
            guard schema == 3 else { throw ProbeError.failed("Expected isolated v3 database") }
            if manual {
                print("Isolated app ready for manual checks. Quit with Cmd+Q when finished; keep this terminal running.")
                while process.isRunning { try await Task.sleep(for: .milliseconds(500)) }
            } else {
                guard running.terminate() else { throw ProbeError.failed("Normal quit request rejected") }
                for _ in 0..<100 {
                    if !process.isRunning { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            guard !process.isRunning, process.terminationStatus == 0 else { throw ProbeError.failed("Normal app quit failed") }
            print("Isolated packaged launch/normal quit \(attempt): passed; exact app PID/path, restricted PATH, v3 database under isolated home")
        }
        print("Real home writes and installed-app writes denied by kernel profile; real MangoMusic library/preferences reads denied.")
    }
}

private enum ProbeError: Error { case failed(String) }
