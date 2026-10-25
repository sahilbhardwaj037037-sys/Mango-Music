import Foundation
import Testing
@testable import MangoMusic

struct BundledToolTests {
    @Test func packagedToolsFailClosed() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent("Mango-\(UUID()).app")
        let directory = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        // Even installed global mpv must never mask an incomplete packaged app.
        #expect(throws: PlaybackError.missingTool("mpv")) {
            try ToolLocator.locate("mpv", bundleURL: bundle, requiresBundledTools: true)
        }
        let tool = directory.appendingPathComponent("mpv")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        #expect(throws: PlaybackError.missingTool("mpv")) {
            try ToolLocator.locate("mpv", bundleURL: bundle, requiresBundledTools: true)
        }
        try FileManager.default.removeItem(at: tool)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tool.path)
        #expect(throws: PlaybackError.missingTool("mpv")) {
            try ToolLocator.locate("mpv", bundleURL: bundle, requiresBundledTools: true)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        #expect(try ToolLocator.locate("mpv", bundleURL: bundle, requiresBundledTools: true) == tool)
        try FileManager.default.removeItem(at: tool)
        try FileManager.default.createSymbolicLink(at: tool, withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
        #expect(throws: PlaybackError.missingTool("mpv")) {
            try ToolLocator.locate("mpv", bundleURL: bundle, requiresBundledTools: true)
        }
    }
    @Test func compiledOutScriptingNeedsNoRuntimeOptions() {
        let bundled = MPVConnection.arguments(socketPath: "/tmp/test", scriptingAvailable: false)
        #expect(!bundled.contains("--load-scripts=no"))
        #expect(!bundled.contains("--ytdl=no"))
        #expect(bundled.contains("--media-controls=no"))
        #expect(bundled.contains("--input-ipc-server=/tmp/test"))
        #expect(MPVConnection.arguments(socketPath: "/tmp/test").contains("--load-scripts=no"))
    }
    @Test func packagedPathExcludesDevelopmentTools() {
        #expect(ToolLocator.runtimePath(for: URL(fileURLWithPath: "/tmp/Mango Music.app/Contents/MacOS/yt-dlp")) == "/tmp/Mango Music.app/Contents/MacOS:/usr/bin:/bin")
        #expect(ToolLocator.runtimePath(for: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")).contains("/opt/homebrew/bin"))
    }
}
