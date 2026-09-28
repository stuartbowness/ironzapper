import Foundation
import Security

let helperServiceName = "ai.toyo.IronZapper.Helper"
let helperPlistName = helperServiceName + ".plist"

@objc protocol IronZapperHelperProtocol {
    func ping(reply: @escaping (String) -> Void)
    func remove(_ request: Data, authorization: Data, reply: @escaping (Data?, String?) -> Void)
}
struct HelperRequest: Codable {
    let appURL: URL
    let appIdentity: FileIdentity
    let candidates: [Candidate]
}
enum SigningRequirement {
    static func peer(identifier: String) throws -> String {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any], let team = dict[kSecCodeInfoTeamIdentifier as String] as? String,
              team.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            throw ZapperError.invalid("Iron Zapper needs a valid development or Developer ID signature to use its helper.")
        }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\" and !(entitlement[\"com.apple.security.get-task-allow\"] exists)"
    }
}
