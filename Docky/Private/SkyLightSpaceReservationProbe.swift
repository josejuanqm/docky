//
//  SkyLightSpaceReservationProbe.swift
//  Docky
//
//  Experimental probe for "use the system Dock as the screen-space reserver,
//  suppress its visuals via SkyLight." Not wired into Docky's runtime —
//  intended to be invoked manually (lldb, debug menu item, scratch button)
//  to gather data before committing to an implementation.
//
//  Phase 1 is read-only and answers: does NSScreen.visibleFrame actually
//  track the system Dock's footprint? Run dumpState(), then change Dock
//  size in System Settings, then run dumpState() again. If the "reserved
//  band" (frame minus visibleFrame) tracks the change, the prerequisite
//  holds and Phase 2 is worth trying.
//
//  Phase 2 attempts to set the Dock's CGS windows to alpha 0 — the goal is
//  to keep its reservation while erasing its pixels. Restore via
//  restoreAlpha() before quitting.
//

// Also gated on `!APP_STORE_SANDBOX`: the file references
// CGSPrivate.swift symbols (CGSGetWindowAlpha, CGSSetWindowAlpha,
// CGSMainConnectionID), which are themselves stripped from the MAS
// build. Without this guard a Debug MAS build would fail to compile.
#if DEBUG && !APP_STORE_SANDBOX

import AppKit
import Foundation

enum SkyLightSpaceReservationProbe {
    // MARK: Phase 1 — read-only diagnostics

    static func dumpState() {
        print("=== SkyLight space-reservation probe ===")
        print("timestamp: \(Date())")

        if let dockOrientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) {
            print("Dock orientation: \(dockOrientation)")
        } else {
            print("Dock orientation: <unset, defaults to bottom>")
        }
        if let dockTileSize = CFPreferencesCopyAppValue("tilesize" as CFString, "com.apple.dock" as CFString) {
            print("Dock tilesize: \(dockTileSize)")
        } else {
            print("Dock tilesize: <unset>")
        }
        if let dockAutohide = CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) {
            print("Dock autohide: \(dockAutohide)")
        } else {
            print("Dock autohide: <unset>")
        }

        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            let visible = screen.visibleFrame
            let reservedTop = frame.maxY - visible.maxY
            let reservedBottom = visible.minY - frame.minY
            let reservedLeft = visible.minX - frame.minX
            let reservedRight = frame.maxX - visible.maxX
            print("Screen[\(index)]: frame=\(frame) visibleFrame=\(visible)")
            print("  reserved bands → top=\(reservedTop) bottom=\(reservedBottom) left=\(reservedLeft) right=\(reservedRight)")
        }

        let dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?
            .processIdentifier
        print("Dock PID: \(dockPID.map(String.init) ?? "<not running>")")

        let dockWindows = self.dockWindows()
        print("Dock windows: \(dockWindows.count)")
        for window in dockWindows {
            let alpha = readAlpha(windowID: window.windowID)
            print("  windowID=\(window.windowID) layer=\(window.layer) bounds=\(window.bounds) name=\(window.name ?? "<unnamed>") alpha=\(alpha.map(String.init(describing:)) ?? "?")")
        }
        print("===")
    }

    // MARK: Phase 2 — SkyLight alpha suppression (mutating)

    /// Sets all Dock-owned windows to alpha 0. Returns the list of windows
    /// touched so the caller can pair this with a restore. After calling,
    /// re-run dumpState() to verify the reserved bands are unchanged.
    @discardableResult
    static func attemptAlphaSuppress() -> [DockWindow] {
        let windows = dockWindows()
        let connection = CGSMainConnectionID()
        for window in windows {
            let result = CGSSetWindowAlpha(connection, window.windowID, 0.0)
            print("CGSSetWindowAlpha(\(window.windowID), 0.0) → \(result)")
        }
        return windows
    }

    /// Restores alpha on the Dock-owned windows. Always run this before
    /// shipping anything else from this session.
    static func restoreAlpha() {
        let connection = CGSMainConnectionID()
        for window in dockWindows() {
            let result = CGSSetWindowAlpha(connection, window.windowID, 1.0)
            print("CGSSetWindowAlpha(\(window.windowID), 1.0) → \(result)")
        }
    }

    // MARK: Internals

    struct DockWindow {
        let windowID: Int
        let layer: Int
        let bounds: CGRect
        let name: String?
    }

    private static func dockWindows() -> [DockWindow] {
        guard let dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?
            .processIdentifier
        else {
            return []
        }

        let listOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(listOptions, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var results: [DockWindow] = []
        for info in infos {
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  pidNumber.int32Value == dockPID,
                  let windowNumber = info[kCGWindowNumber as String] as? NSNumber
            else { continue }

            let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
            let name = info[kCGWindowName as String] as? String
            var bounds = CGRect.zero
            if let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
               let parsed = CGRect(dictionaryRepresentation: boundsDict) {
                bounds = parsed
            }
            results.append(DockWindow(
                windowID: windowNumber.intValue,
                layer: layer,
                bounds: bounds,
                name: name
            ))
        }
        return results
    }

    private static func readAlpha(windowID: Int) -> Float? {
        var value: Float = -1
        let result = CGSGetWindowAlpha(CGSMainConnectionID(), windowID, &value)
        return result == 0 ? value : nil
    }
}

#endif
