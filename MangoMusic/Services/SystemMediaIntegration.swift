import Foundation

enum MediaCommandKind: CaseIterable, Hashable, Sendable { case play, pause, toggle, next, previous, seek, stop }
enum MediaCommand: Equatable, Sendable {
    case play, pause, toggle, next, previous, seek(Double), stop
    var kind: MediaCommandKind {
        switch self { case .play: .play; case .pause: .pause; case .toggle: .toggle; case .next: .next
        case .previous: .previous; case .seek: .seek; case .stop: .stop }
    }
}
enum MediaPlaybackPhase: Sendable { case stopped, loading, playing, paused, buffering, failed }
enum SystemPlaybackState: Sendable { case stopped, playing, paused }
struct NowPlayingMetadata: Equatable, Sendable {
    let title: String
    let artist: String?
    let duration: Double?
    let elapsed: Double
    let rate: Double
}
struct MediaPlaybackSnapshot: Sendable {
    let generation: UUID
    let phase: MediaPlaybackPhase
    let title: String?
    let artist: String?
    let duration: Double?
    let elapsed: Double
    let positionRevision: Int
    let commands: Set<MediaCommandKind>

    var metadata: NowPlayingMetadata? {
        guard phase != .stopped, phase != .failed, let title else { return nil }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let position = elapsed.isFinite ? max(0, elapsed) : 0
        return NowPlayingMetadata(title: normalizedTitle.isEmpty ? "Unknown title" : normalizedTitle,
                                  artist: artist.flatMap { $0.isEmpty ? nil : $0 }, duration: duration,
                                  elapsed: duration.map { min($0, position) } ?? position, rate: phase == .playing ? 1 : 0)
    }
    var systemState: SystemPlaybackState { metadata == nil ? .stopped : (phase == .playing || phase == .buffering) ? .playing : .paused }
}

/// Apple extrapolates elapsed time from the last clock anchor. Ordinary updates are capped
/// at one per five seconds; metadata/state/generation changes and seek anchors publish immediately.
struct NowPlayingPublicationPolicy {
    private var previous: MediaPlaybackSnapshot?
    private var publishedAt: TimeInterval = 0
    mutating func shouldPublish(_ snapshot: MediaPlaybackSnapshot, now: TimeInterval) -> Bool {
        let publish: Bool
        if let old = previous {
            let a = old.metadata, b = snapshot.metadata
            let expected = (a?.elapsed ?? 0) + max(0, now - publishedAt) * (a?.rate ?? 0)
            publish = old.generation != snapshot.generation || old.phase != snapshot.phase
                || old.positionRevision != snapshot.positionRevision || a?.title != b?.title
                || a?.artist != b?.artist || a?.duration != b?.duration || (a == nil) != (b == nil)
                || (b != nil && (now - publishedAt >= 5 || abs((b?.elapsed ?? 0) - expected) > 1))
        } else { publish = true }
        if publish { previous = snapshot; publishedAt = now }
        return publish
    }
}

@MainActor
protocol SystemMediaAdapting: AnyObject {
    func activate(_ handler: @escaping @MainActor @Sendable (MediaCommand, UUID) -> Void)
    func setCommands(_ commands: Set<MediaCommandKind>, generation: UUID)
    func publish(_ metadata: NowPlayingMetadata?, state: SystemPlaybackState)
    func deactivate()
}
enum PlaybackInterruption: Sendable { case sleep, wake, outputChanged }
@MainActor
protocol PlaybackLifecycleMonitoring: AnyObject {
    func activate(_ handler: @escaping @MainActor @Sendable (PlaybackInterruption) -> Void)
    func deactivate()
}

/// App-scoped, not view-scoped. Closing/reopening a window never registers extra handlers.
@MainActor
final class SystemMediaIntegration {
    private let library: MusicLibrary
    private let adapter: any SystemMediaAdapting
    private let lifecycle: any PlaybackLifecycleMonitoring
    private let clock: () -> TimeInterval
    private var policy = NowPlayingPublicationPolicy()
    private(set) var isActive = false
    private var registration = UUID()
    init(library: MusicLibrary, adapter: any SystemMediaAdapting, lifecycle: any PlaybackLifecycleMonitoring,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.library = library; self.adapter = adapter; self.lifecycle = lifecycle; self.clock = clock
    }
    func start() {
        guard !isActive else { return }
        isActive = true; policy = NowPlayingPublicationPolicy()
        registration = UUID(); let epoch = registration
        adapter.activate { [weak self] command, generation in
            guard let self, self.isActive, self.registration == epoch else { return }
            self.library.handleMediaCommand(command, generation: generation)
        }
        lifecycle.activate { [weak self] reason in
            guard let self, self.isActive, self.registration == epoch else { return }
            self.library.handleInterruption(reason)
        }
        library.onMediaStateChange = { [weak self] in self?.synchronize() }
        synchronize()
    }
    private func synchronize() {
        guard isActive else { return }
        let snapshot = library.mediaPlaybackSnapshot
        adapter.setCommands(snapshot.commands, generation: snapshot.generation)
        if policy.shouldPublish(snapshot, now: clock()) { adapter.publish(snapshot.metadata, state: snapshot.systemState) }
    }
    func stop() {
        guard isActive else { return }
        isActive = false; registration = UUID()
        library.onMediaStateChange = nil
        lifecycle.deactivate(); adapter.deactivate()
    }
}

/// MediaPlayer callbacks need a synchronous status on an unspecified queue. Only immutable
/// command data crosses to the main actor; the generation is checked again before execution.
final class MediaCommandGate: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: Set<MediaCommandKind> = []
    private var generation = UUID()
    private var registration = UUID()
    private var handler: (@MainActor @Sendable (MediaCommand, UUID) -> Void)?
    func activate(_ handler: @escaping @MainActor @Sendable (MediaCommand, UUID) -> Void) {
        lock.lock(); defer { lock.unlock() }; self.handler = handler; registration = UUID()
    }
    func update(_ commands: Set<MediaCommandKind>, generation: UUID) {
        lock.lock(); defer { lock.unlock() }; self.commands = commands; self.generation = generation
    }
    func submit(_ command: MediaCommand) -> Bool {
        if case .seek(let value) = command, !value.isFinite || value < 0 { return false }
        lock.lock()
        let handler = commands.contains(command.kind) ? handler : nil, generation = generation, epoch = registration
        lock.unlock()
        guard let handler else { return false }
        Task { @MainActor [weak self] in
            guard self?.isCurrent(epoch) == true else { return }
            handler(command, generation)
        }
        return true
    }
    private func isCurrent(_ epoch: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }; return handler != nil && registration == epoch
    }
    func deactivate() {
        lock.lock(); defer { lock.unlock() }; handler = nil; commands = []; registration = UUID()
    }
}
