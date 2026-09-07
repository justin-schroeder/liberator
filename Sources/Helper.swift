import Foundation
import Security
import Darwin

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard !BuildIdentity.teamID.isEmpty, connection.effectiveUserIdentifier >= 501 else { return false }
        connection.setCodeSigningRequirement("anchor apple generic and certificate leaf[subject.OU] = \"\(BuildIdentity.teamID)\" and identifier \"app.liberator.mac\"")
        guard let pw = getpwuid(connection.effectiveUserIdentifier), let home = pw.pointee.pw_dir else { return false }
        let homePath = String(cString: home)
        guard homePath.hasPrefix("/Users/") else { return false }
        connection.exportedInterface = NSXPCInterface(with: LiberatorHelperProtocol.self)
        connection.exportedObject = HelperSession(home: homePath)
        connection.resume()
        return true
    }
}
final class HelperSession: NSObject, LiberatorHelperProtocol {
    let home: String
    let queue = DispatchQueue(label: "app.liberator.helper.operations")
    init(home: String) { self.home = home }
    func apply(_ payload: Data, authorization: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        queue.async { [self] in
            do {
                guard payload.count <= 8_000_000, authorization.count == MemoryLayout<AuthorizationExternalForm>.size else { throw POSIXError(.EINVAL) }
                var form = AuthorizationExternalForm()
                _ = withUnsafeMutableBytes(of: &form) { authorization.copyBytes(to: $0) }
                var ref: AuthorizationRef?
                guard AuthorizationCreateFromExternalForm(&form, &ref) == errAuthorizationSuccess, let ref else { throw POSIXError(.EACCES) }
                defer { AuthorizationFree(ref, []) }
                let status = "system.privilege.admin".withCString { name -> OSStatus in
                    var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
                    return withUnsafeMutablePointer(to: &item) { p in
                        var rights = AuthorizationRights(count: 1, items: p)
                        return AuthorizationCopyRights(ref, &rights, nil, [.extendRights], nil)
                    }
                }
                guard status == errAuthorizationSuccess else { throw POSIXError(.EACCES) }
                let requests = try JSONDecoder().decode([ChangeRequest].self, from: payload)
                guard requests.count <= 1000 else { throw POSIXError(.E2BIG) }
                let results = requests.map { SafeMutation.apply($0, allowedRoots: ["/Applications", home]) }
                reply(try JSONEncoder().encode(results), nil)
            } catch { reply(nil, error.localizedDescription) }
        }
    }
}
@main struct HelperMain {
    static func main() {
        guard geteuid() == 0, !BuildIdentity.teamID.isEmpty else { fputs("A signed release and root service context are required.\n", stderr); exit(1) }
        let delegate = HelperDelegate()
        let listener = NSXPCListener(machServiceName: serviceName)
        listener.delegate = delegate
        withExtendedLifetime(delegate) { listener.resume(); RunLoop.current.run() }
    }
}
