import Foundation
import Darwin

struct ProcessOutput: Sendable {
    let stdout: Data
    let stderr: Data
    let status: Int32
}

protocol ProcessRunning: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> ProcessOutput
}

struct FoundationProcessRunner: ProcessRunning {
    var timeout: TimeInterval = 45
    var outputLimit = 4 * 1024 * 1024

    func run(executable: URL, arguments: [String]) async throws -> ProcessOutput {
        let execution = ProcessExecution()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let output = try await Task.detached(priority: .userInitiated) {
                try execution.execute(executable: executable, arguments: arguments,
                                      timeout: timeout, outputLimit: outputLimit)
            }.value
            try Task.checkCancellation()
            return output
        } onCancel: {
            execution.stop(cancelled: true)
        }
    }
}

/// Foundation Process runs and drains both pipes off the main actor. All mutable
/// process lifecycle state is protected by this lock, including start/cancel races.
private final class ProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    func stop(cancelled: Bool) {
        lock.lock()
        if cancelled { self.cancelled = true } else { timedOut = true }
        let running = process
        if let running, running.isRunning { running.terminate() }
        lock.unlock()
        // A stuck child must not keep a cancelled task or its pipes alive indefinitely.
        if let running {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                self.lock.lock()
                if running.isRunning { kill(running.processIdentifier, SIGKILL) }
                self.lock.unlock()
            }
        }
    }

    func execute(executable: URL, arguments: [String], timeout: TimeInterval,
                 outputLimit: Int) throws -> ProcessOutput {
        let child = Process()
        let stdout = Pipe(), stderr = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = stdout
        child.standardError = stderr
        child.currentDirectoryURL = FileManager.default.temporaryDirectory
        // Do not inherit shell customizations, Python injection variables or credentials.
        child.environment = ["PATH": ToolLocator.runtimePath(for: executable),
                             "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                             "LANG": "en_US.UTF-8", "PYTHONIOENCODING": "utf-8",
                             "PYTHONNOUSERSITE": "1"]
        lock.lock()
        guard !cancelled else { lock.unlock(); throw CancellationError() }
        process = child
        do { try child.run() }
        catch { process = nil; lock.unlock(); throw SearchError.launchFailed }
        lock.unlock()
        let deadline = DispatchWorkItem { self.stop(cancelled: false) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let out = PipeBuffer(limit: outputLimit)
        let err = PipeBuffer(limit: 64 * 1024)
        let readers = DispatchGroup()
        for (pipe, buffer) in [(stdout, out), (stderr, err)] {
            readers.enter()
            DispatchQueue.global().async {
                defer { readers.leave() }
                buffer.drain(pipe.fileHandleForReading)
            }
        }
        child.waitUntilExit()
        readers.wait()
        deadline.cancel()
        lock.lock()
        let wasCancelled = cancelled, didTimeOut = timedOut
        process = nil
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        if didTimeOut { throw SearchError.timedOut }
        if out.overflowed || err.overflowed { throw SearchError.outputTooLarge }
        if out.readFailed || err.readFailed { throw SearchError.malformedOutput }
        return ProcessOutput(stdout: out.data, stderr: err.data, status: child.terminationStatus)
    }
}

/// Each buffer has one writer; its values are read only after the dispatch group joins.
private final class PipeBuffer: @unchecked Sendable {
    let limit: Int
    private(set) var data = Data()
    private(set) var overflowed = false
    private(set) var readFailed = false
    init(limit: Int) { self.limit = limit }
    func drain(_ handle: FileHandle) {
        defer { try? handle.close() }
        do {
            while let chunk = try handle.read(upToCount: 16 * 1024), !chunk.isEmpty {
                let available = max(0, limit - data.count)
                data.append(chunk.prefix(available))
                if chunk.count > available { overflowed = true }
            }
        } catch { readFailed = true }
    }
}
