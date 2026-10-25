import Foundation

struct FavoriteRecord: Equatable, Sendable {
    let song: Song
    let addedAt: Date
}

struct LibrarySnapshot: Equatable, Sendable {
    var favorites: [FavoriteRecord] = []
    var history: [HistoryEntry] = []
    var queue: [QueueEntry] = []
    var currentSong: Song?
    /// A queue selection is recoverable until the first positive playback-clock event.
    var pendingQueueEntry: QueueEntry?
    var revision = 0
}

protocol LibraryPersisting: Sendable {
    func load() async throws -> LibrarySnapshot
    func save(_ snapshot: LibrarySnapshot, expecting revision: Int) async throws -> Int
    func close() async
}

enum PersistenceError: Error, LocalizedError, Equatable {
    case unavailable, corrupt, newerSchema, unrecognizedSchema, invalidData, writeFailed, conflict, closed
    var errorDescription: String? {
        switch self {
        case .unavailable: "The local library could not be opened. Check the Application Support folder and available disk space."
        case .corrupt: "The local library could not be read. Your database has been preserved; restore a backup or repair it before retrying."
        case .newerSchema: "This library was created by a newer Mango Music version. Open it with that version."
        case .unrecognizedSchema: "The library schema is not recognized. The existing database has been preserved."
        case .invalidData: "The library contains invalid data. No changes were saved."
        case .writeFailed: "Library changes were not saved. Check disk space and permissions, then retry saving before quitting."
        case .conflict: "Another app instance changed the library. Changes in this window are not saved. Close the other instance and preserve these edits before reopening."
        case .closed: "The library is closed. Reopen Mango Music to continue."
        }
    }
}
