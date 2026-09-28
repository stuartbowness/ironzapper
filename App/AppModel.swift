import AppKit
import SwiftUI
import ServiceManagement

@MainActor @Observable final class AppModel {
    enum Phase { case idle, scanning, review, removing, result }
    var phase: Phase = .idle
    var report: ScanReport?
    var selected = Set<String>()
    var outcomes = [RemovalOutcome]()
    var errorMessage: String?
    var showQuitConfirmation = false
    var currentOperation = ""
    var progress = 0.0
    var helperStatus: SMAppService.Status = .notRegistered
    let helper = HelperClient()
    private var scanTask: Task<Void, Never>?
    private let zapSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "Zap", withExtension: "wav") else { return nil }
        let sound = NSSound(contentsOf: url, byReference: false)
        sound?.volume = 0.65
        return sound
    }()
    var selectedCandidates: [Candidate] { report?.candidates.filter { selected.contains($0.id) && $0.selectable } ?? [] }
    var selectedBytes: Int64 { selectedCandidates.reduce(0) { $0 + $1.bytes } }
    var busy: Bool { phase == .scanning || phase == .removing }
    var systemSelection: Bool { selectedCandidates.contains { $0.privileged && $0.category != .application } }
    var appIcon: NSImage { report.map { NSWorkspace.shared.icon(forFile: $0.app.url.path) } ?? NSImage(named: NSImage.applicationIconName)! }
    init() { helperStatus = helper.status }
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose Application"
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }
    func scan(_ url: URL) {
        guard phase != .removing else { return }
        scanTask?.cancel(); phase = .scanning; report = nil; selected = []; outcomes = []
        currentOperation = url.deletingPathExtension().lastPathComponent
        scanTask = Task {
            let worker = Task.detached(priority: .userInitiated) { try AppScanner().scan(url) }
            do {
                let found = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                report = found; selected = Set(found.candidates.filter(\.selectedByDefault).map(\.id)); phase = .review
            } catch is CancellationError { /* The action that cancelled the task owns the state. */ }
            catch { if !Task.isCancelled { phase = .idle; errorMessage = error.localizedDescription } }
        }
    }
    func reset() { guard phase != .removing else { return }; scanTask?.cancel(); report = nil; selected = []; outcomes = []; phase = .idle }
    func beginRemoval() {
        guard !selectedCandidates.isEmpty, let app = report?.app else { return }
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL == app.url || $0.bundleIdentifier == app.bundleID }) {
            showQuitConfirmation = true
        } else { Task { await remove() } }
    }
    func quitAndRemove() {
        guard let app = report?.app else { return }
        Task {
            let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL == app.url || $0.bundleIdentifier == app.bundleID }
            for process in running { process.terminate() }
            for _ in 0..<30 {
                if running.allSatisfy(\.isTerminated) { await remove(); return }
                try? await Task.sleep(for: .milliseconds(200))
            }
            errorMessage = "The app is still running. Finish saving your work and quit it, then try again."
        }
    }
    func enableHelper() {
        do { try helper.enable(); helperStatus = helper.status }
        catch { errorMessage = "System cleanup could not be enabled: \(error.localizedDescription)" }
    }
    func refreshHelper() { helperStatus = helper.status }
    func disableHelper() { Task { do { try await helper.disable(); refreshHelper() } catch { errorMessage = error.localizedDescription } } }
    func remove() async {
        guard phase == .review, let report else { return }
        let items = RemovalEngine.ordered(selectedCandidates)
        let privileged = items.filter { $0.privileged && $0.category != .application }
        if !privileged.isEmpty && helper.status != .enabled {
            errorMessage = "Enable system cleanup and approve Iron Zapper in System Settings before removing these items. Nothing has been removed."; return
        }
        phase = .removing; outcomes = []; progress = 0; currentOperation = "Rechecking ownership…"
        do {
            let fresh = try await Task.detached { try AppScanner().scan(report.app.url) }.value
            guard fresh.app.fileIdentity == report.app.fileIdentity else { throw ZapperError.invalid("The application changed. Scan again.") }
            for item in items {
                guard let updated = fresh.candidates.first(where: { $0.id == item.id }), updated.selectable,
                      updated.ownership == item.ownership, updated.identity == item.identity else { throw ZapperError.invalid("Ownership or file contents changed for \(item.url.lastPathComponent). Scan again.") }
            }
            // Play once after validation, for both direct and quit-confirmed cleanup.
            // Playback is asynchronous and never controls the removal operation.
            zapSound?.play()
            if !privileged.isEmpty {
                currentOperation = "Removing system components…"
                outcomes += try await helper.remove(app: report.app, candidates: privileged)
            }
            var failed = outcomes.contains { !$0.succeeded }
            for item in items where !privileged.contains(where: { $0.id == item.id }) {
                currentOperation = item.url.lastPathComponent
                if failed {
                    outcomes.append(.init(originalPath: item.id, trashPath: nil, message: "Preserved after an earlier operation failed.", succeeded: false))
                } else {
                    let outcome = await Task.detached { RemovalEngine.trash(item) }.value
                    outcomes.append(outcome); failed = !outcome.succeeded
                }
                progress = Double(outcomes.count) / Double(max(items.count, 1))
            }
        } catch {
            for item in items where !outcomes.contains(where: { $0.id == item.id }) {
                outcomes.append(.init(originalPath: item.id, trashPath: nil, message: error.localizedDescription, succeeded: false))
            }
        }
        do { try RemovalEngine.record(app: report.app, outcomes: outcomes) }
        catch { errorMessage = "Cleanup results could not be saved: \(error.localizedDescription)" }
        phase = .result
    }
}
