import Foundation

enum DownloadStatus: String, Sendable, CaseIterable {
    case queued, downloading, validating, complete, cancelled, failed, interrupted, missing, deleting
    var active: Bool { self == .queued || self == .downloading || self == .validating }
    var label: String {
        switch self {
        case .queued: "Queued"
        case .downloading: "Downloading"
        case .validating: "Checking audio"
        case .complete: "Downloaded"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        case .interrupted: "Interrupted"
        case .missing: "File missing or damaged"
        case .deleting: "Deleting"
        }
    }
}

struct DownloadRecord: Identifiable, Equatable, Sendable {
    var id: String { song.id }
    var song: Song
    let sourceURL: URL
    var attempt = UUID()
    var status: DownloadStatus = .queued
    var relativePath: String?
    var format: String?
    var fileSize: Int64 = 0
    var downloadedAt: Date?
    var checksum: String?
    var error: String?
}

struct DownloadSnapshot: Sendable {
    var records: [DownloadRecord] = []
    var revision = 0
}
protocol DownloadPersisting: Sendable {
    func loadDownloads() async throws -> DownloadSnapshot
    func saveDownloads(_ records: [DownloadRecord], expecting revision: Int) async throws -> Int
}

struct DownloadProgress: Sendable, Equatable {
    let bytes: Int64
    let total: Int64?
    var fraction: Double? { total.flatMap { $0 > 0 ? min(1, max(0, Double(bytes) / Double($0))) : nil } }
}
struct DownloadLimits: Sendable {
    var perFile: Int64 = 512 * 1024 * 1024
    var total: Int64 = 5 * 1024 * 1024 * 1024
    var freeReserve: Int64 = 256 * 1024 * 1024
    var timeout: TimeInterval = 900
}
struct ValidatedAudio: Sendable {
    let duration: Double
    let format: String
}
enum DownloadError: Error, LocalizedError, Equatable {
    case unavailable, invalidAudio, unsafePath, storageLimit, noSpace, offline, missing, conflict, tools, timeout
    var errorDescription: String? {
        switch self {
        case .unavailable: "The audio could not be downloaded. Check the source and connection, then Retry."
        case .invalidAudio: "The download is not a supported, complete audio file."
        case .unsafePath: "The managed Downloads folder or file path is unsafe. No outside files were changed."
        case .storageLimit: "Download storage limit reached (512 MB per song, 5 GB total). Delete downloads to make room."
        case .noSpace: "Not enough free disk space. Free space, then Retry."
        case .offline: "Offline Mode is on. Download this song or turn Offline Mode off to stream."
        case .missing: "The downloaded file is missing or damaged. Download it again when online."
        case .conflict: "Another app instance changed Downloads. Reopen after preserving unsaved changes."
        case .tools: "This format needs verified FFmpeg tools, which are unavailable in this build."
        case .timeout: "The download timed out. Check the connection, then Retry."
        }
    }
}

/// Shared synchronous policy: playback and recommendation tasks also recheck their generations.
final class PlaybackNetworkPolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var offline = false
    var offlineOnly: Bool { lock.lock(); defer { lock.unlock() }; return offline }
    func setOffline(_ value: Bool) { lock.lock(); offline = value; lock.unlock() }
}
