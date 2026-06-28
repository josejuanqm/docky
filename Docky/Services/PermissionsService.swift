//
//  PermissionsService.swift
//  Docky
//
//  Tracks the remaining macOS permissions Docky needs:
//    - .userFolders       → Full Disk Access for pinned folder previews
//    - .finderAutomation       → Finder Apple Events for Finder-backed actions
//    - .accessibility          → inspect and restore minimized windows
//    - .systemEventsAutomation → System Events Apple Events for menu-click actions
//    - .screenCapture     → minimized window previews
//
//  Required file-system access is granted through Full Disk Access (FDA),
//  probed via an attempted read of a TCC-protected directory
//  (inket/FullDiskAccess approach).
//

import AppKit
import ApplicationServices
import Combine
import CoreLocation

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

enum GrantMethod {
    case fullDiskAccess
    case automation
    case accessibility
    case screenCapture
    case location
}

enum Permission: String, CaseIterable, Identifiable {
    case userFolders
    case finderAutomation
    case accessibility
    case systemEventsAutomation
    case screenCapture
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userFolders: return String(localized: "Full Disk Access")
        case .finderAutomation: return String(localized: "Automation (Finder)")
        case .accessibility: return String(localized: "Accessibility")
        case .systemEventsAutomation: return String(localized: "Automation (System Events)")
        case .screenCapture: return String(localized: "Screen Recording")
        case .location: return String(localized: "Location")
        }
    }

    var explanation: String {
        switch self {
        case .userFolders:
            return String(localized: "Grant Full Disk Access so Docky can preview recent items from folders pinned to the Dock, including protected locations like Downloads, Documents, and Desktop. No data leaves your Mac.")
        case .finderAutomation:
            return String(localized: "Docky uses Finder automation for reveal-in-Finder, open-folder, and Trash actions. macOS grants this separately from Full Disk Access, and you can request it here without waiting for the first Finder action to fail.")
        case .accessibility:
            return String(localized: "Accessibility access lets Docky click menu bar items for curated menuClick actions, inspect app windows for Dock-like reopen behavior and window menus, and restore minimized windows beside the Trash. These actions are slower and more fragile than built-in actions, so Docky requests this only when needed.")
        case .systemEventsAutomation:
            return String(localized: "Docky uses System Events automation for curated menuClick actions. Requesting it here lets Docky click supported app menus without waiting for the first action to trigger a macOS prompt. Menu-click actions still require Accessibility too.")
        case .screenCapture:
            return String(localized: "Grant Screen Recording so Docky can show thumbnail previews for minimized windows. Docky only captures the minimized window itself for its dock tile, and nothing leaves your Mac. macOS may require quitting and reopening Docky after you allow this.")
        case .location:
            return String(localized: "Grant location access so Docky can show local weather in the Weather widget. Your location is used on-device to fetch the forecast and is not stored by Docky.")
        }
    }

    var systemSettingsURL: URL? {
        switch self {
        case .userFolders:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        case .finderAutomation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .systemEventsAutomation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenCapture:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .location:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        }
    }

    var isRequiredAtLaunch: Bool {
        switch self {
        case .userFolders:
            return true
        case .finderAutomation:
            return false
        case .systemEventsAutomation:
            return false
        case .accessibility:
            return true
        case .screenCapture:
            return true
        case .location:
            return false
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

    @Published private(set) var systemEventsAutomation: PermissionStatus = .notDetermined
    @Published private(set) var systemEventsAutomationGrantMethod: GrantMethod?

    @Published private(set) var screenCapture: PermissionStatus = .notDetermined
    @Published private(set) var screenCaptureGrantMethod: GrantMethod?

    @Published private(set) var location: PermissionStatus = .notDetermined
    @Published private(set) var locationGrantMethod: GrantMethod?

    private let dockBookmarkKey = "docky.dockPlistBookmark"
    private let userFoldersBookmarkKey = "docky.userFoldersBookmark"
    private let finderAutomationStatusKey = "docky.finderAutomationStatus"
    private let systemEventsAutomationStatusKey = "docky.systemEventsAutomationStatus"
    private let initialOnboardingCompletedKey = "docky.initialOnboardingCompleted"
    private let skippedPermissionsKey = "docky.skippedPermissions"

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
        case .systemEventsAutomation: return systemEventsAutomation
        case .screenCapture: return screenCapture
        case .location: return location
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
            if hasSkippedPermission($0) {
                return false
            }

            if $0.isRequiredAtLaunch {
                return status(for: $0) != .granted
            }

            if hasCompletedInitialOnboarding {
                return false
            }

            return status(for: $0) == .notDetermined
        }
    }

    var allGranted: Bool { missingPermissions.isEmpty }

    var allRequiredGranted: Bool { missingRequiredPermissions.isEmpty }

    var setupComplete: Bool { setupPermissions.isEmpty }

    var hasCompletedInitialOnboarding: Bool {
        UserDefaults.standard.bool(forKey: initialOnboardingCompletedKey)
    }

    func refresh() {
        let fdaGranted = checkFullDiskAccess()
        refreshUserFolders(fdaGranted: fdaGranted)
        refreshFinderAutomation()
        refreshAccessibility()
        refreshSystemEventsAutomation()
        refreshScreenCapture()
        refreshLocation()
    }

    func markInitialOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: initialOnboardingCompletedKey)
    }

    func markPermissionSkipped(_ permission: Permission) {
        var skippedPermissions = skippedPermissionIDs
        skippedPermissions.insert(permission.rawValue)
        UserDefaults.standard.set(Array(skippedPermissions), forKey: skippedPermissionsKey)
    }

    func hasSkippedPermission(_ permission: Permission) -> Bool {
        skippedPermissionIDs.contains(permission.rawValue)
    }

    // MARK: - Grant actions

    private var skippedPermissionIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: skippedPermissionsKey) ?? [])
    }

    func openSystemSettings(for permission: Permission) {
        guard let url = permission.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func requestPermission(for permission: Permission) async -> Bool {
        switch permission {
        case .finderAutomation:
            return await AppleScriptService.shared.requestFinderAutomationPermission()
        case .accessibility:
            return requestAccessibilityPermission(prompt: true)
        case .systemEventsAutomation:
            return await AppleScriptService.shared.requestSystemEventsAutomationPermission()
        case .screenCapture:
            return requestScreenCapturePermission()
        case .location:
            return await WeatherService.shared.requestLocationPermission()
        case .userFolders:
            return false
        }
    }

    func clearAutomationStatus(for permission: Permission) {
        switch permission {
        case .finderAutomation:
            UserDefaults.standard.removeObject(forKey: finderAutomationStatusKey)
            refreshFinderAutomation()
        case .systemEventsAutomation:
            UserDefaults.standard.removeObject(forKey: systemEventsAutomationStatusKey)
            refreshSystemEventsAutomation()
        case .userFolders, .accessibility, .screenCapture, .location:
            break
        }
    }

    @discardableResult
    func requestAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        refreshAccessibility()
        return granted
    }

    @discardableResult
    func requestScreenCapturePermission() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        refreshScreenCapture()
        return granted
    }

    func presentPermissionAlert(for permission: Permission, actionTitle: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "\(permission.title) is required")
        alert.informativeText = String(localized: "Allow Docky in Privacy & Security so it can perform \(actionTitle.lowercased()).")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
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

    func updateSystemEventsAutomation(status: PermissionStatus) {
        switch status {
        case .granted:
            UserDefaults.standard.set("granted", forKey: systemEventsAutomationStatusKey)
            systemEventsAutomationGrantMethod = .automation
        case .denied:
            UserDefaults.standard.set("denied", forKey: systemEventsAutomationStatusKey)
            systemEventsAutomationGrantMethod = nil
        case .notDetermined:
            UserDefaults.standard.removeObject(forKey: systemEventsAutomationStatusKey)
            systemEventsAutomationGrantMethod = nil
        }
        systemEventsAutomation = status
    }

    private func refreshSystemEventsAutomation() {
        switch UserDefaults.standard.string(forKey: systemEventsAutomationStatusKey) {
        case "granted":
            systemEventsAutomation = .granted
            systemEventsAutomationGrantMethod = .automation
        case "denied":
            systemEventsAutomation = .denied
            systemEventsAutomationGrantMethod = nil
        default:
            systemEventsAutomation = .notDetermined
            systemEventsAutomationGrantMethod = nil
        }
    }

    private func refreshAccessibility() {
        let granted = AXIsProcessTrusted()
        accessibility = granted ? .granted : .denied
        accessibilityGrantMethod = granted ? .accessibility : nil
    }

    private func refreshScreenCapture() {
        let granted = CGPreflightScreenCaptureAccess()
        screenCapture = granted ? .granted : .denied
        screenCaptureGrantMethod = granted ? .screenCapture : nil
    }

    private func refreshLocation() {
        WeatherService.shared.refreshAuthorizationStatus()

        if WeatherService.shared.hasLocationAuthorization {
            location = .granted
            locationGrantMethod = .location
            return
        }

        switch WeatherService.shared.authorizationStatus {
        case .notDetermined:
            location = .notDetermined
            locationGrantMethod = nil
        case .denied, .restricted:
            location = .denied
            locationGrantMethod = nil
        case .authorizedAlways:
            location = .granted
            locationGrantMethod = .location
        @unknown default:
            location = .denied
            locationGrantMethod = nil
        }
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
