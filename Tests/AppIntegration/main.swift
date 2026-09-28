import AppKit
import SwiftUI

@main struct AppIntegration {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let fm = FileManager.default
        let id = "test.ironzapper.ui." + UUID().uuidString.lowercased()
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("build/" + id)
        let app = root.appendingPathComponent("IronZapper Fixture.app")
        try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": id, "CFBundleName": "IronZapper Fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let preference = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/" + id + ".plist")
        try Data("disposable UI integration fixture".utf8).write(to: preference)
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: preference) }
        let model = AppModel()
        model.scan(app)
        for _ in 0..<600 {
            if model.phase != .scanning { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard model.phase == .review, let report = model.report, report.candidates.count == 2,
              Set(report.candidates.map(\.id)) == [app.path, preference.path], model.selected.count == 2 else {
            throw ZapperError.invalid("Unexpected fixture scan: \(model.errorMessage ?? "") / \(model.report?.candidates.map(\.id) ?? [])")
        }
        try capture(model, name: "review-light", dark: false)
        try capture(model, name: "review-dark", dark: true)
        // A changed file must stop the whole operation before any file moves.
        try Data("modified after review".utf8).write(to: preference)
        await model.remove()
        guard model.phase == .result, model.outcomes.count == 2, model.outcomes.allSatisfy({ !$0.succeeded }),
              fm.fileExists(atPath: app.path), fm.fileExists(atPath: preference.path) else { throw ZapperError.invalid("Changed-file preflight did not preserve fixture data.") }
        try capture(model, name: "changed-file-result", dark: false)
        model.scan(app)
        for _ in 0..<600 {
            if model.phase != .scanning { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard model.phase == .review else { throw ZapperError.invalid("Fixture rescan failed") }
        await model.remove()
        guard model.phase == .result, model.outcomes.count == 2, model.outcomes.allSatisfy(\.succeeded) else {
            throw ZapperError.invalid("Fixture removal failed: \(model.outcomes.map(\.message))")
        }
        for outcome in model.outcomes {
            guard let path = outcome.trashPath, fm.fileExists(atPath: path) else { throw ZapperError.invalid("A trashed fixture is not recoverable") }
            // Remove only the test data just created and positively identified above.
            try fm.removeItem(atPath: path)
        }
        try capture(model, name: "success-result", dark: true)
        model.reset()
        try capture(model, name: "idle-dark", dark: true)
        let records = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ai.toyo.IronZapper/Operations")
        for file in (try? fm.contentsOfDirectory(at: records, includingPropertiesForKeys: nil)) ?? [] {
            if let data = try? Data(contentsOf: file), let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any], record["appPath"] as? String == app.path { try fm.removeItem(at: file) }
        }
        print("PASS: UI scan → review → changed-file rejection → rescan → Trash → result; both trashed fixtures recovered and cleaned up.")
    }
    @MainActor static func capture(_ model: AppModel, name: String, dark: Bool) throws {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let view = ContentView(model: model).frame(width: 600, height: 640).environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view); renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { throw ZapperError.invalid("Could not render UI verification image") }
        try data.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Artifacts/\(name).png"))
    }
}
