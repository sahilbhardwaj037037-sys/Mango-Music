import Foundation

enum PlaybackEvent: Equatable {
    case loaded, clockAnchor, position(Double), duration(Double), paused(Bool), buffering(Bool), volume(Double), ended, failure(String)
}

@MainActor
protocol AudioPlaying: AnyObject {
    var onEvent: ((UUID, PlaybackEvent) -> Void)? { get set }
    func load(_ url: URL, request: UUID, volume: Double, paused: Bool) async throws
    func pause(_ paused: Bool) async throws
    func seek(_ position: Double) async throws
    func volume(_ value: Double) async throws
    func stop() async
    func interrupt()
    func shutdown()
}

extension AudioPlaying {
    func load(_ url: URL, request: UUID, volume: Double) async throws {
        try await load(url, request: request, volume: volume, paused: false)
    }
}

@MainActor
final class MPVPlaybackEngine: AudioPlaying {
    var onEvent: ((UUID, PlaybackEvent) -> Void)?
    private let connection: MPVConnection
    private var request = UUID()
    private var entry: Int?
    private var completed = false
    private var watchdog: Task<Void, Never>?
    private var interruptionTask: Task<Void, Never>?
    init(connection: MPVConnection = MPVConnection()) { self.connection = connection }

    func load(_ url: URL, request: UUID, volume: Double, paused: Bool) async throws {
        watchdog?.cancel()
        await interruptionTask?.value
        try Task.checkCancellation()
        try await connection.start(sink: { [weak self] id, message in
            Task { @MainActor in self?.receive(id, message) }
        }, failure: { [weak self] id, error in
            Task { @MainActor in self?.onEvent?(id, .failure(error.localizedDescription)) }
        })
        try Task.checkCancellation()
        // Await a stop acknowledgement before changing generations. Old queued events keep their old ID.
        try await connection.command(["stop"])
        try Task.checkCancellation()
        self.request = request; entry = nil; completed = false
        await connection.setGeneration(request)
        try await connection.command(["set_property", "volume", min(1, max(0, volume)) * 100])
        try await connection.command(["set_property", "pause", paused])
        try Task.checkCancellation()
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard let self, self.request == request else { return }
            self.onEvent?(request, .failure(PlaybackError.timeout.localizedDescription))
            await self.connection.shutdown()
        }
        if url.isFileURL {
            // Downloaded media must be self-contained; local files cannot request remote references.
            try await connection.command(["loadfile", url.absoluteString, "replace", -1,
                ["demuxer": "lavf", "demuxer-lavf-o": "protocol_whitelist=file", "access-references": "no", "autoload-files": "no"]])
        } else { try await connection.command(["loadfile", url.absoluteString, "replace"]) }
    }
    func pause(_ paused: Bool) async throws { try await connection.command(["set_property", "pause", paused]) }
    func seek(_ position: Double) async throws { try await connection.command(["seek", max(0, position), "absolute+exact"]) }
    func volume(_ value: Double) async throws {
        try await connection.command(["set_property", "volume", min(1, max(0, value)) * 100])
    }
    func stop() async {
        watchdog?.cancel(); completed = true
        try? await connection.command(["stop"])
    }
    func interrupt() {
        watchdog?.cancel(); completed = true
        connection.owner.shutdown()
        interruptionTask = Task { await connection.shutdown() }
    }
    func shutdown() {
        watchdog?.cancel()
        connection.owner.shutdown(permanent: true)
        Task { await connection.shutdown() }
    }
    private func receive(_ id: UUID, _ message: MPVMessage) {
        guard id == request else { return }
        switch message.event {
        case "start-file": entry = message.entry
        case "file-loaded": watchdog?.cancel(); onEvent?(id, .loaded)
        case "playback-restart": onEvent?(id, .clockAnchor)
        case "end-file":
            guard !completed, message.entry == entry, entry != nil else { return }
            if message.reason == "eof" {
                completed = true; watchdog?.cancel(); onEvent?(id, .ended)
            } else if message.reason == "error" {
                completed = true; watchdog?.cancel()
                onEvent?(id, .failure(PlaybackError.playback.localizedDescription))
            }
        case "property-change":
            switch message.name {
            case "time-pos": if let v = message.number, v.isFinite { onEvent?(id, .position(max(0, v))) }
            case "duration": if let v = message.number, v.isFinite, v > 0 { onEvent?(id, .duration(v)) }
            case "pause": if let v = message.flag { onEvent?(id, .paused(v)) }
            case "paused-for-cache": if let v = message.flag { onEvent?(id, .buffering(v)) }
            case "volume": if let v = message.number, v.isFinite { onEvent?(id, .volume(v / 100)) }
            default: break
            }
        default: break
        }
    }
}
