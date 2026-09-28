import Foundation

public struct AppScanner: Sendable {
    public let locations: ScanLocations
    public init(locations: ScanLocations = ScanLocations()) { self.locations = locations }

    public func scan(_ url: URL) throws -> ScanReport {
        let app = try AppInspector.inspect(url)
        var warnings = [String]()
        let inventory = inventory(excluding: app.url, warnings: &warnings)
        let duplicateID = inventory.apps.contains { $0.bundleID == app.bundleID }
        let siblings = inventory.apps.filter { $0.teamID != nil && $0.teamID == app.teamID }
        var candidates = [Candidate]()
        candidates.append(try candidate(app.url, category: .application, ownership: .exclusive,
                                        reason: "The application you selected.", privileged: !FileManager.default.isWritableFile(atPath: app.url.deletingLastPathComponent().path)))
        let directories: [(String, Category)] = [
            ("Preferences", .preferences), ("Preferences/ByHost", .preferences), ("Caches", .caches),
            ("Application Support", .support), ("Logs", .logs), ("Saved Application State", .state),
            ("Containers", .containers), ("Group Containers", .containers), ("WebKit", .caches),
            ("HTTPStorages", .caches), ("LaunchAgents", .services)
        ]
        for system in [false, true] {
            let library = system ? locations.systemLibrary : locations.home.appendingPathComponent("Library")
            var dirs = directories
            if system { dirs = directories.filter { !["Containers", "Group Containers", "Saved Application State", "WebKit", "HTTPStorages", "Preferences/ByHost"].contains($0.0) } + [("LaunchDaemons", .services), ("PrivilegedHelperTools", .services)] }
            for (relative, category) in dirs {
                try Task.checkCancellation()
                let parent = library.appendingPathComponent(relative)
                guard FileManager.default.fileExists(atPath: parent.path) else { continue }
                guard canonicalPath(parent) == parent.path else {
                    warnings.append("Skipped redirected location: \(parent.path)"); continue
                }
                let children: [URL]
                do { children = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) }
                catch { warnings.append("Could not scan \(parent.path): \(error.localizedDescription)"); continue }
                for child in children {
                    let name = child.lastPathComponent
                    let exact = Self.matchesBundleName(name, bundleID: app.bundleID, byHost: relative == "Preferences/ByHost")
                    let group = app.groups.contains(name)
                    let helper = app.helperRequirements[name] != nil
                    let service = category == .services && child.pathExtension == "plist" ? serviceInfo(child) : nil
                    let programOwned = service.map { isWithin(URL(fileURLWithPath: $0.program), app.url) || app.helperRequirements[URL(fileURLWithPath: $0.program).lastPathComponent] != nil } ?? false
                    let nameMatch = name.caseInsensitiveCompare(app.name) == .orderedSame || name.caseInsensitiveCompare(app.name + ".plist") == .orderedSame
                    guard exact || group || helper || programOwned || nameMatch else { continue }
                    var ownership: Ownership = .uncertain
                    var reason = "Name resembles this application. Review before selecting."
                    if exact { ownership = .exclusive; reason = "Exact application bundle identifier: \(app.bundleID)." }
                    if duplicateID && exact { ownership = .shared; reason = "Another installed copy uses the same bundle identifier." }
                    if group || relative == "Group Containers" { ownership = .shared; reason = "App-group data can be shared with other applications. Preserved." }
                    if system { ownership = .uncertain; reason = "System-wide item; exclusive ownership is not established." }
                    if category == .services {
                        ownership = .uncertain; reason = "Service ownership could not be established. Preserved."
                        if let service, service.label == name.replacingOccurrences(of: ".plist", with: ""), !service.label.hasPrefix("com.apple."), programOwned {
                            let program = URL(fileURLWithPath: service.program)
                            let embedded = isWithin(program, app.url)
                            let signedHelper = AppInspector.helperMatches(program, app: app)
                            if (embedded || signedHelper) && inventory.complete && !duplicateID && !otherAppClaims(program, app: app, inventory: inventory.apps) && !otherServiceReferences(program, excluding: child) {
                                ownership = .exclusive; reason = embedded ? "Launch service runs an executable inside this application." : "Launch service runs a signed helper declared exclusively by this app."
                            }
                        } else if helper && AppInspector.helperMatches(child, app: app) && inventory.complete && !duplicateID && !otherAppClaims(child, app: app, inventory: inventory.apps) {
                            // Helper files are eligible only with an owned launch plist; couple them below.
                            ownership = .exclusive; reason = "Signed helper matches this app's embedded requirement and signing team."
                        }
                    }
                    if !system && !inventory.complete && ownership == .exclusive && category != .application {
                        ownership = .uncertain; reason += " Installed-app inventory is incomplete."
                    }
                    if !system && category == .support && nameMatch && !exact && !siblings.isEmpty {
                        reason = "May be vendor data shared with other installed applications."
                    }
                    do {
                        var item = try candidate(child, category: category, ownership: ownership, reason: reason, privileged: system)
                        if let service { item.serviceLabel = service.label; item.serviceDomain = relative == "LaunchDaemons" ? "system" : "gui" }
                        candidates.append(item)
                    } catch { warnings.append("Could not inspect \(child.path): \(error.localizedDescription)") }
                }
            }
        }
        // Product data is often one level below a vendor folder (for example
        // Application Support/Vendor/Product). Surface the product, never the vendor root.
        for relative in ["Application Support", "Caches", "Logs"] {
            let root = locations.home.appendingPathComponent("Library/" + relative)
            guard canonicalPath(root) == root.path,
                  let vendors = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
            for vendor in vendors {
                try Task.checkCancellation()
                guard !candidates.contains(where: { isWithin(vendor, $0.url) }),
                      canonicalPath(vendor) == vendor.path,
                      (try? vendor.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      let children = try? FileManager.default.contentsOfDirectory(at: vendor, includingPropertiesForKeys: nil) else { continue }
                for child in children where Self.matchesProductName(child.lastPathComponent, app: app) {
                    do {
                        candidates.append(try candidate(child, category: relative == "Application Support" ? .support : relative == "Caches" ? .caches : .logs,
                            ownership: .uncertain, reason: "Product name inside a vendor folder matches this application. This may contain profiles or saved work; review before selecting.", privileged: false))
                    } catch { warnings.append("Could not inspect product data: \(child.path)") }
                }
            }
        }
        // A loose privileged executable has no safe service lifecycle; leave it alone.
        candidates = candidates.map { item in
            if item.url.deletingLastPathComponent().lastPathComponent == "PrivilegedHelperTools" && item.ownership == .exclusive {
                let hasOwnedService = candidates.contains { c in
                    c.ownership == .exclusive && c.serviceLabel != nil && serviceInfo(c.url)?.program == item.url.path
                }
                if !hasOwnedService { return Candidate(url: item.url, category: item.category, ownership: .uncertain, reason: "No exclusively owned launch service was found for this helper.", bytes: item.bytes, sizeComplete: item.sizeComplete, privileged: true, identity: item.identity) }
            }
            return item
        }
        // Receipt files are checked against all receipt owners and bounded Library roots.
        if locations.systemLibrary.path == "/Library" {
            let receiptEvidence = try ReceiptInspector.inspect(app: app)
            warnings += receiptEvidence.warnings
            if inventory.complete && !duplicateID {
                for (file, package) in receiptEvidence.files {
                    if let existing = candidates.first(where: { isWithin(file, $0.url) }), existing.ownership == .exclusive { continue }
                    do {
                        candidates.append(try candidate(file, category: .support, ownership: .exclusive,
                            reason: "Installer receipt \(package) owns this file and installs only the selected application. No other receipt claims it.", privileged: true))
                    } catch { warnings.append("Could not inspect receipt-owned file: \(file.path)") }
                }
            }
        }
        let embeddedServiceLocations = ["Contents/Library/LaunchDaemons", "Contents/Library/LaunchAgents", "Contents/Library/SystemExtensions", "Contents/Library/LoginItems"]
        for path in embeddedServiceLocations where FileManager.default.fileExists(atPath: app.url.appendingPathComponent(path).path) {
            warnings.append("This app contains \(URL(fileURLWithPath: path).lastPathComponent). Use its own settings or vendor uninstaller to unregister embedded services/extensions before removal.")
        }
        warnings.append("Search covers standard application locations and the current user's Library. Other users, custom install locations, keychains, and vendor-managed extensions are not exhaustively scanned.")
        if candidates.contains(where: { !$0.sizeComplete }) { warnings.append("Some file sizes are incomplete because their contents could not be read.") }
        return ScanReport(app: app, candidates: Self.deduplicate(candidates), warnings: warnings, scannedAt: Date())
    }

