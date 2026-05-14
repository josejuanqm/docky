//
//  DockyHelperProtocol.swift
//  DockyHelper
//
//  XPC interface vended by the helper. Same file is referenced (via
//  symlink or build-phase copy) from both the helper target and the
//  MAS Docky target so the contract stays in lockstep.
//
//  Adding methods is fine; renaming or changing signatures is a
//  protocol-version bump that requires both ends to update.
//

import Foundation

@objc public protocol DockyHelperProtocol {
    /// Liveness + version handshake. Reply must be `"pong:vN"`.
    /// The MAS bridge refuses to set `isAvailable = true` unless the
    /// returned version matches what the bundle was built against.
    func ping(reply: @escaping (String) -> Void)
}
