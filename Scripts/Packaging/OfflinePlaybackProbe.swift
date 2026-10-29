import Foundation
import Darwin

/// Compile with the current Models, Services and ViewModels sources; uses null audio.
@main struct OfflinePlaybackProbe {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        guard args.count > 3, args[1] == "play" else { throw ProbeError.failed("Expected play, bundled mpv and generated eight-second audio files") }
        // A kernel-denied IPv4 connection distinguishes policy denial from a closed server.
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        var denied = fd < 0 && (errno == EPERM || errno == EACCES)
        if fd >= 0 {
            var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET); address.sin_port = UInt16(9).bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            denied = result == -1 && (errno == EPERM || errno == EACCES)
            Darwin.close(fd)
        }
        guard denied else { throw ProbeError.failed("Network was not denied by policy") }
        let connection = MPVConnection(executable: URL(fileURLWithPath: args[2]), audioOutput: "null")
        let player = MPVPlaybackEngine(connection: connection)
        defer { player.shutdown() }
        var events: [PlaybackEvent] = []
        player.onEvent = { _, event in events.append(event) }
        func wait(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(10)
            while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            guard condition() else { throw ProbeError.failed("Event deadline") }
        }
        var records: [[String: Any]] = [], ownedPID: Int32?
        var ownedDirectory: URL?
        for path in args.dropFirst(3) {
            events = []
            let url = URL(fileURLWithPath: path)
            try await player.load(url, request: UUID(), volume: 0.1)
            try await wait { events.contains(.loaded) && events.contains { if case .position(let p) = $0 { return p > 0.1 }; return false } }
            guard !events.contains(where: { if case .failure = $0 { return true }; return false }) else { throw ProbeError.failed("Playback failure") }
            let pid = connection.owner.processIdentifier
            if let ownedPID { guard pid == ownedPID else { throw ProbeError.failed("Persistent process changed") } }
            else { ownedPID = pid; ownedDirectory = connection.owner.ownedDirectory }
            if records.isEmpty {
                try await player.pause(true); try await wait { events.contains(.paused(true)) }
                try await player.seek(2)
                try await wait { events.contains { if case .position(let p) = $0 { return p >= 1.9 }; return false } }
                try await player.pause(false); try await wait { events.contains(.paused(false)) }
            }
            let duration = events.compactMap { event -> Double? in if case .duration(let d) = event { return d }; return nil }.last ?? 0
            guard duration > 7.8 && duration < 8.2 else { throw ProbeError.failed("Duration mismatch") }
            try await player.seek(max(0,duration - 0.3)); try await wait { events.contains(.ended) }
            guard events.filter({ $0 == .ended }).count == 1 else { throw ProbeError.failed("Duplicate EOF") }
            records.append(["file":url.lastPathComponent,"extension":url.pathExtension,"duration":duration,"positive_clock":true,"natural_eof_once":true])
        }
        events = []
        try await player.load(URL(fileURLWithPath: args[3] + ".missing"), request: UUID(), volume: 0.1)
        try await wait { events.contains { if case .failure = $0 { return true }; return false } }
        await player.stop(); await connection.shutdown()
        if let ownedPID { try await wait { Darwin.kill(ownedPID,0) == -1 && errno == ESRCH } }
        let socketRemoved = ownedDirectory.map { !FileManager.default.fileExists(atPath:$0.path) } ?? false
        guard socketRemoved else { throw ProbeError.failed("Owned socket directory remains") }
        let report: [String:Any] = ["network_denied":denied,"files":records,"same_persistent_pid":true,
            "missing_file_failed_gracefully":true,"owned_pid_exited":true,"owned_socket_removed":socketRemoved,"audio_output":"null"]
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
enum ProbeError: Error { case failed(String) }
