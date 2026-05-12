//
//  AppleScriptService.swift
//  Docky
//
//  Finder-backed actions that are awkward or unavailable via NSWorkspace
//  alone. Scripts are executed directly from source at runtime.
//

import AppKit
import Foundation

final class AppleScriptService {
    static let shared = AppleScriptService()

    private init() {}

    @discardableResult
    func requestFinderAutomationPermission() async -> Bool {
        await runFinderScript(.permissionProbe)
    }

    @discardableResult
    func requestSystemEventsAutomationPermission() async -> Bool {
        await runSystemEventsPermissionProbe()
    }

    func executeDescriptor(source: String) throws -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptServiceError.compilationFailed
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let error = scriptError(from: errorInfo) {
            throw error
        }
        return result
    }

    @discardableResult
    func runCatalogScript(
        source: String,
        permissionRequirements: [Permission],
        actionTitle: String,
        targetApp: String?
    ) async -> Result<Void, AppleScriptServiceError> {
        do {
            try execute(source: source)
            permissionRequirements.forEach { permission in
                updateGrantedPermission(permission)
            }
            return .success(())
        } catch let error as AppleScriptServiceError {
            handleCatalogError(error, actionTitle: actionTitle, targetApp: targetApp, permissionRequirements: permissionRequirements)
            return .failure(error)
        } catch {
            let wrapped = AppleScriptServiceError.executionFailed(error.localizedDescription)
            handleCatalogError(wrapped, actionTitle: actionTitle, targetApp: targetApp, permissionRequirements: permissionRequirements)
            return .failure(wrapped)
        }
    }

    @discardableResult
    func runMenuClickScript(
        targetApp: String,
        processName: String,
        path: [String],
        requiresFrontmost: Bool,
        holdOption: Bool,
        actionTitle: String
    ) async -> Bool {
        let script = makeMenuClickScript(
            targetApp: targetApp,
            processName: processName,
            path: path,
            requiresFrontmost: requiresFrontmost,
            holdOption: holdOption
        )
        switch await runCatalogScript(
            source: script,
            permissionRequirements: [.accessibility, .systemEventsAutomation],
            actionTitle: actionTitle,
            targetApp: targetApp
        ) {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    @discardableResult
    func revealInFinder(_ url: URL) async -> Bool {
        await runFinderScript(.reveal(url))
    }

    @discardableResult
    func openFinderWindow(for url: URL) async -> Bool {
        await runFinderScript(.openFolder(url))
    }

    @discardableResult
    func openTrash() async -> Bool {
        await runFinderScript(.openTrash)
    }

    @discardableResult
    func emptyTrash() async -> Bool {
        await runFinderScript(.emptyTrash)
    }

    private func runFinderScript(_ command: FinderCommand) async -> Bool {
        do {
            try await MainActor.run { try execute(source: command.source) }
            PermissionsService.shared.updateFinderAutomation(status: .granted)
            return true
        } catch let error as AppleScriptServiceError {
            handle(error)
            return false
        } catch {
            handle(.executionFailed(error.localizedDescription))
            return false
        }
    }

    private func runSystemEventsPermissionProbe() async -> Bool {
        do {
            try await MainActor.run { try execute(source: SystemEventsCommand.permissionProbe.source) }
            PermissionsService.shared.updateSystemEventsAutomation(status: .granted)
            return true
        } catch let error as AppleScriptServiceError {
            handleSystemEventsPermissionProbe(error)
            return false
        } catch {
            handleSystemEventsPermissionProbe(.executionFailed(error.localizedDescription))
            return false
        }
    }

    private func execute(source: String) throws {
        _ = try executeDescriptor(source: source)
    }

    private func scriptError(from errorInfo: NSDictionary?) -> AppleScriptServiceError? {
        guard let errorInfo else { return nil }
        let number = errorInfo[NSAppleScript.errorNumber] as? Int
        let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "AppleScript execution failed."

        if number == -1743 {
            return .permissionDenied
        }
        if number == 1002 {
            return .accessibilityDenied
        }
        return .executionFailed(message)
    }

    private func handle(_ error: AppleScriptServiceError) {
        switch error {
        case .permissionDenied:
            PermissionsService.shared.updateFinderAutomation(status: .denied)
            presentAlert(
                title: "Finder automation wasn’t allowed",
                body: "Allow Docky to control Finder in Privacy & Security > Automation, or use the Automation (Finder) row in Docky Settings to request access again."
            )
        case .accessibilityDenied:
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "Finder action")
        case .compilationFailed:
            presentAlert(
                title: "Finder action failed",
                body: "Docky couldn't prepare the AppleScript needed for this Finder action."
            )
        case .executionFailed(let message):
            presentAlert(
                title: "Finder action failed",
                body: message
            )
        }
    }

    private func handleCatalogError(
        _ error: AppleScriptServiceError,
        actionTitle: String,
        targetApp: String?,
        permissionRequirements: [Permission]
    ) {
        switch error {
        case .permissionDenied:
            permissionRequirements.forEach { permission in
                switch permission {
                case .finderAutomation:
                    PermissionsService.shared.updateFinderAutomation(status: .denied)
                case .systemEventsAutomation:
                    PermissionsService.shared.updateSystemEventsAutomation(status: .denied)
                case .accessibility:
                    PermissionsService.shared.refresh()
                case .userFolders, .screenCapture, .location:
                    break
                }
            }

            if permissionRequirements.contains(.finderAutomation) {
                presentAutomationAlert(
                    targetApp: targetApp ?? "the target app",
                    actionTitle: actionTitle,
                    includesSystemEvents: false
                )
            } else if let targetApp {
                presentAutomationAlert(
                    targetApp: targetApp,
                    actionTitle: actionTitle,
                    includesSystemEvents: permissionRequirements.contains(.accessibility)
                )
            } else {
                presentAlert(
                    title: "Script action wasn’t allowed",
                    body: "macOS blocked \(actionTitle.lowercased())."
                )
            }
        case .accessibilityDenied:
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: actionTitle)
        case .compilationFailed:
            presentAlert(
                title: "Script action failed",
                body: "Docky couldn't prepare the AppleScript needed for \(actionTitle.lowercased())."
            )
        case .executionFailed(let message):
            presentAlert(
                title: "Script action failed",
                body: message
            )
        }
    }

    private func updateGrantedPermission(_ permission: Permission) {
        switch permission {
        case .finderAutomation:
            PermissionsService.shared.updateFinderAutomation(status: .granted)
        case .systemEventsAutomation:
            PermissionsService.shared.updateSystemEventsAutomation(status: .granted)
        case .accessibility:
            PermissionsService.shared.refresh()
        case .userFolders, .screenCapture, .location:
            break
        }
    }

    private func presentAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentAutomationAlert(
        targetApp: String,
        actionTitle: String,
        includesSystemEvents: Bool
    ) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Automation wasn’t allowed")
        let appName = displayName(for: targetApp)
        if includesSystemEvents {
            alert.informativeText = String(
                format: String(localized: "Allow Docky to control System Events and %1$@ in Privacy & Security > Automation, then try %2$@ again."),
                appName,
                actionTitle.lowercased()
            )
        } else {
            alert.informativeText = String(
                format: String(localized: "Allow Docky to control %1$@ in Privacy & Security > Automation, then try %2$@ again."),
                appName,
                actionTitle.lowercased()
            )
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionsService.shared.openSystemSettings(for: .finderAutomation)
        }
    }

    private func handleSystemEventsPermissionProbe(_ error: AppleScriptServiceError) {
        switch error {
        case .permissionDenied:
            PermissionsService.shared.updateSystemEventsAutomation(status: .denied)
            presentAlert(
                title: "System Events automation wasn’t allowed",
                body: "Allow Docky to control System Events in Privacy & Security > Automation, or use the Automation (System Events) row in Docky Settings to request access again."
            )
        case .accessibilityDenied:
            PermissionsService.shared.presentPermissionAlert(for: .accessibility, actionTitle: "Request System Events Access")
        case .compilationFailed:
            presentAlert(
                title: "System Events action failed",
                body: "Docky couldn't prepare the AppleScript needed to request System Events automation."
            )
        case .executionFailed(let message):
            presentAlert(
                title: "System Events action failed",
                body: message
            )
        }
    }

    private func displayName(for bundleIdentifier: String) -> String {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }

        if let bundle = Bundle(url: appURL) {
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !displayName.isEmpty {
                return displayName
            }
            if let name = bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String,
               !name.isEmpty {
                return name
            }
        }

        return appURL.deletingPathExtension().lastPathComponent
    }
}

