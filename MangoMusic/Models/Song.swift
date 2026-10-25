import Foundation

struct Song: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let duration: TimeInterval
    var durationKnown: Bool = true
    var durationLabel: String { durationKnown ? duration.timestamp : "—" }

    static let samples: [Song] = [
        Song(id: "1", title: "Morning Light", artist: "The Quiet Hours", duration: 224),
        Song(id: "2", title: "A Walk Along the Coast", artist: "June & the Sea", duration: 197),
        Song(id: "3", title: "Slow Motion", artist: "Paper Satellites", duration: 263),
        Song(id: "4", title: "Almost Home", artist: "Oliver Lane", duration: 208),
        Song(id: "5", title: "After the Rain", artist: "Mira Sol", duration: 242),
        Song(id: "6", title: "City Windows", artist: "The Quiet Hours", duration: 185),
        Song(id: "7", title: "Golden", artist: "Sunday Letters", duration: 216),
        Song(id: "8", title: "Stay a Little Longer", artist: "June & the Sea", duration: 251),
        Song(id: "9", title: "Blue Hour", artist: "Mira Sol", duration: 189),
        Song(id: "10", title: "Somewhere New", artist: "Paper Satellites", duration: 235)
    ]
}

struct QueueEntry: Identifiable, Equatable, Sendable {
    var id = UUID()
    let song: Song
}

struct HistoryEntry: Identifiable, Equatable, Sendable {
    var id = UUID()
    let song: Song
    let playedAt: Date
    var playCount = 1
}

enum Destination: String, CaseIterable, Identifiable {
    case search = "Search", queue = "Up Next", favorites = "Favorites", history = "History"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .search: "magnifyingglass"
        case .queue: "text.line.first.and.arrowtriangle.forward"
        case .favorites: "heart"
        case .history: "clock"
        }
    }
}

extension TimeInterval {
    var timestamp: String {
        let seconds = Int(min(Double(Int.max / 2), max(0, isFinite ? self : 0)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
