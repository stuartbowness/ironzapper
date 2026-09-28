import Foundation
import Testing
@testable import IronZapperCore

private func makeWrappedApp(_ f: Fixture) throws -> URL {
    try FileManager.default.removeItem(at: f.app.appendingPathComponent("Contents"))
    let inner = f.app.appendingPathComponent("Wrapper/Example.app")
    try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
    let metadata: [String: Any] = ["CFBundleIdentifier": f.bundleID, "CFBundleName": "Example", "CFBundlePackageType": "APPL", "CFBundleSupportedPlatforms": ["iPhoneOS"]]
    try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0).write(to: inner.appendingPathComponent("Info.plist"))
    try FileManager.default.createSymbolicLink(atPath: f.app.appendingPathComponent("WrappedBundle").path, withDestinationPath: "Wrapper/Example.app")
    return inner
}
@Test func wrappedIOSAppUsesInnerMetadataButSelectsOuterApplication() throws {
    let f = try Fixture()
    let inner = try makeWrappedApp(f)
    let preference = try f.file("Home/Library/Preferences/\(f.bundleID).plist")
    let scan = try f.scanner.scan(f.app)
    #expect(scan.app.bundleID == f.bundleID)
    #expect(scan.app.url.path == f.app.path)
    #expect(scan.candidates.first { $0.category == .application }?.url.path == f.app.path)
    #expect(!scan.candidates.contains { $0.url.path == inner.path })
    #expect(scan.candidates.first { $0.url.path == preference.path }?.selectedByDefault == true)
}
@Test func wrappedPointerCannotEscapeTheSelectedApplication() throws {
    let f = try Fixture()
    let inner = try makeWrappedApp(f)
    let external = f.root.appendingPathComponent("Outside.app")
    try FileManager.default.moveItem(at: inner, to: external)
    let link = f.app.appendingPathComponent("WrappedBundle")
    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
    #expect(throws: (any Error).self) { try f.scanner.scan(f.app) }
}
@Test func redirectedWrapperDirectoryIsRejected() throws {
    let f = try Fixture()
    _ = try makeWrappedApp(f)
    let wrapper = f.app.appendingPathComponent("Wrapper")
    let outside = f.root.appendingPathComponent("Outside")
    try FileManager.default.moveItem(at: wrapper, to: outside)
    try FileManager.default.createSymbolicLink(at: wrapper, withDestinationURL: outside)
    #expect(throws: (any Error).self) { try f.scanner.scan(f.app) }
}
@Test func wrappedApplicationTrashKeepsTheWholeWrapperRecoverable() throws {
    let f = try Fixture()
    _ = try makeWrappedApp(f)
    let candidate = try #require(f.scanner.scan(f.app).candidates.first { $0.category == .application })
    let result = RemovalEngine.trash(candidate)
    #expect(result.succeeded)
    let path = try #require(result.trashPath)
    defer { try? FileManager.default.removeItem(atPath: path) }
    #expect(FileManager.default.fileExists(atPath: path + "/Wrapper/Example.app/Info.plist"))
    #expect(!FileManager.default.fileExists(atPath: f.app.path))
}
