import Foundation
import CryptoKit
import Darwin

actor ManagedDownloadFiles {
    static var defaultRoot: URL { SQLiteLibraryStore.defaultURL.deletingLastPathComponent().appendingPathComponent("Downloads", isDirectory: true) }
    nonisolated let root: URL
    private var rootFD: Int32 = -1
    private var lockFD: Int32 = -1
    static let extensions: Set<String> = ["m4a", "mp4", "opus", "ogg", "webm", "flac", "wav", "mp3", "aac", "ts"]
    init(root: URL = ManagedDownloadFiles.defaultRoot) { self.root = root.standardizedFileURL }
    deinit {
        if lockFD >= 0 { Darwin.close(lockFD) }
        if rootFD >= 0 { Darwin.close(rootFD) }
    }
    func claim() throws { _ = try openRoot() }
    func close() {
        if lockFD >= 0 { Darwin.close(lockFD); lockFD = -1 }
        if rootFD >= 0 { Darwin.close(rootFD); rootFD = -1 }
    }

    static func validRelativePath(_ path: String, attempt: UUID, videoID: String) -> Bool {
        guard (try? YouTubeVideoID.validate(videoID)) == videoID else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "media" else { return false }
        let name = String(parts[1]), suffix = (name as NSString).pathExtension
        return extensions.contains(suffix) && name == "\(videoID)-\(attempt.uuidString).\(suffix)"
    }
    private func openRoot() throws -> Int32 {
        if rootFD < 0 {
            try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
            if mkdir(root.path, 0o700) != 0 && errno != EEXIST { throw DownloadError.unsafePath }
            let fd = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw DownloadError.unsafePath }
            let owner = openat(fd, ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard owner >= 0 else { Darwin.close(fd); throw DownloadError.unsafePath }
            guard flock(owner, LOCK_EX | LOCK_NB) == 0 else {
                Darwin.close(owner); Darwin.close(fd); throw DownloadError.conflict
            }
            guard fchmod(fd, 0o700) == 0 else {
                Darwin.close(owner); Darwin.close(fd); throw DownloadError.unsafePath
            }
            lockFD = owner; rootFD = fd
        }
        var owned = stat(), current = stat()
        guard fstat(rootFD, &owned) == 0, lstat(root.path, &current) == 0,
              owned.st_ino == current.st_ino, owned.st_dev == current.st_dev,
              current.st_mode & S_IFMT == S_IFDIR else { throw DownloadError.unsafePath }
        return rootFD
    }
    private func directory(_ name: String, under parent: Int32) throws -> Int32 {
        if mkdirat(parent, name, 0o700) != 0 && errno != EEXIST { throw DownloadError.unsafePath }
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw DownloadError.unsafePath }
        return fd
    }
    func stage(_ attempt: UUID) throws -> URL {
        let base = try directory("staging", under: openRoot()); defer { Darwin.close(base) }
        let fd = try directory(attempt.uuidString, under: base); defer { Darwin.close(fd) }
        return root.appendingPathComponent("staging").appendingPathComponent(attempt.uuidString)
    }
    func candidate(_ attempt: UUID) throws -> URL {
        let stage = try stage(attempt)
        let files = try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            .filter { $0.lastPathComponent.hasPrefix("audio.") && !$0.lastPathComponent.contains(".part") && !$0.lastPathComponent.contains(".ytdl") }
        guard files.count == 1, let file = files.first else { throw DownloadError.invalidAudio }
        let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true else { throw DownloadError.unsafePath }
        return file
    }
    func relativePath(for record: DownloadRecord, extension suffix: String) throws -> String {
        guard Self.extensions.contains(suffix) else { throw DownloadError.tools }
        return "media/\(try YouTubeVideoID.validate(record.id))-\(record.attempt.uuidString).\(suffix)"
    }
    func inspectStage(_ attempt: UUID, name: String, limit: Int64) throws -> (Int64, String) {
        guard name.hasPrefix("audio."), !name.contains("/"), name != ".", name != ".." else { throw DownloadError.unsafePath }
        _ = try stage(attempt)
        let base = try directory("staging", under: openRoot()); defer { Darwin.close(base) }
        let job = try directory(attempt.uuidString, under: base); defer { Darwin.close(job) }
        let fd = openat(job, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw DownloadError.invalidAudio }
        return try fingerprint(fd, limit: limit)
    }
    private func fingerprint(_ fd: Int32, limit: Int64) throws -> (Int64, String) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFREG, value.st_size > 0, value.st_size <= limit else { throw DownloadError.invalidAudio }
        var hash = SHA256(), count: Int64 = 0
        while let bytes = try handle.read(upToCount: 128 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            count += Int64(bytes.count)
            guard count <= limit else { throw DownloadError.storageLimit }
            hash.update(data: bytes)
        }
        guard count == value.st_size else { throw DownloadError.invalidAudio }
        return (count, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    func publish(_ record: DownloadRecord, name: String) throws {
        guard let path = record.relativePath, Self.validRelativePath(path, attempt: record.attempt, videoID: try YouTubeVideoID.validate(record.id)) else { throw DownloadError.unsafePath }
        let base = try directory("staging", under: openRoot()); defer { Darwin.close(base) }
        let job = try directory(record.attempt.uuidString, under: base); defer { Darwin.close(job) }
        let media = try directory("media", under: openRoot()); defer { Darwin.close(media) }
        guard !name.contains("/"), name.hasPrefix("audio.") else { throw DownloadError.unsafePath }
        let fd = openat(job, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw DownloadError.invalidAudio }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size == record.fileSize,
              fchmod(fd, 0o600) == 0, fsync(fd) == 0 else { throw DownloadError.invalidAudio }
        // Exclusive publication: an existing managed file is never overwritten.
        guard linkat(job, name, media, (path as NSString).lastPathComponent, 0) == 0 else { throw DownloadError.unsafePath }
        _ = fsync(media)
    }
    func localFile(_ record: DownloadRecord, limit: Int64) throws -> URL {
        guard record.status == .complete, let path = record.relativePath,
              Self.validRelativePath(path, attempt: record.attempt, videoID: try YouTubeVideoID.validate(record.id)),
              let checksum = record.checksum else { throw DownloadError.missing }
        let media = try directory("media", under: openRoot()); defer { Darwin.close(media) }
        let fd = openat(media, (path as NSString).lastPathComponent, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw DownloadError.missing }
        let (size, digest) = try fingerprint(fd, limit: limit)
        guard size == record.fileSize, digest == checksum else { throw DownloadError.missing }
        return root.appendingPathComponent(path)
    }
    func deleteMedia(_ record: DownloadRecord) throws {
        guard let path = record.relativePath else { return }
        guard Self.validRelativePath(path, attempt: record.attempt, videoID: try YouTubeVideoID.validate(record.id)) else { throw DownloadError.unsafePath }
        let media = try directory("media", under: openRoot()); defer { Darwin.close(media) }
        // unlinkat removes a replaced symlink itself, never its target.
        if unlinkat(media, (path as NSString).lastPathComponent, 0) != 0 && errno != ENOENT { throw DownloadError.unsafePath }
        _ = fsync(media)
    }
    func cleanStage(_ attempt: UUID) throws {
        let base = try directory("staging", under: openRoot()); defer { Darwin.close(base) }
        try removeDirectory(attempt.uuidString, parent: base, url: root.appendingPathComponent("staging/\(attempt.uuidString)"))
    }
    private func removeDirectory(_ name: String, parent: Int32, url: URL) throws {
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return }
            // Never traverse a substituted symlink.
            throw DownloadError.unsafePath
        }
        defer { Darwin.close(fd) }
        for child in try FileManager.default.contentsOfDirectory(atPath: url.path) {
            var value = stat()
            guard fstatat(fd, child, &value, AT_SYMLINK_NOFOLLOW) == 0 else { throw DownloadError.unsafePath }
            if value.st_mode & S_IFMT == S_IFDIR { try removeDirectory(child, parent: fd, url: url.appendingPathComponent(child)) }
            else if unlinkat(fd, child, 0) != 0 { throw DownloadError.unsafePath }
        }
        if unlinkat(parent, name, AT_REMOVEDIR) != 0 { throw DownloadError.unsafePath }
    }
    func usage() throws -> Int64 {
        _ = try openRoot()
        return try Self.byteCount(root)
    }
    nonisolated static func byteCount(_ directory: URL) throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: []) else { return 0 }
        var sum: Int64 = 0, count = 0
        for case let url as URL in enumerator {
            count += 1; guard count < 20_000 else { throw DownloadError.storageLimit }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw DownloadError.unsafePath }
            if values.isRegularFile == true { sum += Int64(values.fileSize ?? 0) }
        }
        return sum
    }
    nonisolated static func checkSpace(stage: URL, limits: DownloadLimits, existingBytes: Int64) throws {
        let bytes = try byteCount(stage)
        guard bytes <= limits.perFile, bytes + existingBytes <= limits.total else { throw DownloadError.storageLimit }
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: stage.path)
        guard let free = attributes[.systemFreeSize] as? NSNumber, free.int64Value >= limits.freeReserve else { throw DownloadError.noSpace }
    }
}
