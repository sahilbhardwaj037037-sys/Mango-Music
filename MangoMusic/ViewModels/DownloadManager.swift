import Foundation
import Observation

@MainActor @Observable
final class DownloadManager {
    private(set) var records: [DownloadRecord] = []
    private(set) var progress: [String: DownloadProgress] = [:]
    private(set) var isRestoring = true
    private(set) var isClosing = false
    private(set) var offline = false
    private(set) var hasUnsavedChanges = false
    private(set) var persistenceError: String?
    private(set) var busyIDs = Set<String>()
    @ObservationIgnored private let store: any DownloadPersisting
    @ObservationIgnored let files: ManagedDownloadFiles
    @ObservationIgnored let policy: PlaybackNetworkPolicy
    @ObservationIgnored private let service: any AudioDownloading
    @ObservationIgnored private let validator: any AudioFileValidating
    @ObservationIgnored let limits: DownloadLimits
    @ObservationIgnored private(set) var restorationTask: Task<Void, Never>?
    @ObservationIgnored private(set) var workerTask: Task<Void, Never>?
    @ObservationIgnored private var writerTask: Task<Void, Never>?
    private var activeID: String?
    private var revision = 0
    private var edits = 0
    private var loaded = false
    var canEdit: Bool { loaded && !isRestoring && !isClosing }
    var bytesUsed: Int64 { records.filter { $0.status == .complete }.reduce(0) { $0 + $1.fileSize } }
    var completed: [DownloadRecord] { records.filter { $0.status == .complete } }

