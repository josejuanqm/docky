//
//  AppActivation.swift
//  Docky
//
//  Shared entry point for every "bring this other app forward" call.
//
//  Since macOS 14 activation is cooperative: `NSRunningApplication.activate`
//  is honored only when the *requesting* process is allowed to hand over
//  activation. A `.regular` app that isn't itself frontmost is not, so the
//  call returns false and nothing happens. Docky normally runs `.accessory`,
//  which the system exempts — but it promotes to `.regular` while the
//  Settings or Permissions window is open, and for as long as that window
//  stayed open every dock-tile click silently failed to switch apps (#35).
//
//  `activate(from:)` sidesteps the whole question by transferring activation
//  from whichever app currently owns it, and is honored under either policy.
//

import AppKit

extension NSRunningApplication {
    /// Activates the app by transferring activation away from the frontmost
    /// app, so it works whether or not Docky is `.accessory` or frontmost.
    @discardableResult
    func activateTransferringFrontmost(options: NSApplication.ActivationOptions = []) -> Bool {
        let donor = NSWorkspace.shared.frontmostApplication ?? .current
        if activate(from: donor, options: options) {
            return true
        }

        // Donor may have quit or lost the front slot between the lookup and
        // the call; a plain activate still succeeds while Docky is `.accessory`.
        return activate(options: options)
    }
}
