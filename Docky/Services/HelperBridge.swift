//
//  HelperBridge.swift
//  Docky
//
//  XPC client for the optional Docky Helper. The helper is a separately
//  distributed Developer ID-signed agent that lives outside the App
//  Store sandbox and vends the private-API features Docky depends on
//  (SkyLight blur, AX window control, MediaRemote, system Dock
//  manipulation, etc).
//
//  Both bundles are signed with the same Team ID, so the helper's
//  XPC listener can verify the client is genuinely Docky via
//  `audit_token` + `SecCodeCheckValidity`, and the client can verify
//  the helper the same way. No HMAC handshake, no shared secrets.
//
//  Goal-shaping (per /goal):
//  - The full Developer ID product never asks the bridge anything,
//    its features call private APIs directly. The bridge exists only
//    so the MAS / sandboxed build can light up the same features
//    *when* the user has installed the helper.
//  - `isAvailable` gates every UI affordance for features that
//    require the helper. When `false`, the controls don't render at
//    all (clean optics: the user doesn't see disabled buttons or
//    "needs helper" CTAs unless they go looking for them).
//  - The MAS-only build (gated by `#if APP_STORE_SANDBOX`, added in
//    a follow-up commit) is the only consumer of this bridge today.
//    Until then it's harmless dead code with `isAvailable == false`.
//
//  Protocol versioning: the first call on every fresh connection is
//  `ping(reply:)` returning `"pong:vN"`. The bridge refuses to
//  expose `isAvailable = true` unless the helper's version matches
//  what this bundle was built against. Update + ship them in
//  lockstep when the protocol changes.
//

import Combine
import Foundation

/// XPC protocol the side-loaded helper vends. Kept @objc / Objective-C
/// compatible so it can be shared via an Obj-C bridging header if we
/// ever extract it into a framework target. Adding methods is fine;
/// renaming or changing signatures is a protocol-version bump.
@objc protocol DockyHelperProtocol {
    /// Liveness + version handshake. Reply is `"pong:vN"`; bridge
    /// validates `N` against `HelperBridge.expectedProtocolVersion`
    /// before flipping `isAvailable` true.
    func ping(reply: @escaping (String) -> Void)
}

@MainActor
final class HelperBridge: ObservableObject {
    static let shared = HelperBridge()

    /// True only after the helper has been reached and its protocol
    /// version matches. Drives every gated UI affordance, view-level
    /// `if HelperBridge.shared.isAvailable { ... }` is the canonical
    /// gate.
    @Published private(set) var isAvailable: Bool = false

    /// Bump in lockstep with `DockyHelperProtocol` whenever a method
    /// is renamed, removed, or has its signature changed.
    static let expectedProtocolVersion = 1

    /// Mach service name the helper's LaunchAgent registers. Same
    /// string lives in the helper's launchd plist and in the MAS
    /// build's `temporary-exception.mach-lookup.global-name`
    /// entitlement (or in the App Group scope when we move to that).
    static let machServiceName = "gt.quintero.Docky.Helper"

    private init() {
        // Intentionally no connect-on-launch. `startIfNeeded()` is
        // called once at app start from `AppDelegate` (added in a
        // follow-up commit) so the bridge state is wired up before
        // any view reads `isAvailable`.
    }

    /// Public entry point. Idempotent. Tries to reach the helper;
    /// flips `isAvailable` to match the result. Future commits add
    /// the real `NSXPCConnection` here, today it's a stub so callers
    /// can already be wired against the API.
    func startIfNeeded() {
        // Phase 0: no helper exists yet. Stay unavailable so every
        // gated feature stays hidden. The day the helper ships, this
        // method becomes the real NSXPCConnection + ping handshake.
        isAvailable = false
    }

    /// Drops any active connection and reports unavailable. Called on
    /// app termination and when the helper invalidates the connection
    /// (e.g. user removed the helper while Docky was running).
    func teardown() {
        isAvailable = false
    }
}