    init(store: any DownloadPersisting, files: ManagedDownloadFiles = ManagedDownloadFiles(),
         policy: PlaybackNetworkPolicy = PlaybackNetworkPolicy(), service: any AudioDownloading = YTAudioDownloadService(),
         validator: any AudioFileValidating = MPVAudioFileValidator(), limits: DownloadLimits = DownloadLimits()) {
        self.store = store; self.files = files; self.policy = policy
        self.service = service; self.validator = validator; self.limits = limits
        self.offline = policy.offlineOnly
        restore()
    }
    func record(for song: Song) -> DownloadRecord? { records.first { $0.id == song.id } }
    func enqueue(_ song: Song) {
        guard canEdit, !policy.offlineOnly, records.count < 10_000,
              record(for: song) == nil, let raw = try? YouTubeVideoID.validate(song.id),
              let source = URL(string: "https://www.youtube.com/watch?v=\(raw)") else { return }
        records.append(DownloadRecord(song: song, sourceURL: source))
        save(); startWorker()
    }
    func cancel(_ id: String) {
        guard canEdit, let index = records.firstIndex(where: { $0.id == id && $0.status.active }) else { return }
        records[index].status = .cancelled; progress[id] = nil
        if activeID == id { workerTask?.cancel() }
        save()
    }
    func retry(_ id: String) async {
        guard canEdit, !policy.offlineOnly, !busyIDs.contains(id),
              let old = records.first(where: { $0.id == id && !$0.status.active && $0.status != .complete && $0.status != .deleting }) else { return }
        busyIDs.insert(id); defer { busyIDs.remove(id); startWorker() }
        if activeID == id { await workerTask?.value }
        do {
            try await files.deleteMedia(old); try await files.cleanStage(old.attempt)
            guard canEdit, !policy.offlineOnly else { return }
            replace(DownloadRecord(song: old.song, sourceURL: old.sourceURL)); save()
        } catch { persistenceError = (error as? LocalizedError)?.errorDescription ?? DownloadError.unsafePath.localizedDescription }
    }
    func delete(_ ids: Set<String>) async {
        guard canEdit, busyIDs.isDisjoint(with: ids) else { return }
        busyIDs.formUnion(ids); defer { busyIDs.subtract(ids); startWorker() }
        for id in ids { cancel(id) }
        if let activeID, ids.contains(activeID) { await workerTask?.value }
        for id in ids {
            guard var record = records.first(where: { $0.id == id }) else { continue }
            record.status = .deleting; replace(record); save()
            guard await flush() else { return }
            do {
                try await files.deleteMedia(record); try await files.cleanStage(record.attempt)
                records.removeAll { $0.id == id }; progress[id] = nil; save()
            } catch {
                record.error = DownloadError.unsafePath.localizedDescription; replace(record); save()
            }
        }
        _ = await flush()
    }
    func setOffline(_ value: Bool) {
        offline = value
        policy.setOffline(value)
        if value { for record in records where record.status.active { cancel(record.id) } }
    }
    func localFile(for song: Song) async throws -> URL? {
        await restorationTask?.value
        guard loaded, !isClosing else { throw DownloadError.unavailable }
        guard let record = record(for: song), record.status == .complete, !busyIDs.contains(song.id) else { return nil }
        do { return try await files.localFile(record, limit: limits.perFile) }
        catch is CancellationError { throw CancellationError() }
        catch {
            // Do not apply a stale lookup to a newer download attempt.
            if let index = records.firstIndex(where: { $0.id == song.id && $0.attempt == record.attempt && $0.status == .complete }) {
                records[index].status = .missing; records[index].error = DownloadError.missing.localizedDescription; save()
            }
            return nil
        }
    }
    private func replace(_ record: DownloadRecord) {
        if let i = records.firstIndex(where: { $0.id == record.id }) { records[i] = record }
    }
    private func startWorker() {
        guard canEdit, !policy.offlineOnly, persistenceError == nil, workerTask == nil,
              records.contains(where: { $0.status == .queued && !busyIDs.contains($0.id) }) else { return }
        workerTask = Task { [weak self] in
            while let self, self.canEdit, !self.policy.offlineOnly, self.persistenceError == nil, !Task.isCancelled,
                  let record = self.records.first(where: { $0.status == .queued && !self.busyIDs.contains($0.id) }) {
                self.activeID = record.id
                await self.perform(record)
                self.activeID = nil
            }
            self?.workerTask = nil
            self?.startWorker()
        }
    }
    private func perform(_ original: DownloadRecord) async {
        var record = original
        var published = false
        do {
            record.status = .downloading; replace(record); save()
            guard await flush() else { throw PersistenceError.writeFailed }
            try Task.checkCancellation()
            guard !policy.offlineOnly else { throw DownloadError.offline }
            let existing = try await files.usage(), stage = try await files.stage(record.attempt)
            let id = record.id, attempt = record.attempt
            let file = try await service.download(source: record.sourceURL, stage: stage, existingBytes: existing, limits: limits) { [weak self] update in
                Task { @MainActor in
                    guard let self, self.records.contains(where: { $0.id == id && $0.attempt == attempt && $0.status == .downloading }) else { return }
                    self.progress[id] = update
                }
            }
            try Task.checkCancellation()
            guard file.deletingLastPathComponent().standardizedFileURL == stage.standardizedFileURL else { throw DownloadError.unsafePath }
            record.status = .validating; replace(record); save()
            let (size, digest) = try await files.inspectStage(record.attempt, name: file.lastPathComponent, limit: limits.perFile)
            let audio = try await validator.validate(file)
            try Task.checkCancellation()
            record.relativePath = try await files.relativePath(for: record, extension: file.pathExtension)
            record.format = audio.format; record.fileSize = size; record.checksum = digest
            record.song = Song(id: record.id, title: record.song.title, artist: record.song.artist, duration: audio.duration)
            replace(record); save()
            // A persisted validating row names the publication, allowing restart cleanup after a crash.
            guard await flush() else { throw PersistenceError.writeFailed }
            try Task.checkCancellation()
            try await files.publish(record, name: file.lastPathComponent)
            published = true
            try Task.checkCancellation()
            guard !policy.offlineOnly else { throw DownloadError.offline }
            record.status = .complete; record.downloadedAt = .now; record.error = nil
            replace(record); progress[record.id] = nil; save()
            guard await flush() else { throw PersistenceError.writeFailed }
            try await files.cleanStage(record.attempt)
        } catch {
            let cancelled = error is CancellationError || Task.isCancelled || policy.offlineOnly
            // Cleanup must run even if the download task itself is cancelled.
            do {
                if published { try await files.deleteMedia(record) }
                else { record.relativePath = nil }
                try await files.cleanStage(record.attempt)
            } catch { record.error = DownloadError.unsafePath.localizedDescription }
            record.status = cancelled ? .cancelled : .failed
            if !cancelled { record.error = record.error ?? (error as? LocalizedError)?.errorDescription ?? DownloadError.unavailable.localizedDescription }
            replace(record); progress[record.id] = nil; save()
            _ = await flush()
        }
    }
    private func restore() {
        guard restorationTask == nil else { return }
        isRestoring = true
        restorationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isRestoring = false; self.restorationTask = nil }
            do {
                // Claim before reading so the snapshot cannot precede another owner's final save.
                try await self.files.claim()
                let snapshot = try await self.store.loadDownloads()
                self.records = snapshot.records; self.revision = snapshot.revision; self.loaded = true
                var changed = false
                for original in snapshot.records {
                    var record = original
                    if record.status == .complete {
                        do { _ = try await self.files.localFile(record, limit: self.limits.perFile) }
                        catch { record.status = .missing; record.error = DownloadError.missing.localizedDescription }
                    } else {
                        do {
                            try await self.files.deleteMedia(record); try await self.files.cleanStage(record.attempt)
                            if record.status == .deleting { self.records.removeAll { $0.id == record.id }; changed = true; continue }
                            if record.status.active { record.status = .interrupted }
                        } catch { record.status = .failed; record.error = DownloadError.unsafePath.localizedDescription }
                    }
                    if record != original { self.replace(record); changed = true }
                }
                if changed { self.save(); _ = await self.flush() }
            } catch { self.persistenceError = (error as? LocalizedError)?.errorDescription ?? PersistenceError.unavailable.localizedDescription }
        }
    }
    private func save() {
        guard loaded else { return }
        edits += 1; hasUnsavedChanges = true
        if writerTask == nil { startWriter() }
    }
    private func startWriter() {
        writerTask = Task { [weak self] in
            while let self, self.hasUnsavedChanges {
                let edit = self.edits, snapshot = self.records
                do {
                    self.revision = try await self.store.saveDownloads(snapshot, expecting: self.revision)
                    if self.edits == edit { self.hasUnsavedChanges = false }
                    self.persistenceError = nil
                } catch {
                    self.persistenceError = (error as? LocalizedError)?.errorDescription ?? PersistenceError.writeFailed.localizedDescription
                    self.writerTask = nil; return
                }
            }
            self?.writerTask = nil
        }
    }
    func flush() async -> Bool {
        if hasUnsavedChanges, writerTask == nil { startWriter() }
        await writerTask?.value
        return !hasUnsavedChanges
    }
    func retryPersistence() {
        if !loaded { restore() }
        else { Task { _ = await flush(); startWorker() } }
    }
    func prepareToQuit() async -> Bool {
        await restorationTask?.value
        for record in records where record.status.active { cancel(record.id) }
        isClosing = true
        workerTask?.cancel(); await workerTask?.value
        if !loaded { return true }
        guard await flush() else { isClosing = false; return false }
        await files.close()
        return true
    }
    func cancelQuit() { isClosing = false }
    func shutdown() { isClosing = true; workerTask?.cancel() }
}

struct LocalFirstAudioResolver: AudioStreamResolving {
    let downloads: DownloadManager?
    let streaming: any AudioStreamResolving
    let policy: PlaybackNetworkPolicy
    func resolve(_ song: Song) async throws -> URL {
        try Task.checkCancellation()
        if let downloads, let local = try await downloads.localFile(for: song) { return local }
        try Task.checkCancellation()
        guard !policy.offlineOnly else { throw DownloadError.offline }
        return try await streaming.resolve(song)
    }
}
