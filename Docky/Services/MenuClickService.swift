//
//  MenuClickService.swift
//  Docky
//

import AppKit
import Foundation

final class MenuClickService {
    static let shared = MenuClickService()

    private init() {}

    @discardableResult
    func perform(action: CatalogActionDefinition, context: CatalogActionContext) async -> Bool {
        guard let targetApp = action.targetApp,
              let path = action.path,
              !path.isEmpty else {
            return false
        }

        if action.requiresFrontmost {
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: targetApp)
            try? await Task.sleep(for: .milliseconds(250))
        }

        let processName = runningApplicationName(for: targetApp)
        guard let processName else {
            presentUnavailableAlert(targetApp: targetApp, actionTitle: action.title)
            return false
        }

        if PermissionsService.shared.status(for: .accessibility) != .granted {
            PermissionsService.shared.requestAccessibilityPermission(prompt: true)
        }

        guard PermissionsService.shared.status(for: .accessibility) == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: action.title)
            return false
        }

        if PermissionsService.shared.status(for: .systemEventsAutomation) != .granted {
            _ = await PermissionsService.shared.requestPermission(for: .systemEventsAutomation)
        }

        guard PermissionsService.shared.status(for: .systemEventsAutomation) == .granted else {
            PermissionsService.shared.presentPermissionAlert(for: .systemEventsAutomation, actionTitle: action.title)
            return false
        }

        return await AppleScriptService.shared.runMenuClickScript(
            targetApp: targetApp,
            processName: processName,
            path: path,
            requiresFrontmost: action.requiresFrontmost,
            holdOption: action.holdOption,
            actionTitle: action.title
        )
    }

    private func runningApplicationName(for bundleIdentifier: String) -> String? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           let localizedName = app.localizedName,
           !localizedName.isEmpty {
            return localizedName
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func presentUnavailableAlert(targetApp: String, actionTitle: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Menu action unavailable")
        alert.informativeText = String(localized: "Docky couldn't find a running process for \(targetApp) to perform \(actionTitle).")
        alert.alertStyle = .warning
        alert.runModal()
    }
}
