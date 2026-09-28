import Foundation
import Security
import Darwin

final class HelperSession: NSObject, IronZapperHelperProtocol {
    let uid: uid_t
    let queue = DispatchQueue(label: "ai.toyo.IronZapper.helper.operations")
    init(uid: uid_t) { self.uid = uid }
    func ping(reply: @escaping (String) -> Void) { reply("Iron Zapper helper ready") }
    func remove(_ data: Data, authorization: Data, reply: @escaping (Data?, String?) -> Void) {
        // XPC dispatch is serialized explicitly; privilege must be authorized per operation.
        queue.async { [self] in
            do {
                guard data.count < 1_000_000, authorization.count == MemoryLayout<AuthorizationExternalForm>.size,
                      let user = getpwuid(uid), uid >= 501 else { throw ZapperError.invalid("Invalid user or authorization request.") }
                let home = URL(fileURLWithPath: String(cString: user.pointee.pw_dir)), gid = user.pointee.pw_gid
                var form = AuthorizationExternalForm()
                _ = withUnsafeMutableBytes(of: &form) { authorization.copyBytes(to: $0) }
                var auth: AuthorizationRef?
                guard AuthorizationCreateFromExternalForm(&form, &auth) == errAuthorizationSuccess, let auth else { throw ZapperError.invalid("Administrator authorization is missing.") }
                defer { AuthorizationFree(auth, []) }
                let status = "system.privilege.admin".withCString { name in
                    var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
                    return withUnsafeMutablePointer(to: &item) { pointer in
                        var rights = AuthorizationRights(count: 1, items: pointer)
                        return AuthorizationCopyRights(auth, &rights, nil, [], nil)
                    }
                }
                guard status == errAuthorizationSuccess else { throw ZapperError.invalid("Administrator authorization was not granted.") }
                let request = try JSONDecoder().decode(HelperRequest.self, from: data)
                guard request.candidates.count <= 100,
                      isWithin(request.appURL, URL(fileURLWithPath: "/Applications")),
                      try FileIdentity.read(request.appURL) == request.appIdentity else { throw ZapperError.invalid("Application changed or is outside /Applications.") }
                let scan = try AppScanner(locations: ScanLocations(home: home)).scan(request.appURL)
                var approved = [Candidate]()
                for requested in request.candidates {
                    guard let fresh = scan.candidates.first(where: { $0.id == requested.id }), fresh.ownership == .exclusive,
                          fresh.privileged, fresh.identity == requested.identity else {
                        throw ZapperError.invalid("System ownership or file identity changed. Scan again.")
                    }
                    try RemovalEngine.validate(fresh); approved.append(fresh)
                }
                // A helper cannot be removed while its associated launch plist is left installed.
                for item in approved where item.url.deletingLastPathComponent().lastPathComponent == "PrivilegedHelperTools" {
                    guard approved.contains(where: { serviceInfo($0.url)?.program == item.url.path }) else {
                        throw ZapperError.invalid("Select the helper's launch service as well as its executable.")
                    }
                }
                for item in approved { try SecureTrash.preflight(item, home: home, uid: uid) }
                var outcomes = [RemovalOutcome](), failed = false
                for item in RemovalEngine.ordered(approved) {
                    if failed { outcomes.append(.init(originalPath: item.id, trashPath: nil, message: "Preserved after an earlier system operation failed.", succeeded: false)); continue }
                    var stopped = false
                    do {
                        if let label = item.serviceLabel {
                            try RemovalEngine.stopService(label: label, domain: item.serviceDomain == "system" ? "system" : "gui/\(uid)")
                            stopped = true
                        }
                        let path = try SecureTrash.move(item, home: home, uid: uid, gid: gid)
                        outcomes.append(.init(originalPath: item.id, trashPath: path, message: "Moved to a recovery folder in Trash. Reinstall the app to restore its service.", succeeded: true))
                    } catch {
                        failed = true
                        outcomes.append(.init(originalPath: item.id, trashPath: nil, message: (stopped ? "Service was stopped. " : "") + error.localizedDescription, succeeded: false))
                    }
                }
                reply(try JSONEncoder().encode(outcomes), nil)
            } catch { reply(nil, error.localizedDescription) }
        }
    }
}
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier >= 501,
              let requirement = try? SigningRequirement.peer(identifier: "ai.toyo.IronZapper") else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: IronZapperHelperProtocol.self)
        connection.exportedObject = HelperSession(uid: connection.effectiveUserIdentifier)
        connection.resume()
        return true
    }
}
let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: helperServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
