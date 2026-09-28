import Foundation

public struct ReceiptEvidence: Sendable {
    public var files: [URL: String] = [:]
    public var warnings: [String] = []
    public init() {}
}
public struct ReceiptRecord: Sendable {
    public let package: String
    public let installedApps: Set<String>
    public let dataFiles: Set<String>
    public init(package: String, installedApps: Set<String>, dataFiles: Set<String>) {
        self.package = package; self.installedApps = installedApps; self.dataFiles = dataFiles
    }
}
/// Receipts are ownership evidence, never executable instructions or unrestricted paths.
public enum ReceiptInspector {
    public static let dataRoots = ["/Library/Application Support", "/Library/Preferences", "/Library/Caches", "/Library/Logs"]
    public static func exclusiveFiles(appPath: String, records: [ReceiptRecord]) -> [String: String] {
        var owners = [String: Set<String>]()
        let packages = Set(records.filter { $0.installedApps == [appPath] }.map(\.package))
        for record in records {
            for file in record.dataFiles where allowedDataPath(file) { owners[file, default: []].insert(record.package) }
        }
        return owners.reduce(into: [:]) { result, entry in
            if entry.value.count == 1, let package = entry.value.first, packages.contains(package) { result[entry.key] = package }
        }
    }
    public static func allowedDataPath(_ path: String) -> Bool {
        !path.split(separator: "/").contains("..") && !path.split(separator: "/").contains(".") &&
            dataRoots.contains { path.hasPrefix($0 + "/") }
    }
    public static func inspect(app: AppIdentity) throws -> ReceiptEvidence {
        var result = ReceiptEvidence()
        let root = URL(fileURLWithPath: "/var/db/receipts")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            result.warnings.append("Installer receipts could not be read. Receipt-owned system data is preserved."); return result
        }
        var records = [ReceiptRecord](), incomplete = false
        for plist in entries where plist.pathExtension == "plist" {
            try Task.checkCancellation()
            guard let data = try? Data(contentsOf: plist),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let package = info["PackageIdentifier"] as? String else { incomplete = true; continue }
            let bom = plist.deletingPathExtension().appendingPathExtension("bom")
            guard FileManager.default.fileExists(atPath: bom.path) else { continue }
            let prefix = info["InstallPrefixPath"] as? String ?? ""
            guard !prefix.split(separator: "/").contains("..") else { incomplete = true; continue }
            let base = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let listing = try run("/usr/bin/lsbom", ["-s", "-f", bom.path])
            guard listing.status == 0 else { incomplete = true; continue }
            var apps = Set<String>(), files = Set<String>()
            for line in listing.output.split(separator: "\n") {
                let relative = line.hasPrefix("./") ? line.dropFirst(2) : line[...]
                guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { incomplete = true; continue }
                let path = base.isEmpty ? "/" + relative : "/" + base + "/" + relative
                if path.hasPrefix("/Applications/"), let end = path.range(of: ".app/")?.lowerBound {
                    apps.insert(String(path[..<end]) + ".app")
                }
                if dataRoots.contains(where: { path.hasPrefix($0 + "/") }) { files.insert(path) }
            }
            records.append(.init(package: package, installedApps: apps, dataFiles: files))
        }
        guard !incomplete else {
            result.warnings.append("Some installer receipts could not be interpreted. Receipt-owned system data is preserved."); return result
        }
        for (path, package) in exclusiveFiles(appPath: app.url.path, records: records) {
            let url = URL(fileURLWithPath: path)
            guard let identity = try? FileIdentity.read(url), identity.mode & S_IFMT == S_IFREG,
                  !identity.isSymbolicLink, canonicalPath(url) == path else { continue }
            result.files[url] = package
        }
        return result
    }
}
