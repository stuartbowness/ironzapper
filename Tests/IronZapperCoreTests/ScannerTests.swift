import Foundation
import Testing
@testable import IronZapperCore

final class Fixture {
    let root: URL
    let home: URL
    let applications: URL
    let system: URL
    let app: URL
    let bundleID = "test.ironzapper.Example"
    var scanner: AppScanner { AppScanner(locations: ScanLocations(home: home, systemLibrary: system, applicationRoots: [applications])) }
    init() throws {
        root = URL(fileURLWithPath: canonicalPath(FileManager.default.temporaryDirectory)!).appendingPathComponent("IronZapperTests-" + UUID().uuidString)
        home = root.appendingPathComponent("Home"); applications = root.appendingPathComponent("Applications"); system = root.appendingPathComponent("Library")
        app = applications.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try makeApp(app, id: bundleID)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func makeApp(_ url: URL, id: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": id, "CFBundleName": "Example", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    }
    @discardableResult func file(_ path: String, text: String = "fixture") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
}

@Test func exactNamesDoNotCapturePrefixNeighbours() {
    #expect(AppScanner.matchesBundleName("com.example.App.plist", bundleID: "com.example.App"))
    #expect(!AppScanner.matchesBundleName("com.example.AppPro.plist", bundleID: "com.example.App"))
    #expect(!AppScanner.matchesBundleName("com.example.App.helper", bundleID: "com.example.App"))
    #expect(AppScanner.matchesBundleName("com.example.App.\(UUID().uuidString).plist", bundleID: "com.example.App", byHost: true))
    #expect(!AppScanner.matchesBundleName("com.example.App.somebody.plist", bundleID: "com.example.App", byHost: true))
}
@Test func scannerFindsExactPreferencesWithoutMutating() throws {
    let f = try Fixture()
    let exact = try f.file("Home/Library/Preferences/\(f.bundleID).plist")
    let neighbour = try f.file("Home/Library/Preferences/\(f.bundleID)Pro.plist")
    let before = try Data(contentsOf: exact)
    let report = try f.scanner.scan(f.app)
    #expect(report.candidates.first { $0.url.path == exact.path }?.selectedByDefault == true)
    #expect(!report.candidates.contains { $0.url.path == neighbour.path })
    #expect(try Data(contentsOf: exact) == before)
    #expect(FileManager.default.fileExists(atPath: f.app.path))
}
@Test func duplicateInstallationPreservesSharedPreferences() throws {
    let f = try Fixture()
    try f.makeApp(f.applications.appendingPathComponent("Another Copy.app"), id: f.bundleID)
    let preference = try f.file("Home/Library/Preferences/\(f.bundleID).plist")
    let match = try #require(f.scanner.scan(f.app).candidates.first { $0.url.path == preference.path })
    #expect(match.ownership == .shared)
    #expect(!match.selectable)
}
@Test func nameOnlySupportFolderNeedsExplicitSelection() throws {
    let f = try Fixture()
    let file = try f.file("Home/Library/Application Support/Example/data.db")
    let match = try #require(f.scanner.scan(f.app).candidates.first { $0.url.path == file.deletingLastPathComponent().path })
    #expect(match.ownership == .uncertain)
    #expect(match.selectable)
    #expect(!match.selectedByDefault)
}
@Test func unknownSystemDataIsNeverSelectable() throws {
    let f = try Fixture()
    let file = try f.file("Library/Application Support/\(f.bundleID)/data.db")
    let match = try #require(f.scanner.scan(f.app).candidates.first { $0.url.path == file.deletingLastPathComponent().path })
    #expect(match.ownership == .uncertain)
    #expect(!match.selectable)
}
@Test func symbolicLinkCannotTargetUnrelatedData() throws {
    let f = try Fixture()
    let unrelated = try f.file("Important.txt", text: "keep me")
    let link = f.home.appendingPathComponent("Library/Caches/\(f.bundleID)")
    try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: unrelated)
    let match = try #require(f.scanner.scan(f.app).candidates.first { $0.url.path == link.path })
    #expect(match.ownership == .protected)
    #expect(!match.selectable)
    #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep me")
}
@Test func changedFileIsRejectedBeforeTrash() throws {
    let f = try Fixture()
    let file = try f.file("Home/Library/Preferences/\(f.bundleID).plist")
    let candidate = try #require(f.scanner.scan(f.app).candidates.first { $0.url.path == file.path })
    try Data("changed contents".utf8).write(to: file)
    #expect(throws: (any Error).self) { try RemovalEngine.validate(candidate) }
    let outcome = RemovalEngine.trash(candidate)
    #expect(!outcome.succeeded)
    #expect(FileManager.default.fileExists(atPath: file.path))
}
@Test func replacedFileWithSameNameIsRejected() throws {
    let f = try Fixture()
    let file = try f.file("Home/Library/Preferences/\(f.bundleID).plist")
    let candidate = try #require(f.scanner.scan(f.app).candidates.first { $0.url.path == file.path })
    let replacement = try f.file("replacement", text: "different")
    _ = try FileManager.default.replaceItemAt(file, withItemAt: replacement)
    #expect(throws: (any Error).self) { try RemovalEngine.validate(candidate) }
}
@Test func appleApplicationsAndIronZapperAreProtected() throws {
    let f = try Fixture()
    for id in ["com.apple.Finder", "ai.toyo.IronZapper"] {
        try f.makeApp(f.app, id: id)
        #expect(throws: (any Error).self) { try f.scanner.scan(f.app) }
    }
}
@Test func invalidBundleIdentifiersCannotEscapeSearchRoots() throws {
    let f = try Fixture()
    try f.makeApp(f.app, id: "../../somewhere")
    #expect(throws: (any Error).self) { try f.scanner.scan(f.app) }
}
@Test func servicePointingElsewhereIsPreserved() throws {
    let f = try Fixture()
    let plist: [String: Any] = ["Label": f.bundleID, "ProgramArguments": ["/usr/bin/true"]]
    let url = try f.file("Library/LaunchDaemons/\(f.bundleID).plist")
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
    let item = try #require(f.scanner.scan(f.app).candidates.first { $0.url.path == url.path })
    #expect(!item.selectable)
}
@Test func ownedEmbeddedServiceIsFoundAndOrderedBeforeApplication() throws {
    let f = try Fixture()
    let program = try f.file("Applications/Example.app/Contents/MacOS/service")
    let url = try f.file("Library/LaunchDaemons/\(f.bundleID).plist")
    let plist: [String: Any] = ["Label": f.bundleID, "Program": program.path]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
    let report = try f.scanner.scan(f.app)
    let service = try #require(report.candidates.first { $0.url.path == url.path })
    #expect(service.selectedByDefault)
    #expect(RemovalEngine.ordered(report.candidates).first?.url == url)
    #expect(RemovalEngine.ordered(report.candidates).last?.category == .application)
}
@Test func unreadableLibraryIsReported() throws {
    let f = try Fixture()
    let directory = f.home.appendingPathComponent("Library/Preferences")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
    let report = try f.scanner.scan(f.app)
    #expect(report.warnings.contains { $0.contains("Could not scan") })
}
@Test func realTrashOperationKeepsDisposableDataRecoverable() throws {
    let f = try Fixture()
    let file = try f.file("Home/Library/Preferences/\(f.bundleID).plist", text: "recoverable fixture")
    let candidate = try #require(f.scanner.scan(f.app).candidates.first { $0.url.path == file.path })
    let result = RemovalEngine.trash(candidate)
    #expect(result.succeeded)
    let path = try #require(result.trashPath)
    let trashed = URL(fileURLWithPath: path)
    defer { try? FileManager.default.removeItem(at: trashed) }
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(try String(contentsOf: trashed, encoding: .utf8) == "recoverable fixture")
}

@Test func sizeIncludesRealFrameworkVersionsWithoutFollowingLinks() throws {
    let f = try Fixture()
    let data = try f.file("Framework/Versions/A/Payload", text: String(repeating: "x", count: 4096))
    let version = data.deletingLastPathComponent()
    try FileManager.default.createSymbolicLink(at: version.deletingLastPathComponent().appendingPathComponent("Current"), withDestinationURL: version)
    try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("Framework/Payload"), withDestinationURL: data)
    let other = try f.file("Framework/OtherData", text: String(repeating: "y", count: 100))
    let size = AppScanner.size(other.deletingLastPathComponent())
    #expect(size.complete)
    #expect(size.bytes == 4196)
}

@Test func nestedProductDataIsShownWithoutSelectingItsVendorFolder() throws {
    let f = try Fixture()
    let data = try f.file("Home/Library/Application Support/Vendor/Example/profile.db")
    let unrelated = try f.file("Home/Library/Application Support/Vendor/OtherProduct/data.db")
    let report = try f.scanner.scan(f.app)
    let item = try #require(report.candidates.first { $0.url.path == data.deletingLastPathComponent().path })
    #expect(item.ownership == .uncertain)
    #expect(!item.selectedByDefault)
    #expect(item.selectable)
    #expect(!report.candidates.contains { $0.url.path == unrelated.deletingLastPathComponent().path })
    #expect(!report.candidates.contains { $0.url.path == data.deletingLastPathComponent().deletingLastPathComponent().path })
}
