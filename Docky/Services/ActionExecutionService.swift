//
//  ActionExecutionService.swift
//  Docky
//

import AppKit
import Foundation

enum BuiltinAction: String {
    case openApp
    case showAllWindows
    case togglePinnedApp
    case showAppInFinder
    case hideApp
    case quitApp
    case openFolderInFinder
    case revealFolderInFinder
    case openTrash
    case emptyTrash
}

final class ActionExecutionService {
    static let shared = ActionExecutionService()

    private init() {}

    @discardableResult
    func perform(action: CatalogActionDefinition, context: CatalogActionContext) async -> Bool {
        guard preflightPermissions(for: action) else {
            return false
        }

        switch action.kind {
        case .builtin:
            guard let builtinID = action.builtinIdentifier, let builtin = BuiltinAction(rawValue: builtinID) else {
                return false
            }
            return await performBuiltinAction(builtin, context: context)
        case .applescript:
            return await performAppleScriptAction(action, context: context)
        case .menuClick:
            return await MenuClickService.shared.perform(action: action, context: context)
        }
    }

    private func performBuiltinAction(_ action: BuiltinAction, context: CatalogActionContext) async -> Bool {
        switch action {
        case .openApp:
            guard let bundleIdentifier = context.bundleIdentifier else { return false }
            WorkspaceService.shared.activateOrOpen(bundleIdentifier: bundleIdentifier)
            return true
        case .showAllWindows:
            guard let bundleIdentifier = context.bundleIdentifier else { return false }
            WorkspaceService.shared.showAllWindows(bundleIdentifier: bundleIdentifier)
            return true
        case .togglePinnedApp:
            guard let bundleIdentifier = context.bundleIdentifier else { return false }
            return TileStore.shared.setPinnedApp(bundleIdentifier: bundleIdentifier, pinned: !context.isPinned)
        case .showAppInFinder:
            guard let bundleIdentifier = context.bundleIdentifier else { return false }
            WorkspaceService.shared.revealApplicationInFinder(bundleIdentifier: bundleIdentifier)
            return true
        case .hideApp:
            guard let bundleIdentifier = context.bundleIdentifier else { return false }
            WorkspaceService.shared.hide(bundleIdentifier: bundleIdentifier)
            return true
        case .quitApp:
            guard let bundleIdentifier = context.bundleIdentifier else { return false }
            WorkspaceService.shared.quit(bundleIdentifier: bundleIdentifier, force: context.modifierFlags.contains(.option))
            return true
        case .openFolderInFinder:
            guard case .folder(let folder) = context.tile.content else { return false }
            return await AppleScriptService.shared.openFinderWindow(for: folder.url)
        case .revealFolderInFinder:
            guard case .folder(let folder) = context.tile.content else { return false }
            return await AppleScriptService.shared.revealInFinder(folder.url)
        case .openTrash:
            return await AppleScriptService.shared.openTrash()
        case .emptyTrash:
            return await AppleScriptService.shared.emptyTrash()
        }
    }

    private func performAppleScriptAction(_ action: CatalogActionDefinition, context: CatalogActionContext) async -> Bool {
        guard let source = action.script else { return false }
        let resolvedSource = resolveScript(source, inputs: action.inputs, context: context)
        switch await AppleScriptService.shared.runCatalogScript(
            source: resolvedSource,
            permissionRequirements: action.permissions.map(\.permission),
            actionTitle: action.title,
            targetApp: action.targetApp
        ) {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    private func resolveScript(_ source: String, inputs: [CatalogInputKey], context: CatalogActionContext) -> String {
        var resolved = source
        for input in inputs {
            let token = "{{\(input.rawValue)}}"
            let value = context.stringValue(for: input) ?? ""
            resolved = resolved.replacingOccurrences(of: token, with: escapedAppleScriptString(value))
        }
        return resolved
    }

    private func preflightPermissions(for action: CatalogActionDefinition) -> Bool {
        for requirement in action.permissions {
            let permission = requirement.permission
            if permission == .finderAutomation {
                continue
            }
            if PermissionsService.shared.status(for: permission) == .granted {
                continue
            }

            switch permission {
            case .accessibility:
                PermissionsService.shared.requestAccessibilityPermission(prompt: true)
            case .finderAutomation, .userFolders, .screenCapture, .location, .systemEventsAutomation, .calendar, .reminders:
                break
            }

            if PermissionsService.shared.status(for: permission) != .granted {
                PermissionsService.shared.presentPermissionAlert(for: permission, actionTitle: action.title)
                return false
            }
        }

        return true
    }
}

private func escapedAppleScriptString(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
