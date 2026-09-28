import Foundation
import Security

public enum AppInspector {
    public static func inspect(_ input: URL) throws -> AppIdentity {
        let url = input
        guard url.isFileURL, url.pathExtension.lowercased() == "app", !url.path.contains("/../"),
              canonicalPath(url) == url.path else {
            throw ZapperError.invalid("Choose an application bundle, not a shortcut or symbolic link.")
        }
        let identity = try FileIdentity.read(url)
        let metadataBundle = try metadataBundleURL(url)
        let metadataURL = metadataBundle.appendingPathComponent(metadataBundle == url ? "Contents/Info.plist" : "Info.plist")
        guard canonicalPath(metadataURL) == metadataURL.path, !identity.isSymbolicLink,
              let data = try? Data(contentsOf: metadataURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              validIdentifier(bundleID), plist["CFBundlePackageType"] as? String == "APPL" else {
            throw ZapperError.invalid("This folder is not a valid Mac application.")
        }
        guard !bundleID.hasPrefix("com.apple."), bundleID != "ai.toyo.IronZapper",
              !isWithin(url, URL(fileURLWithPath: "/System")) else {
            throw ZapperError.invalid("Iron Zapper protects macOS applications and itself.")
        }
        let signature = signingInfo(metadataBundle)
        let entitlements = signature?[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        let groups = Set((entitlements["com.apple.security.application-groups"] as? [String] ?? []).filter(validIdentifier))
        return AppIdentity(url: url, name: plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent,
                           bundleID: bundleID, teamID: signature?[kSecCodeInfoTeamIdentifier as String] as? String,
                           groups: groups, helperRequirements: plist["SMPrivilegedExecutables"] as? [String: String] ?? [:], fileIdentity: identity)
    }
    // Apple Silicon can install iOS applications in an outer .app wrapper.
    // Follow only Apple's internal pointer, confined to a direct child of Wrapper.
    // Discovery uses inner metadata; removal always keeps the outer app URL.
    private static func metadataBundleURL(_ app: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path) { return app }
        let wrapper = app.appendingPathComponent("Wrapper")
        guard canonicalPath(wrapper) == wrapper.path,
              let resolved = canonicalPath(app.appendingPathComponent("WrappedBundle")) else {
            throw ZapperError.invalid("This application is missing its bundle metadata.")
        }
        let inner = URL(fileURLWithPath: resolved)
        guard inner.pathExtension == "app", inner.deletingLastPathComponent().path == wrapper.path,
              let data = try? Data(contentsOf: inner.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              (plist["CFBundleSupportedPlatforms"] as? [String])?.contains("iPhoneOS") == true else {
            throw ZapperError.invalid("This app's wrapped bundle is invalid or points outside the application.")
        }
        return inner
    }
    public static func validIdentifier(_ value: String) -> Bool {
        value.count > 3 && value.count < 240 && value.contains(".") &&
        value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").contains($0) }
    }
    public static func signingInfo(_ url: URL) -> [String: Any]? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return nil }
        return info as? [String: Any]
    }
    public static func helperMatches(_ url: URL, app: AppIdentity) -> Bool {
        guard let team = app.teamID, let requirementText = app.helperRequirements[url.lastPathComponent],
              signingInfo(url)?[kSecCodeInfoTeamIdentifier as String] as? String == team else { return false }
        var requirement: SecRequirement?, code: SecStaticCode?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
