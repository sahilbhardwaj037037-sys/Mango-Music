import Foundation
import MediaPlayer

/// Only macOS-supported MediaPlayer APIs. No AVAudioSession, global event tap, artwork or URLs.
@MainActor
final class NativeSystemMediaAdapter: SystemMediaAdapting {
    private let center = MPNowPlayingInfoCenter.default()
    private let commands = MPRemoteCommandCenter.shared()
    private let gate = MediaCommandGate()
    private var tokens: [(MPRemoteCommand, Any)] = []
    private(set) var isActive = false
    var registeredHandlerCount: Int { tokens.count }
    private var lastCommands: Set<MediaCommandKind>?
    private var lastGeneration: UUID?

    static func dictionary(_ metadata: NowPlayingMetadata) -> [String: Any] {
        var result: [String: Any] = [MPMediaItemPropertyTitle: metadata.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: metadata.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: metadata.rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue]
        if let artist = metadata.artist { result[MPMediaItemPropertyArtist] = artist }
        if let duration = metadata.duration { result[MPMediaItemPropertyPlaybackDuration] = duration }
        return result
    }
    private var supported: [(MediaCommandKind, MPRemoteCommand)] {
        [(.play, commands.playCommand), (.pause, commands.pauseCommand), (.toggle, commands.togglePlayPauseCommand),
         (.next, commands.nextTrackCommand), (.previous, commands.previousTrackCommand),
         (.seek, commands.changePlaybackPositionCommand), (.stop, commands.stopCommand)]
    }
    func activate(_ handler: @escaping @MainActor @Sendable (MediaCommand, UUID) -> Void) {
        guard !isActive else { return }; isActive = true
        gate.activate(handler)
        for command in [commands.seekForwardCommand, commands.seekBackwardCommand, commands.skipForwardCommand,
                        commands.skipBackwardCommand, commands.changePlaybackRateCommand, commands.changeRepeatModeCommand,
                        commands.changeShuffleModeCommand, commands.ratingCommand, commands.likeCommand,
                        commands.dislikeCommand, commands.bookmarkCommand, commands.enableLanguageOptionCommand,
                        commands.disableLanguageOptionCommand] { command.isEnabled = false }
        for (kind, command) in supported {
            command.isEnabled = false
            let gate = gate
            let token = command.addTarget { event in
                let action: MediaCommand
                switch kind {
                case .play: action = .play
                case .pause: action = .pause
                case .toggle: action = .toggle
                case .next: action = .next
                case .previous: action = .previous
                case .stop: action = .stop
                case .seek:
                    guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                    action = .seek(event.positionTime)
                }
                return gate.submit(action) ? .success : .noActionableNowPlayingItem
            }
            tokens.append((command, token))
        }
    }
    func setCommands(_ enabled: Set<MediaCommandKind>, generation: UUID) {
        guard isActive, lastCommands != enabled || lastGeneration != generation else { return }
        gate.update(enabled, generation: generation)
        if lastCommands != enabled {
            for (kind, command) in supported { command.isEnabled = enabled.contains(kind) }
        }
        lastCommands = enabled; lastGeneration = generation
    }
    func publish(_ metadata: NowPlayingMetadata?, state: SystemPlaybackState) {
        guard isActive else { return }
        center.nowPlayingInfo = metadata.map(Self.dictionary)
        // macOS requires this explicitly; audio is owned by a child process, not an iOS audio session.
        switch state { case .playing: center.playbackState = .playing
        case .paused: center.playbackState = .paused; case .stopped: center.playbackState = .stopped }
    }
    func deactivate() {
        guard isActive else { return }; isActive = false
        gate.deactivate()
        for (command, token) in tokens { command.removeTarget(token); command.isEnabled = false }
        tokens.removeAll(); lastCommands = nil; lastGeneration = nil
        center.nowPlayingInfo = nil; center.playbackState = .stopped
    }
}
