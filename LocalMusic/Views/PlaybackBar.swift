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
                        .disabled(library.currentSong == nil).help("Previous")
                        .accessibilityLabel("Previous song")
                    Button(action: library.togglePlayback) {
                        Image(systemName: library.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2).frame(width: 28, height: 28)
                    }
                    .disabled(library.currentSong == nil && library.queue.isEmpty)
                    .help("Play/Pause (Space)").accessibilityLabel(library.isPlaying ? "Pause" : "Play")
                    Button(action: library.next) { Image(systemName: "forward.end.fill") }
                        .disabled(library.queue.isEmpty).help("Next")
                        .accessibilityLabel("Next song")
                }
                .buttonStyle(.plain)
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $library.volume, in: 0...1).accessibilityLabel("Volume")
                    Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 136).padding(.leading, 16)
            }
            HStack(spacing: 10) {
                Text(library.progress.timestamp).frame(width: 32, alignment: .trailing)
                Slider(value: $library.progress, in: 0...max(1, library.currentSong?.duration ?? 1))
                    .disabled(library.currentSong == nil)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(library.progress.timestamp) of \((library.currentSong?.duration ?? 0).timestamp)")
                Text((library.currentSong?.duration ?? 0).timestamp).frame(width: 32, alignment: .leading)
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.bar)
    }
}
