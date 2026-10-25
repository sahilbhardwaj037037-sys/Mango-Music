import Foundation
import Darwin

/// Only decoded, non-sensitive fields cross into the UI. Raw IPC and signed URLs are never logged.
struct MPVMessage: Sendable {
    var event: String?
    var name: String?
    var number: Double?
    var flag: Bool?
    var reason: String?
    var entry: Int?
    var request: Int?
    var success = true

    static func decode(_ data: Data) throws -> Self {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["event"] is String || object["request_id"] is Int else { throw PlaybackError.protocolError }
        if object["request_id"] != nil, !(object["error"] is String) { throw PlaybackError.protocolError }
        let value = object["data"] as? NSNumber
        return Self(event: object["event"] as? String, name: object["name"] as? String,
                    number: value?.doubleValue, flag: value?.boolValue, reason: object["reason"] as? String,
                    entry: object["playlist_entry_id"] as? Int, request: object["request_id"] as? Int,
                    success: (object["error"] as? String ?? "success") == "success")
    }
}

/// Synchronous termination is also used by applicationWillTerminate, where no async work is guaranteed.
final class OwnedMPVProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var directory: URL?
    private var closed = false
    func launch(_ child: Process, directory: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { try? FileManager.default.removeItem(at: directory); throw CancellationError() }
        self.directory = directory
        try child.run()
        process = child
    }
    func shutdown(permanent: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        if permanent { closed = true }
        if let process, process.isRunning {
            process.terminate()
            // SIGKILL is scoped to our owned, unreaped child only. Never kill by name.
            for _ in 0..<20 {
                if !process.isRunning { break }
                usleep(10_000)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
    deinit { shutdown() }
}

actor MPVConnection {
    nonisolated let owner = OwnedMPVProcess()
    private var handle: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var buffer = Data()
    private var counter = 0
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
    private var generation = UUID()
    private var lifecycle = UUID()
    private var sink: (@Sendable (UUID, MPVMessage) -> Void)?
    private var failure: (@Sendable (UUID, PlaybackError) -> Void)?
    private let executable: URL?
    private let audioOutput: String?

    init(executable: URL? = nil, audioOutput: String? = nil) { self.executable = executable; self.audioOutput = audioOutput }

    func start(sink: @escaping @Sendable (UUID, MPVMessage) -> Void,
               failure: @escaping @Sendable (UUID, PlaybackError) -> Void) async throws {
        if handle != nil { return }
        self.sink = sink; self.failure = failure
        let tool = try ToolLocator.locate("mpv", override: executable)
        let epoch = UUID(); lifecycle = epoch
        // Short path stays within sockaddr_un.sun_path; mkdir is atomic and mode 0700.
        var template = Array("/tmp/mango-mpv-XXXXXX".utf8CString)
        let directoryPath = template.withUnsafeMutableBufferPointer { storage -> String? in
            guard let path = mkdtemp(storage.baseAddress!) else { return nil }
            return String(cString: path)
        }
        guard let directoryPath else { throw PlaybackError.connection }
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let socketPath = directory.appendingPathComponent("ipc").path
        let child = Process()
        child.executableURL = tool
        child.arguments = ["--no-config", "--load-scripts=no", "--ytdl=no", "--idle=yes", "--vid=no",
                           "--audio-display=no", "--force-window=no", "--no-terminal",
                           "--cache-on-disk=no", "--save-position-on-quit=no", "--input-default-bindings=no",
                           "--network-timeout=20", "--input-ipc-server=\(socketPath)"]
        if let audioOutput { child.arguments?.append("--ao=\(audioOutput)") }
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path]
        child.terminationHandler = { [weak self] _ in Task { await self?.disconnected(epoch) } }
        do {
            try owner.launch(child, directory: directory)
            for _ in 0..<100 {
                try Task.checkCancellation()
                guard lifecycle == epoch else { throw CancellationError() }
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else { throw PlaybackError.connection }
                var address = sockaddr_un()
                address.sun_family = sa_family_t(AF_UNIX)
                address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
                withUnsafeMutableBytes(of: &address.sun_path) { target in
                    target.copyBytes(from: Array(socketPath.utf8) + [0])
                }
                let connected = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                if connected == 0 {
                    var noSignal: Int32 = 1
                    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                    var timeout = timeval(tv_sec: 1, tv_usec: 0)
                    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                    handle = file
                    let (chunks, continuation) = AsyncStream<Data>.makeStream()
                    readerTask = Task { [weak self] in
                        for await chunk in chunks { await self?.receive(chunk, epoch: epoch) }
                    }
                    file.readabilityHandler = { file in
                        var storage = [UInt8](repeating: 0, count: 64 * 1024)
                        let count = Darwin.recv(file.fileDescriptor, &storage, storage.count, 0)
                        if count < 0 && errno == EINTR { return }
                        let data = count > 0 ? Data(storage.prefix(count)) : Data()
                        continuation.yield(data)
                        if data.isEmpty { continuation.finish() }
                    }
                    for (index, property) in ["time-pos", "duration", "pause", "paused-for-cache", "volume"].enumerated() {
                        try await command(["observe_property", index + 1, property])
                    }
                    return
                }
                Darwin.close(fd)
                try await Task.sleep(for: .milliseconds(30))
            }
            throw PlaybackError.connection
        } catch {
            shutdown()
            throw error
        }
    }

    func setGeneration(_ id: UUID) { generation = id }

    func command(_ arguments: [any Sendable]) async throws {
        guard let handle else { throw PlaybackError.connection }
        counter += 1
        let id = counter, epoch = lifecycle
        let data = try JSONSerialization.data(withJSONObject: ["command": arguments, "request_id": id]) + Data([10])
        try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try handle.write(contentsOf: data) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: PlaybackError.connection) }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                await self?.expire(id, epoch: epoch)
            }
        }
    }

    private func expire(_ id: Int, epoch: UUID) {
        guard lifecycle == epoch, pending[id] != nil else { return }
        fail(.timeout)
    }
    private func receive(_ data: Data, epoch: UUID) {
        guard lifecycle == epoch, handle != nil else { return }
        guard !data.isEmpty else { disconnected(epoch); return }
        buffer.append(data)
        guard buffer.count <= 1024 * 1024 else { fail(.protocolError); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            do {
                let message = try MPVMessage.decode(Data(line))
                if let id = message.request {
                    let continuation = pending.removeValue(forKey: id)
                    if message.success { continuation?.resume() }
                    else { continuation?.resume(throwing: PlaybackError.command) }
                } else { sink?(generation, message) }
            } catch { fail(.protocolError); return }
        }
    }
    private func disconnected(_ epoch: UUID) {
        guard lifecycle == epoch else { return }
        fail(.connection)
    }
    private func fail(_ error: PlaybackError) {
        let callback = failure, id = generation
        shutdown()
        callback?(id, error)
    }
    func shutdown() {
        lifecycle = UUID()
        readerTask?.cancel(); readerTask = nil
        handle?.readabilityHandler = nil
        try? handle?.close(); handle = nil
        buffer.removeAll()
        let continuations = pending.values; pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: PlaybackError.connection) }
        owner.shutdown()
    }
}
