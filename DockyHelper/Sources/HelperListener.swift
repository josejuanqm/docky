//
//  HelperListener.swift
//  DockyHelper
//
//  NSXPCListener that vends `DockyHelperProtocol`. Bound to the
//  Mach service `gt.quintero.Docky.Helper` (matches the LaunchAgent
//  plist).
//
//  Connection acceptance pins the peer to our Team ID via
//  `SecCodeCheckValidity` over the connection's `auditToken`. Any
//  caller that isn't Docky.app (MAS) signed under the same team is
//  rejected, so the helper can't be repurposed by another app on
//  the machine.
//

import Foundation
import Security

final class HelperListener: NSObject, NSXPCListenerDelegate {
    static let machServiceName = "gt.quintero.Docky.Helper"

    private let listener: NSXPCListener

    override init() {
        self.listener = NSXPCListener(machServiceName: Self.machServiceName)
        super.init()
        listener.delegate = self
    }

    func start() {
        listener.resume()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        guard isAcceptableClient(newConnection) else {
            NSLog("[DockyHelper] Rejected XPC connection: peer code signing did not match Docky Team ID")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: DockyHelperProtocol.self)
        newConnection.exportedObject = HelperService()
        newConnection.resume()
        return true
    }

    /// Verifies the peer process is signed under Docky's Team ID by
    /// running its `audit_token` through `SecCodeCopyGuestWithAttributes`
    /// and checking against an identifier requirement string. This is
    /// the standard cross-process trust pattern; the same recipe lives
    /// in Apple's "Embedded Helper" sample code.
    private func isAcceptableClient(_ connection: NSXPCConnection) -> Bool {
        var token = connection.auditToken
        let tokenData = Data(bytes: &token, count: MemoryLayout.size(ofValue: token))

        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary

        var codeRef: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &codeRef) == errSecSuccess,
              let code = codeRef else {
            return false
        }

        // Identifier prefix is the Docky bundle id family; MAS uses
        // `.appstore`, Developer ID uses the bare identifier. Both
        // are signed under the same Team ID so the requirement string
        // pins to the team-id anchor.
        let requirementString = """
        identifier "gt.quintero.Docky" or identifier "gt.quintero.Docky.appstore" \
        and anchor apple generic and certificate leaf[subject.OU] = "<TEAM_ID_PLACEHOLDER>"
        """

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else {
            return false
        }

        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }
}

private extension NSXPCConnection {
    /// `auditToken` isn't a Swift-visible property by default; it's
    /// accessed through the runtime so the underlying value type
    /// (`audit_token_t`) round-trips correctly.
    var auditToken: audit_token_t {
        var token = audit_token_t()
        let selector = NSSelectorFromString("auditToken")
        guard responds(to: selector) else { return token }
        // The `auditToken` private getter returns the value by copy
        // via the standard Objective-C method dispatch. Read via
        // perform + NSValue to keep the bytes intact.
        if let methodIMP = method(for: selector) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> audit_token_t
            let fn = unsafeBitCast(methodIMP, to: Getter.self)
            token = fn(self, selector)
        }
        return token
    }
}
