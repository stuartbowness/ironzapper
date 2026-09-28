import Foundation
import Darwin

public enum ZapperError: LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}
public enum Ownership: String, Codable, Sendable { case exclusive, uncertain, shared, protected }
public enum Category: String, Codable, CaseIterable, Sendable {
    case application = "Application", preferences = "Preferences", caches = "Caches"
    case support = "Application data", logs = "Logs", state = "Saved state", containers = "Containers", services = "Background services"
}
public struct FileIdentity: Codable, Equatable, Sendable {
    public let device: Int32
    public let inode: UInt64
    public let modified: Int64
    public let nanoseconds: Int64
    public let size: Int64
    public let mode: UInt16
    public let owner: UInt32
    public static func read(_ url: URL) throws -> Self {
        var s = stat()
        guard lstat(url.path, &s) == 0 else { throw ZapperError.invalid("Cannot inspect \(url.path): \(String(cString: strerror(errno)))") }
        return Self(device: s.st_dev, inode: s.st_ino, modified: Int64(s.st_mtimespec.tv_sec),
                    nanoseconds: Int64(s.st_mtimespec.tv_nsec), size: s.st_size, mode: s.st_mode, owner: s.st_uid)
    }
    public var isSymbolicLink: Bool { mode & S_IFMT == S_IFLNK }
}
public struct AppIdentity: Codable, Sendable {
    public let url: URL
    public let name: String
    public let bundleID: String
    public let teamID: String?
    public let groups: Set<String>
    public let helperRequirements: [String: String]
    public let fileIdentity: FileIdentity
}
public struct Candidate: Identifiable, Codable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let category: Category
    public let ownership: Ownership
    public let reason: String
    public let bytes: Int64
    public let sizeComplete: Bool
    public let privileged: Bool
    public let identity: FileIdentity
    public var serviceLabel: String? = nil
    public var serviceDomain: String? = nil
    public var selectable: Bool { ownership == .exclusive || (ownership == .uncertain && !privileged && category != .services) }
    public var selectedByDefault: Bool { selectable && ownership == .exclusive }
}
public struct ScanReport: Codable, Sendable {
    public let app: AppIdentity
    public var candidates: [Candidate]
    public var warnings: [String]
    public let scannedAt: Date
}
public struct RemovalOutcome: Identifiable, Codable, Sendable {
    public var id: String { originalPath }
    public let originalPath: String
    public let trashPath: String?
    public let message: String
    public let succeeded: Bool
    public init(originalPath: String, trashPath: String?, message: String, succeeded: Bool) {
        self.originalPath = originalPath; self.trashPath = trashPath; self.message = message; self.succeeded = succeeded
    }
}
public struct ScanLocations: Sendable {
    public let home: URL
    public let systemLibrary: URL
    public let applicationRoots: [URL]
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                systemLibrary: URL = URL(fileURLWithPath: "/Library"),
                applicationRoots: [URL]? = nil) {
        self.home = home; self.systemLibrary = systemLibrary
        self.applicationRoots = applicationRoots ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }
}
public func isWithin(_ child: URL, _ parent: URL) -> Bool {
    let c = child.standardizedFileURL.path, p = parent.standardizedFileURL.path
    return c == p || c.hasPrefix(p + "/")
}

public func canonicalPath(_ url: URL) -> String? {
    guard let resolved = realpath(url.path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
}
