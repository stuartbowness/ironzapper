import Foundation
import Darwin
import Testing
@testable import IronZapperCore
@testable import IronZapperPrivileged

@Test func directoryWalkRefusesSymlinkAncestors() throws {
    let fixture = try Fixture()
    let directory = fixture.root.appendingPathComponent("Real")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let link = fixture.root.appendingPathComponent("Alias")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
    #expect(throws: (any Error).self) { _ = try SecureTrash.openDirectory(link) }
    let fd = try SecureTrash.openDirectory(directory)
    #expect(fd >= 0)
    close(fd)
}
@Test func trustedWalkRejectsUserControlledDirectories() throws {
    let fixture = try Fixture()
    #expect(throws: (any Error).self) { _ = try SecureTrash.openDirectory(fixture.root, trusted: true) }
}
@Test func privilegedTrashRejectsAnUnrelatedPath() throws {
    let fixture = try Fixture()
    let important = try fixture.file("Important.txt", text: "must survive")
    let candidate = Candidate(url: important, category: .services, ownership: .exclusive, reason: "forged request", bytes: 12, sizeComplete: true, privileged: true, identity: try FileIdentity.read(important))
    #expect(throws: (any Error).self) { _ = try SecureTrash.move(candidate, home: fixture.home, uid: getuid(), gid: getgid()) }
    #expect(try String(contentsOf: important, encoding: .utf8) == "must survive")
}
@Test func sharedAppGroupIsProtectedEvenWhenNamedAfterTheApp() throws {
    let f = try Fixture()
    let data = try f.file("Home/Library/Group Containers/\(f.bundleID)/shared.db")
    let item = try #require(f.scanner.scan(f.app).candidates.first { $0.url.path == data.deletingLastPathComponent().path })
    #expect(item.ownership == .shared)
    #expect(!item.selectable)
}
@Test func secondLaunchServicePreventsExclusiveServiceRemoval() throws {
    let f = try Fixture()
    let program = try f.file("Applications/Example.app/Contents/MacOS/service")
    let plist: [String: Any] = ["Label": f.bundleID, "Program": program.path]
    let first = try f.file("Library/LaunchDaemons/\(f.bundleID).plist")
    let second = try f.file("Library/LaunchDaemons/other.vendor.plist")
    let bytes = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try bytes.write(to: first); try bytes.write(to: second)
    let item = try #require(f.scanner.scan(f.app).candidates.first { $0.url.path == first.path })
    #expect(!item.selectable)
}
