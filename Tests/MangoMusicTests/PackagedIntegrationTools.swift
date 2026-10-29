import Foundation
@testable import MangoMusic

// Explicit test-only override; production never accepts executable paths from environment variables.
enum PackagedIntegrationTools {
    static var bundle: URL? {
        ProcessInfo.processInfo.environment["MANGO_PACKAGED_APP"].map { URL(fileURLWithPath: $0) }
    }
    static var mpv: URL? { bundle.map { $0.appendingPathComponent("Contents/MacOS/mpv") } }
    static var ytDLP: URL? { bundle.map { $0.appendingPathComponent("Contents/MacOS/yt-dlp") } }
    static var conversion: VerifiedConversionTools? {
        bundle.flatMap { VerifiedConversionTools.discover(bundleURL: $0, bundled: true) }
    }
    static var fixtureEncoder: URL {
        conversion?.ffmpeg ?? URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    }
    static var resolver: AudioStreamResolver { AudioStreamResolver(executableURL: ytDLP) }
}
