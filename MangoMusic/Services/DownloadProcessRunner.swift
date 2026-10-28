import Foundation
import Darwin

protocol DownloadProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], directory: URL, timeout: TimeInterval,
             progress: @escaping @Sendable (DownloadProgress) -> Void,
             check: @escaping @Sendable () throws -> Void) async throws
}
struct DownloadProcessRunner: DownloadProcessRunning {
    func run(executable: URL, arguments: [String], directory: URL, timeout: TimeInterval,
             progress: @escaping @Sendable (DownloadProgress) -> Void,
             check: @escaping @Sendable () throws -> Void) async throws {
        let execution = DownloadExecution()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await Task.detached {
                try execution.run(executable: executable, arguments: arguments, directory: directory,
                                  timeout: timeout, progress: progress, check: check)
            }.value
            try Task.checkCancellation()
        } onCancel: { execution.cancel() }
    }
}
private final class DownloadOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var line = Data(), diagnostic = Data()
    let progress: @Sendable (DownloadProgress) -> Void
    init(progress: @escaping @Sendable (DownloadProgress) -> Void) { self.progress = progress }
    func consume(_ bytes: Data, stdout: Bool) {
        lock.lock(); defer { lock.unlock() }
        if !stdout {
            diagnostic.append(bytes)
            if diagnostic.count > 65_536 { diagnostic.removeFirst(diagnostic.count - 65_536) }
            return
        }
        line.append(bytes)
        while let end = line.firstIndex(of: 10) {
            let data = Data(line[..<end]); line.removeSubrange(...end)
            let prefix = Data("MANGO_PROGRESS:".utf8)
            guard data.starts(with: prefix), let json = try? JSONSerialization.jsonObject(with: data.dropFirst(prefix.count)) as? [String: Any],
                  let downloaded = json["downloaded_bytes"] as? NSNumber, downloaded.int64Value >= 0 else { continue }
            let total = (json["total_bytes"] as? NSNumber ?? json["total_bytes_estimate"] as? NSNumber)?.int64Value
            progress(DownloadProgress(bytes: downloaded.int64Value, total: total))
        }
        if line.count > 65_536 { line.removeAll() }
    }
}
/// posix_spawn gives every attempt its own process group, including yt-dlp/FFmpeg descendants.
private final class DownloadExecution: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let child = pid; lock.unlock()
        if child > 0 { kill(-child, SIGTERM) }
    }
    private func isCancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func run(executable: URL, arguments: [String], directory: URL, timeout: TimeInterval,
             progress: @escaping @Sendable (DownloadProgress) -> Void, check: @escaping @Sendable () throws -> Void) throws {
        try check()
        let output = Pipe(), error = Pipe()
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, 1)
        posix_spawn_file_actions_adddup2(&actions, error.fileHandleForWriting.fileDescriptor, 2)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        let environment = ["PATH=\(ToolLocator.runtimePath(for: executable))", "HOME=\(FileManager.default.homeDirectoryForCurrentUser.path)",
                           "LANG=en_US.UTF-8", "PYTHONIOENCODING=utf-8", "PYTHONNOUSERSITE=1"]
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var child: pid_t = 0
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        let result = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(&child, executable.path, &actions, &attributes,
                            UnsafeMutablePointer(mutating: args.baseAddress!), UnsafeMutablePointer(mutating: env.baseAddress!))
            }
        }
        if result == 0 { pid = child }
        lock.unlock()
        try? output.fileHandleForWriting.close(); try? error.fileHandleForWriting.close()
        guard result == 0 else { throw DownloadError.unavailable }
        let collector = DownloadOutput(progress: progress), readers = DispatchGroup()
        for (handle, stdout) in [(output.fileHandleForReading, true), (error.fileHandleForReading, false)] {
            readers.enter()
            DispatchQueue.global().async {
                defer { try? handle.close(); readers.leave() }
                while let bytes = try? handle.read(upToCount: 4096), !bytes.isEmpty { collector.consume(bytes, stdout: stdout) }
            }
        }
        var reaped = false, status: Int32 = 0
        defer {
            // Scoped to the group created above. Reap the parent and close pipes before returning.
            kill(-child, SIGKILL)
            if !reaped { _ = waitpid(child, &status, 0) }
            lock.lock(); pid = 0; lock.unlock()
            readers.wait()
        }
        let deadline = Date().addingTimeInterval(timeout)
        var failure: (any Error)?, terminateAt: Date?, nextCheck = Date.distantPast
        while true {
            if isCancelled(), failure == nil { failure = CancellationError() }
            if Date() > deadline, failure == nil { failure = DownloadError.timeout }
            if Date() >= nextCheck, failure == nil {
                do { try check() } catch { failure = error }
                nextCheck = Date().addingTimeInterval(0.5)
            }
            if failure != nil {
                if let terminateAt { if Date().timeIntervalSince(terminateAt) >= 1 { kill(-child, SIGKILL) } }
                else { kill(-child, SIGTERM); terminateAt = Date() }
            }
            let waited = waitpid(child, &status, WNOHANG)
            if waited == child { reaped = true; break }
            if waited == -1, errno != EINTR { throw DownloadError.unavailable }
            usleep(30_000)
        }
        if let failure { throw failure }
        guard status == 0 else { throw DownloadError.unavailable }
    }
}
