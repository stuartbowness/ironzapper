import Foundation
import Darwin
#if SWIFT_PACKAGE
import IronZapperCore
#endif

// Privileged moves use directory descriptors and renameatx_np(RENAME_EXCL).
// No recursive deletion, shell commands, cross-volume copy, or symlink traversal.
enum SecureTrash {
    static func openDirectory(_ url: URL, trusted: Bool = false) throws -> Int32 {
        guard url.path.hasPrefix("/"), !url.pathComponents.contains("..") else { throw ZapperError.invalid("Invalid directory.") }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw error("Open root") }
        for part in url.pathComponents.dropFirst() {
            let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw error("Open directory without following links") }
            if trusted {
                var info = stat()
                guard fstat(next, &info) == 0, info.st_uid == 0, info.st_mode & 0o022 == 0 else {
                    close(next); throw ZapperError.invalid("A system path has writable or untrusted ancestors.")
                }
            }
            fd = next
        }
        return fd
    }
    static func preflight(_ candidate: Candidate, home: URL, uid: uid_t) throws {
        try RemovalEngine.validate(candidate)
        let source = try openDirectory(candidate.url.deletingLastPathComponent(), trusted: true)
        defer { close(source) }
        var info = stat()
        guard fstatat(source, candidate.url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o022 == 0 else {
            throw ZapperError.invalid("The system item is not a safely movable root-owned regular file.")
        }
        let homeFD = try openDirectory(home); defer { close(homeFD) }
        var homeInfo = stat()
        guard fstat(homeFD, &homeInfo) == 0, homeInfo.st_uid == uid, homeInfo.st_dev == info.st_dev else {
            throw ZapperError.invalid("The user's home must be on the same volume as the selected system file.")
        }
        let trash = openat(homeFD, ".Trash", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if trash < 0 {
            guard errno == ENOENT else { throw error("Read Trash before stopping services") }
        } else {
            defer { close(trash) }
            var trashInfo = stat()
            guard fstat(trash, &trashInfo) == 0, trashInfo.st_uid == uid, trashInfo.st_mode & 0o077 == 0 else {
                throw ZapperError.invalid("The user's Trash permissions are unsafe.")
            }
        }
    }
    static func move(_ candidate: Candidate, home: URL, uid: uid_t, gid: gid_t) throws -> String {
        try RemovalEngine.validate(candidate)
        let allowed = ["/Library/LaunchDaemons", "/Library/LaunchAgents", "/Library/PrivilegedHelperTools"]
        guard (allowed.contains(candidate.url.deletingLastPathComponent().path) || ReceiptInspector.dataRoots.contains(where: { isWithin(candidate.url, URL(fileURLWithPath: $0)) })), candidate.ownership == .exclusive else { throw ZapperError.invalid("Privileged path is outside the helper's allowed locations.") }
        let source = try openDirectory(candidate.url.deletingLastPathComponent(), trusted: true); defer { close(source) }
        var sourceStat = stat()
        guard fstat(source, &sourceStat) == 0, sourceStat.st_uid == 0, sourceStat.st_mode & 0o022 == 0 else {
            throw ZapperError.invalid("System directory permissions are unsafe.")
        }
        var itemStat = stat()
        guard fstatat(source, candidate.url.lastPathComponent, &itemStat, AT_SYMLINK_NOFOLLOW) == 0,
              itemStat.st_ino == candidate.identity.inode, itemStat.st_dev == candidate.identity.device,
              itemStat.st_uid == 0, itemStat.st_mode & S_IFMT == S_IFREG, itemStat.st_mode & 0o022 == 0 else {
            throw ZapperError.invalid("Only unchanged, root-owned regular files can be moved by the helper.")
        }
        let homeFD = try openDirectory(home); defer { close(homeFD) }
        var hs = stat()
        guard fstat(homeFD, &hs) == 0, hs.st_uid == uid else { throw ZapperError.invalid("The user's home ownership changed.") }
        let createdTrash = mkdirat(homeFD, ".Trash", 0o700) == 0
        if !createdTrash && errno != EEXIST { throw error("Create Trash") }
        let trash = openat(homeFD, ".Trash", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard trash >= 0 else { throw error("Open Trash") }; defer { close(trash) }
        var ts = stat()
        guard fstat(trash, &ts) == 0 else { throw error("Inspect Trash") }
        if createdTrash && ts.st_uid == 0 { guard fchown(trash, uid, gid) == 0 else { throw error("Set Trash owner") } }
        guard fstat(trash, &ts) == 0, ts.st_uid == uid, ts.st_mode & 0o077 == 0, ts.st_dev == itemStat.st_dev else {
            throw ZapperError.invalid("Trash must be private, owned by the signed-in user, and on the same volume.")
        }
        let folder = "IronZapper-" + UUID().uuidString
        guard mkdirat(trash, folder, 0o700) == 0 else { throw error("Create recovery folder") }
        let recovery = openat(trash, folder, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard recovery >= 0 else { throw error("Open recovery folder") }; defer { close(recovery) }
        // Write recovery instructions before moving. The directory remains root-owned until the move completes.
        let manifest = "Original location: \(candidate.url.path)\n\nThis item was moved by Iron Zapper. It was not permanently deleted.\nTo restore a privileged service, reinstall its application. Finder Put Back is not available for this recovery folder.\n"
        let readme = openat(recovery, "Recovery.txt", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        guard readme >= 0 else { throw error("Write recovery instructions") }
        let data = Array(manifest.utf8)
        let written = data.withUnsafeBytes { write(readme, $0.baseAddress, $0.count) }; close(readme)
        guard written == data.count else { throw error("Write recovery instructions") }
        // Establish recoverability before the source mutation so there is no fallible
        // permission change after the file has moved.
        guard fchown(recovery, uid, gid) == 0 else { throw error("Set recovery folder owner") }
        guard renameatx_np(source, candidate.url.lastPathComponent, recovery, candidate.url.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw error("Move to Trash") }
        return home.appendingPathComponent(".Trash/\(folder)/\(candidate.url.lastPathComponent)").path
    }
    private static func error(_ action: String) -> ZapperError { .invalid("\(action): \(String(cString: strerror(errno)))") }
}
