import Foundation

public enum RemovalEngine {
    public static func validate(_ candidate: Candidate) throws {
        guard candidate.selectable else { throw ZapperError.invalid("This item is protected or its ownership is uncertain.") }
        guard !candidate.url.pathComponents.contains(".."),
              canonicalPath(candidate.url) == candidate.url.path,
              try FileIdentity.read(candidate.url) == candidate.identity else {
            throw ZapperError.invalid("This item changed after the scan. Scan again before removing it.")
        }
    }
    public static func trash(_ candidate: Candidate) -> RemovalOutcome {
        do {
            try validate(candidate)
            guard !candidate.privileged else { throw ZapperError.invalid("Administrator helper required.") }
            if let label = candidate.serviceLabel {
                try stopService(label: label, domain: "gui/\(getuid())")
            }
            try validate(candidate)
            var result: NSURL?
            try FileManager.default.trashItem(at: candidate.url, resultingItemURL: &result)
            return RemovalOutcome(originalPath: candidate.url.path, trashPath: result?.path, message: candidate.serviceLabel == nil ? "Moved to Trash" : "Service stopped and moved to Trash. Reinstall to restore its registration.", succeeded: true)
        } catch {
            return RemovalOutcome(originalPath: candidate.url.path, trashPath: nil, message: error.localizedDescription, succeeded: false)
        }
    }
    public static func stopService(label: String, domain: String) throws {
        guard AppInspector.validIdentifier(label), !label.hasPrefix("com.apple."),
              domain == "system" || domain.hasPrefix("gui/") else { throw ZapperError.invalid("Invalid service identity.") }
        let target = domain + "/" + label
        let check = try run("/bin/launchctl", ["print", target])
        if check.status != 0 {
            // launchctl uses 113 for an absent service. Other errors must not be interpreted as absence.
            if check.status == 113 { return }
            throw ZapperError.invalid("Could not determine whether \(label) is running: \(check.output)")
        }
        let stop = try run("/bin/launchctl", ["bootout", target])
        guard stop.status == 0 else { throw ZapperError.invalid("Could not stop \(label): \(stop.output)") }
    }
    public static func ordered(_ candidates: [Candidate]) -> [Candidate] {
        candidates.sorted {
            func priority(_ c: Candidate) -> Int { c.category == .application ? 3 : c.serviceLabel != nil ? 0 : c.category == .services ? 1 : 2 }
            if priority($0) != priority($1) { return priority($0) < priority($1) }
            return $0.id < $1.id
        }
    }
    public static func record(app: AppIdentity, outcomes: [RemovalOutcome], home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        struct Receipt: Codable { let date: Date; let appPath: String; let bundleID: String; let items: [RemovalOutcome] }
        let directory = home.appendingPathComponent("Library/Application Support/ai.toyo.IronZapper/Operations")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Receipt(date: Date(), appPath: app.url.path, bundleID: app.bundleID, items: outcomes))
            .write(to: directory.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
    }
}
public func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
    process.standardOutput = pipe; process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}
