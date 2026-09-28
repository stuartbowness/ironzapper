import Foundation

@main struct HelperProbe {
    static func main() throws {
        let connection = NSXPCConnection(machServiceName: helperServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: IronZapperHelperProtocol.self)
        connection.setCodeSigningRequirement(try SigningRequirement.peer(identifier: helperServiceName))
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            fputs("Helper connection rejected or unavailable: \(error.localizedDescription)\n", stderr)
            exit(1)
        } as! IronZapperHelperProtocol
        proxy.ping { message in
            print(message)
            exit(0)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { fputs("Helper connection timed out.\n", stderr); exit(2) }
        RunLoop.current.run()
    }
}
