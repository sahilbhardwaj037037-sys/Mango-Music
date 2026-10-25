import SwiftUI

struct PlaybackBar: View {
    @Bindable var library: MusicLibrary

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(library.currentSong?.title ?? "Nothing playing")
                        .font(.callout.weight(.semibold)).lineLimit(1)
                    Text(library.currentSong?.artist ?? "Choose a song to get started")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 18) {
                    Button(action: library.previous) { Image(systemName: "backward.end.fill") }
                        .disabled(!library.playbackCapabilities.contains(.previous)).help("Previous")
                        .accessibilityLabel("Previous song")
                    Button(action: library.togglePlayback) {
                        Image(systemName: library.playPauseShowsPause ? "pause.fill" : "play.fill")
                            .font(.title2).frame(width: 28, height: 28)
                    }
                    .disabled(!library.playbackCapabilities.contains(.toggle))
                    .help("Play/Pause (Space)").accessibilityLabel(library.isLoading ? "Cancel loading" : library.playPauseShowsPause ? "Pause" : "Play")
                    Button(action: library.stop) { Image(systemName: "stop.fill") }
                        .disabled(!library.playbackCapabilities.contains(.stop)).help("Stop").accessibilityLabel("Stop")
                    Button(action: library.next) { Image(systemName: "forward.end.fill") }
                        .disabled(!library.playbackCapabilities.contains(.next)).help("Next")
                        .accessibilityLabel("Next song")
                }
                .buttonStyle(.plain)
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { library.volume }, set: { library.setVolume($0) }), in: 0...1).accessibilityLabel("Volume")
                    Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 136).padding(.leading, 16)
            }
            if let notice = library.playbackNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            if let error = library.playbackError {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry", action: library.retryPlayback)
                }
            }
            HStack(spacing: 10) {
                Text(library.progress.timestamp).frame(width: 32, alignment: .trailing)
                Slider(value: Binding(get: { min(library.progress, max(1, library.duration)) }, set: { library.seek(to: $0) }), in: 0...max(1, library.duration))
                    .disabled(!library.playbackCapabilities.contains(.seek))
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(library.progress.timestamp) of \(library.duration.timestamp)")
                Text(library.duration > 0 ? library.duration.timestamp : "—").frame(width: 32, alignment: .leading)
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.bar)
    }
}
