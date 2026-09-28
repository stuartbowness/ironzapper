import Foundation
import ServiceManagement
import Security

@MainActor final class HelperClient {
    let service = SMAppService.daemon(plistName: helperPlistName)
    var status: SMAppService.Status { service.status }
    func enable() throws {
        if service.status == .notRegistered || service.status == .notFound { try service.register() }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
    func disable() async throws { try await service.unregister() }
    func remove(app: AppIdentity, candidates: [Candidate]) async throws -> [RemovalOutcome] {
        guard status == .enabled else { throw ZapperError.invalid("Enable system cleanup first, approve Iron Zapper in Login Items & Extensions, then try again.") }
        let auth = try authorization()
        let data = try JSONEncoder().encode(HelperRequest(appURL: app.url, appIdentity: app.fileIdentity, candidates: candidates))
        let requirement = try SigningRequirement.peer(identifier: helperServiceName)
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: helperServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: IronZapperHelperProtocol.self)
            connection.setCodeSigningRequirement(requirement)
            let completion = ReplyOnce(continuation: continuation, connection: connection)
            connection.invalidationHandler = { completion.finish(.failure(ZapperError.invalid("Helper connection ended. Inspect Trash and scan again before retrying."))) }
            connection.interruptionHandler = { completion.finish(.failure(ZapperError.invalid("Helper was interrupted. Some operations may have completed; inspect Trash before retrying."))) }
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in completion.finish(.failure(error)) }) as? IronZapperHelperProtocol else {
                completion.finish(.failure(ZapperError.invalid("Could not connect to system cleanup."))); return
            }
            proxy.remove(data, authorization: auth) { data, error in
                if let error { completion.finish(.failure(ZapperError.invalid(error))) }
                else if let data {
                    do { completion.finish(.success(try JSONDecoder().decode([RemovalOutcome].self, from: data))) }
                    catch { completion.finish(.failure(error)) }
                } else { completion.finish(.failure(ZapperError.invalid("Helper returned an incomplete result."))) }
            }
        }
    }
    private func authorization() throws -> Data {
        var reference: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &reference) == errAuthorizationSuccess, let reference else { throw ZapperError.invalid("Could not request administrator authorization.") }
        defer { AuthorizationFree(reference, []) }
        let status = "system.privilege.admin".withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                return AuthorizationCopyRights(reference, &rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], nil)
            }
        }
        guard status == errAuthorizationSuccess else { throw ZapperError.invalid("Administrator authorization was cancelled or denied. Nothing has been removed.") }
        var form = AuthorizationExternalForm()
        guard AuthorizationMakeExternalForm(reference, &form) == errAuthorizationSuccess else { throw ZapperError.invalid("Could not authorize system cleanup.") }
        return withUnsafeBytes(of: form) { Data($0) }
    }
}
private final class ReplyOnce: @unchecked Sendable {
    let lock = NSLock()
    var continuation: CheckedContinuation<[RemovalOutcome], Error>?
    let connection: NSXPCConnection
    init(continuation: CheckedContinuation<[RemovalOutcome], Error>, connection: NSXPCConnection) { self.continuation = continuation; self.connection = connection }
    func finish(_ result: Result<[RemovalOutcome], Error>) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        guard let c else { return }
        connection.invalidationHandler = nil; connection.interruptionHandler = nil; connection.invalidate()
        c.resume(with: result)
    }
}
