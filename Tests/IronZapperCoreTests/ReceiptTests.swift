import Testing
@testable import IronZapperCore

@Test func exclusiveReceiptFindsOnlyAllowedOwnedFiles() {
    let record = ReceiptRecord(package: "test.pkg", installedApps: ["/Applications/Example.app"], dataFiles: ["/Library/Application Support/Example/helper.dat", "/etc/hosts", "/Library/Caches/../../etc/hosts"])
    let files = ReceiptInspector.exclusiveFiles(appPath: "/Applications/Example.app", records: [record])
    #expect(files == ["/Library/Application Support/Example/helper.dat": "test.pkg"])
}
@Test func sharedReceiptFileIsNotRemovable() {
    let path = "/Library/Application Support/Vendor/shared.dat"
    let a = ReceiptRecord(package: "test.a", installedApps: ["/Applications/A.app"], dataFiles: [path])
    let b = ReceiptRecord(package: "test.b", installedApps: ["/Applications/B.app"], dataFiles: [path])
    #expect(ReceiptInspector.exclusiveFiles(appPath: "/Applications/A.app", records: [a,b]).isEmpty)
}
@Test func suiteInstallerDoesNotProveExclusiveOwnership() {
    let record = ReceiptRecord(package: "test.suite", installedApps: ["/Applications/A.app", "/Applications/B.app"], dataFiles: ["/Library/Application Support/Suite/data"])
    #expect(ReceiptInspector.exclusiveFiles(appPath: "/Applications/A.app", records: [record]).isEmpty)
}
