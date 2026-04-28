//
//  SystemDockVisibilityService.swift
//  Docky
//
//  Hides the macOS Dock by writing to com.apple.dock preferences
//  (autohide on, large delay, instant animation, no bouncing, no launch
//  animation). The user's previous values are snapshotted before the first
//  overwrite so they can be restored when the preference is turned off or
//  when Docky quits.
//

import AppKit
import Foundation

final class SystemDockVisibilityService {
    static let shared = SystemDockVisibilityService()

    private static let dockDomain = "com.apple.dock" as CFString
    private static let snapshotKey = "docky.systemDockVisibilitySnapshot"
    private static let snapshotNullMarker = "__docky_null__"

    private static let managedKeys: [String] = [
        "orientation",
        "autohide",
        "autohide-delay",
        "autohide-time-modifier",
        "no-bouncing",
        "launchanim"
    ]

    private static let hiddenValues: [String: CFPropertyList] = [
        "autohide": true as CFBoolean,
        "autohide-delay": 1000.0 as CFNumber,
        "autohide-time-modifier": 0.0 as CFNumber,
        "no-bouncing": true as CFBoolean,
        "launchanim": false as CFBoolean
    ]

    private let defaults = UserDefaults.standard

    private init() {}

    var hasSnapshot: Bool {
        defaults.dictionary(forKey: Self.snapshotKey) != nil
    }

    func hide() {
        if !hasSnapshot {
            captureSnapshot()
        }
        applyHiddenValues()
        restartDock()
    }

    func setOrientation(_ orientation: DockSettingsService.Orientation) {
        CFPreferencesSetAppValue("orientation" as CFString, orientation.rawValue as CFString, Self.dockDomain)
        CFPreferencesAppSynchronize(Self.dockDomain)
        restartDock()
    }

    func restore() {
        if let snapshot = defaults.dictionary(forKey: Self.snapshotKey) {
            applySnapshot(snapshot)
            defaults.removeObject(forKey: Self.snapshotKey)
        } else {
            clearManagedKeys()
        }
        restartDock()
    }

    private func captureSnapshot() {
        var snapshot: [String: Any] = [:]
        for key in Self.managedKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, Self.dockDomain) {
                snapshot[key] = value
            } else {
                snapshot[key] = Self.snapshotNullMarker
            }
        }
        defaults.set(snapshot, forKey: Self.snapshotKey)
    }

    private func applyHiddenValues() {
        for (key, value) in Self.hiddenValues {
            CFPreferencesSetAppValue(key as CFString, value, Self.dockDomain)
        }
        CFPreferencesAppSynchronize(Self.dockDomain)
    }

    private func applySnapshot(_ snapshot: [String: Any]) {
        for key in Self.managedKeys {
            let stored = snapshot[key]
            if let marker = stored as? String, marker == Self.snapshotNullMarker {
                CFPreferencesSetAppValue(key as CFString, nil, Self.dockDomain)
            } else if let stored = stored as CFPropertyList? {
                CFPreferencesSetAppValue(key as CFString, stored, Self.dockDomain)
            } else {
                CFPreferencesSetAppValue(key as CFString, nil, Self.dockDomain)
            }
        }
        CFPreferencesAppSynchronize(Self.dockDomain)
    }

    private func clearManagedKeys() {
        for key in Self.managedKeys {
            CFPreferencesSetAppValue(key as CFString, nil, Self.dockDomain)
        }
        CFPreferencesAppSynchronize(Self.dockDomain)
    }

    private func restartDock() {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .forEach { $0.forceTerminate() }
    }
}