private enum FinderCommand {
    case permissionProbe
    case reveal(URL)
    case openFolder(URL)
    case openTrash
    case emptyTrash

    var source: String {
        switch self {
        case .permissionProbe:
            return """
            tell application id \"com.apple.finder\" to launch
            tell application id \"com.apple.finder\"
                count Finder windows
            end tell
            """
        case .reveal(let url):
            return """
            tell application id \"com.apple.finder\" to launch
            tell application id \"com.apple.finder\"
                activate
                reveal POSIX file "\(escapedPOSIXPath(url))"
            end tell
            """
        case .openFolder(let url):
            return """
            tell application id \"com.apple.finder\" to launch
            tell application id \"com.apple.finder\"
                activate
                open POSIX file "\(escapedPOSIXPath(url))"
            end tell
            """
        case .openTrash:
            return """
            tell application id \"com.apple.finder\" to launch
            tell application id \"com.apple.finder\"
                activate
                open trash
            end tell
            """
        case .emptyTrash:
            return """
            tell application id \"com.apple.finder\" to launch
            tell application id \"com.apple.finder\"
                activate
                empty the trash
            end tell
            """
        }
    }
}

enum AppleScriptServiceError: Error {
    case permissionDenied
    case accessibilityDenied
    case compilationFailed
    case executionFailed(String)
}

