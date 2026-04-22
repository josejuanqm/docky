//
//  PermissionsService.swift
//  Docky
//
//  Tracks the remaining macOS permissions Docky needs:
//    - .userFolders       → Full Disk Access for pinned folder previews
//    - .finderAutomation  → Finder Apple Events for Finder-backed actions
//
//  Required file-system access is granted through Full Disk Access (FDA),
//  probed via an attempted read of a TCC-protected directory
//  (inket/FullDiskAccess approach).
//

import AppKit
import ApplicationServices
import Combine

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

enum GrantMethod {
    case fullDiskAccess
    case automation
    case accessibility
}

enum Permission: String, CaseIterable, Identifiable {
    case userFolders
    case finderAutomation
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userFolders: return "Full Disk Access"
        case .finderAutomation: return "Finder Automation"
        case .accessibility: return "Accessibility"
        }
    }

    var explanation: String {
        switch self {
        case .userFolders:
            return "Grant Full Disk Access so Docky can preview recent items from folders pinned to the Dock, including protected locations like Downloads, Documents, and Desktop. No data leaves your Mac."
        case .finderAutomation:
            return "Docky can ask Finder to reveal files, open folders in Finder, open the Trash, and empty the Trash. macOS controls this separately from file access, and you can grant or revoke it at any time in Privacy & Security."
        case .accessibility:
            return "Accessibility access lets Docky click menu bar items for curated menuClick actions and inspect minimized windows so it can show and restore them beside the Trash. These actions are slower and more fragile than built-in actions, so Docky requests this only when needed."
        }
    }

    var systemSettingsURL: URL? {
        switch self {
        case .userFolders:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        case .finderAutomation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    var isRequiredAtLaunch: Bool {
        switch self {
        case .userFolders:
            return true
        case .finderAutomation:
            return false
        case .accessibility:
            return true
        }
    }
}

final class PermissionsService: ObservableObject {
    static let shared = PermissionsService()

    @Published private(set) var userFolders: PermissionStatus = .notDetermined
    @Published private(set) var userFoldersGrantMethod: GrantMethod?

    @Published private(set) var finderAutomation: PermissionStatus = .notDetermined
    @Published private(set) var finderAutomationGrantMethod: GrantMethod?

    @Published private(set) var accessibility: PermissionStatus = .notDetermined
    @Published private(set) var accessibilityGrantMethod: GrantMethod?

    private let dockBookmarkKey = "docky.dockPlistBookmark"
    private let userFoldersBookmarkKey = "docky.userFoldersBookmark"
    private let finderAutomationStatusKey = "docky.finderAutomationStatus"

    private init() {
        clearLegacyBookmarks()
        refresh()
    }

    // MARK: - Status

    func status(for permission: Permission) -> PermissionStatus {
        switch permission {
        case .userFolders: return userFolders
        case .finderAutomation: return finderAutomation
        case .accessibility: return accessibility
        }
    }

    var missingPermissions: [Permission] {
        Permission.allCases.filter { status(for: $0) != .granted }
    }

    var missingRequiredPermissions: [Permission] {
        Permission.allCases.filter { $0.isRequiredAtLaunch && status(for: $0) != .granted }
    }

    var setupPermissions: [Permission] {
        Permission.allCases.filter {
            if $0.isRequiredAtLaunch {
                return status(for: $0) != .granted
            }
            return status(for: $0) == .notDetermined
        }
    }

    var allGranted: Bool { missingPermissions.isEmpty }

    var allRequiredGranted: Bool { missingRequiredPermissions.isEmpty }

    var setupComplete: Bool { setupPermissions.isEmpty }

    func refresh() {
        let fdaGranted = checkFullDiskAccess()
        refreshUserFolders(fdaGranted: fdaGranted)
        refreshFinderAutomation()
        refreshAccessibility()
    }

    // MARK: - Grant actions

    func openSystemSettings(for permission: Permission) {
        guard let url = permission.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func requestAutomationPermission(for permission: Permission) async -> Bool {
        switch permission {
        case .finderAutomation:
            return await AppleScriptService.shared.requestFinderAutomationPermission()
        case .accessibility:
            return requestAccessibilityPermission(prompt: true)
        case .userFolders:
            return false
        }
    }

    func clearAutomationStatus(for permission: Permission) {
        guard permission == .finderAutomation else { return }
        UserDefaults.standard.removeObject(forKey: finderAutomationStatusKey)
        refreshFinderAutomation()
    }

    @discardableResult
    func requestAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        refreshAccessibility()
        return granted
    }

    func presentPermissionAlert(for permission: Permission, actionTitle: String) {
        let alert = NSAlert()
        alert.messageText = permission.title + " is required"
        alert.informativeText = "Allow Docky in Privacy & Security so it can perform \(actionTitle.lowercased())."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings(for: permission)
        }
    }

    // MARK: - User folders permission

    private func refreshUserFolders(fdaGranted: Bool) {
        if fdaGranted {
            userFoldersGrantMethod = .fullDiskAccess
            userFolders = .granted
            return
        }
        userFoldersGrantMethod = nil
        userFolders = .denied
    }

    // MARK: - Finder automation permission

    func updateFinderAutomation(status: PermissionStatus) {
        switch status {
        case .granted:
            UserDefaults.standard.set("granted", forKey: finderAutomationStatusKey)
            finderAutomationGrantMethod = .automation
        case .denied:
            UserDefaults.standard.set("denied", forKey: finderAutomationStatusKey)
            finderAutomationGrantMethod = nil
        case .notDetermined:
            UserDefaults.standard.removeObject(forKey: finderAutomationStatusKey)
            finderAutomationGrantMethod = nil
        }
        finderAutomation = status
    }

    private func refreshFinderAutomation() {
        switch UserDefaults.standard.string(forKey: finderAutomationStatusKey) {
        case "granted":
            finderAutomation = .granted
            finderAutomationGrantMethod = .automation
        case "denied":
            finderAutomation = .denied
            finderAutomationGrantMethod = nil
        default:
            finderAutomation = .notDetermined
            finderAutomationGrantMethod = nil
        }
    }

    private func refreshAccessibility() {
        let granted = AXIsProcessTrusted()
        accessibility = granted ? .granted : .denied
        accessibilityGrantMethod = granted ? .accessibility : nil
    }

    // MARK: - Full Disk Access probe

    private func checkFullDiskAccess() -> Bool {
        let probePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.stocks")
            .path
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: probePath)
            return true
        } catch {
            return false
        }
    }

    private func clearLegacyBookmarks() {
        UserDefaults.standard.removeObject(forKey: dockBookmarkKey)
        UserDefaults.standard.removeObject(forKey: userFoldersBookmarkKey)
    }
}
