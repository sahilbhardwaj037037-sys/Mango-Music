import Foundation

protocol AudioFileValidating: Sendable {
    func validate(_ url: URL) async throws -> ValidatedAudio
}

/// Uses the same bundled decoder as playback; no Homebrew or ffprobe requirement.
struct MPVAudioFileValidator: AudioFileValidating {
    var executable: URL?
    func validate(_ url: URL) async throws -> ValidatedAudio {
        let connection = MPVConnection(executable: executable, audioOutput: "null", localFilesOnly: true)
        let state = AudioValidationState()
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await connection.start(sink: { _, message in Task { await state.receive(message) } },
                    failure: { _, _ in Task { await state.fail() } })
                try await connection.command(["observe_property", 91, "track-list"])
                try await connection.command(["observe_property", 92, "file-format"])
                try await connection.command(["set_property", "volume", 0])
                try await connection.command(["loadfile", url.absoluteString, "replace"])
                let deadline = Date().addingTimeInterval(10)
                while Date() < deadline {
                    try Task.checkCancellation()
                    if let result = try await state.result() { await connection.shutdown(); return result }
                    try await Task.sleep(for: .milliseconds(30))
                }
                throw DownloadError.invalidAudio
            } catch {
                await connection.shutdown()
                throw error
            }
        } onCancel: {
            connection.owner.shutdown()
            Task { await connection.shutdown() }
        }
    }
}
private actor AudioValidationState {
    var failed = false, loaded = false
    var audio = 0, video = 0
    var position = 0.0, duration = 0.0
    var format: String?
    func fail() { failed = true }
    func receive(_ message: MPVMessage) {
        if message.event == "file-loaded" { loaded = true }
        if message.event == "end-file", message.reason == "error" { failed = true }
        if message.name == "track-list" { audio = message.audioTracks ?? 0; video = message.videoTracks ?? 0 }
        if message.name == "time-pos" { position = message.number ?? position }
        if message.name == "duration" { duration = message.number ?? duration }
        if message.name == "file-format" { format = message.textValue }
    }
    func result() throws -> ValidatedAudio? {
        if failed || video > 0 { throw DownloadError.invalidAudio }
        if let format, ["hls", "dash", "concat", "m3u8"].contains(where: { format.lowercased().contains($0) }) { throw DownloadError.invalidAudio }
        if loaded, audio > 0, position > 0, duration.isFinite, duration > 0, duration <= 21_600, let format {
            return ValidatedAudio(duration: duration, format: format)
        }
        return nil
    }
}