private enum SystemEventsCommand {
    case permissionProbe

    var source: String {
        switch self {
        case .permissionProbe:
            return "tell application id \"com.apple.systemevents\" to get name"
        }
    }
}

private func escapedPOSIXPath(_ url: URL) -> String {
    url.path
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

private extension AppleScriptService {
    func makeMenuClickScript(
        targetApp: String,
        processName: String,
        path: [String],
        requiresFrontmost: Bool,
        holdOption: Bool
    ) -> String {
        let quotedPath = path.map { "\"\($0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"" }
            .joined(separator: ", ")
        let activationScript = requiresFrontmost
            ? "tell application id \"\(targetApp)\" to activate\n    delay 0.15\n"
            : ""
        let optionDown = holdOption ? "key down option\n                delay 0.05\n" : ""
        let optionUp = holdOption ? "key up option\n" : ""

        return """
        \(activationScript)tell application id "com.apple.systemevents"
            tell application process "\(processName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))"
                set menuPath to {\(quotedPath)}
                set currentMenuBar to menu bar 1
                set currentElement to missing value
                repeat with itemIndex from 1 to count of menuPath
                    set itemTitle to item itemIndex of menuPath
                    if itemIndex is 1 then
                        set currentElement to first menu bar item of currentMenuBar whose title is itemTitle
                        \(optionDown)click currentElement
                    else if itemIndex is less than count of menuPath then
                        set currentElement to first menu item of menu 1 of currentElement whose title is itemTitle
                        click currentElement
                    else
                        set currentElement to first menu item of menu 1 of currentElement whose title is itemTitle
                        click currentElement
                    end if
                end repeat
                \(optionUp)end tell
        end tell
        """
    }
}