    public static func matchesProductName(_ name: String, app: AppIdentity) -> Bool {
        func normalise(_ value: String) -> String { value.lowercased().filter { $0.isLetter || $0.isNumber } }
        let leaf = normalise(name)
        let names = [normalise(app.name), normalise(app.bundleID.split(separator: ".").last.map(String.init) ?? "")]
        return leaf.count >= 4 && names.contains(leaf)
    }
    public static func matchesBundleName(_ name: String, bundleID: String, byHost: Bool = false) -> Bool {
        if [bundleID, bundleID + ".plist", bundleID + ".savedState", bundleID + ".binarycookies"].contains(name) { return true }
        guard byHost, name.hasPrefix(bundleID + "."), name.hasSuffix(".plist") else { return false }
        return UUID(uuidString: String(name.dropFirst(bundleID.count + 1).dropLast(6))) != nil
    }
    public static func deduplicate(_ candidates: [Candidate]) -> [Candidate] {
        var result = [Candidate]()
        for item in candidates.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            if !result.contains(where: { $0.id == item.id || ($0.selectable && isWithin(item.url, $0.url)) }) { result.append(item) }
        }
        return result.sorted { a, b in
            if a.category == .application { return true }; if b.category == .application { return false }
            return a.url.path.localizedStandardCompare(b.url.path) == .orderedAscending
        }
    }
    private func candidate(_ url: URL, category: Category, ownership: Ownership, reason: String, privileged: Bool) throws -> Candidate {
        let identity = try FileIdentity.read(url)
        let redirected = identity.isSymbolicLink || canonicalPath(url) != url.path
        let size = Self.size(url)
        return Candidate(url: url, category: category, ownership: redirected ? .protected : ownership,
                         reason: redirected ? "Symbolic links and redirected locations are preserved." : reason,
                         bytes: size.bytes, sizeComplete: size.complete, privileged: privileged, identity: identity)
    }
    public static func size(_ url: URL) -> (bytes: Int64, complete: Bool) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return (0, false) }
        if values.isSymbolicLink == true { return (0, true) }
        if values.isDirectory != true { return (Int64(values.fileSize ?? 0), true) }
        var complete = true, bytes: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in complete = false; return true }) else { return (0, false) }
        for case let file as URL in enumerator {
            if Task.isCancelled { return (bytes, false) }
            guard let v = try? file.resourceValues(forKeys: keys) else { complete = false; continue }
            if v.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if v.isDirectory != true { bytes += Int64(v.fileSize ?? 0) }
        }
        return (bytes, complete)
    }
    private func inventory(excluding target: URL, warnings: inout [String]) -> (apps: [AppIdentity], complete: Bool) {
        var apps = [AppIdentity](), complete = true
        var inventoryWarnings = [String]()
        defer { warnings += inventoryWarnings }
        for root in locations.applicationRoots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { url, _ in
                complete = false; inventoryWarnings.append("Could not inspect installed applications in \(url.path)"); return true
            }) else { complete = false; continue }
            for case let file as URL in walk {
                if (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    walk.skipDescendants()
                    if file.pathExtension == "app", let resolved = canonicalPath(file) {
                        let resolvedURL = URL(fileURLWithPath: resolved)
                        if resolved != canonicalPath(target), let app = try? AppInspector.inspect(resolvedURL) { apps.append(app) }
                    }
                    continue
                }
                if file.pathExtension == "app" {
                    walk.skipDescendants()
                    if canonicalPath(file) != canonicalPath(target), let app = try? AppInspector.inspect(file) { apps.append(app) }
                }
            }
        }
        return (apps, complete)
    }
    private func otherAppClaims(_ program: URL, app: AppIdentity, inventory: [AppIdentity]) -> Bool {
        inventory.contains { $0.helperRequirements[program.lastPathComponent] != nil || $0.bundleID == app.bundleID }
    }
    private func otherServiceReferences(_ program: URL, excluding: URL) -> Bool {
        for root in [locations.systemLibrary.appendingPathComponent("LaunchDaemons"), locations.systemLibrary.appendingPathComponent("LaunchAgents"), locations.home.appendingPathComponent("Library/LaunchAgents")] {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return true }
            for file in files where file.path != excluding.path {
                if serviceInfo(file)?.program == program.path { return true }
            }
        }
        return false
    }
}
public struct ServiceInfo: Sendable { public let label: String; public let program: String }
public func serviceInfo(_ url: URL) -> ServiceInfo? {
    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let label = plist["Label"] as? String, AppInspector.validIdentifier(label),
          let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first,
          program.hasPrefix("/"), !program.contains("/../"), plist["BundleProgram"] == nil else { return nil }
    return ServiceInfo(label: label, program: program)
}
