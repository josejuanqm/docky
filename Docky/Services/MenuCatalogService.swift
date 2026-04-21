//
//  MenuCatalogService.swift
//  Docky
//

import AppKit
import Combine
import Foundation

final class MenuCatalogService: ObservableObject {
    static let shared = MenuCatalogService()

    @Published private(set) var packageSummaries: [CatalogPackageSummary] = []
    @Published private(set) var diagnostics: [String] = []

    private var actionsByID: [String: CatalogActionDefinition] = [:]
    private var menusByTileType: [MenuTileType: CatalogMenuDefinition] = [:]
    private let decoder = JSONDecoder()

    private init() {
        reload()
    }

    func reload() {
        diagnostics = []
        packageSummaries = []
        actionsByID = [:]
        menusByTileType = [:]

        do {
            let actionsDocument: CatalogActionsDocument = try loadJSON(named: "actions", subdirectory: "MenuCatalog")
            let menusDocument: CatalogMenusDocument = try loadJSON(named: "menus", subdirectory: "MenuCatalog")
            apply(actionsDocument: actionsDocument, menusDocument: menusDocument)
        } catch {
            diagnostics = ["Failed to load menu catalog: \(error.localizedDescription)"]
            logDiagnostics()
        }
    }

    func contextActions(for tile: Tile, modifierFlags: NSEvent.ModifierFlags) -> [ContextAction]? {
        switch tile.content {
        case .app, .folder, .trash:
            break
        case .widget, .smartStack, .spacer, .divider:
            return nil
        }

        let tileType = tileType(for: tile)
        guard let menu = menusByTileType[tileType] else {
            record("Missing menu definition for tile type '\(tileType.rawValue)'.")
            return nil
        }

        let context = makeContext(for: tile, modifierFlags: modifierFlags)
        return buildMenuItems(from: menu.items, context: context)
    }

    private func apply(actionsDocument: CatalogActionsDocument, menusDocument: CatalogMenusDocument) {
        var localDiagnostics: [String] = []
        var resolvedActions: [String: CatalogActionDefinition] = [:]

        for package in actionsDocument.packages {
            packageSummaries.append(CatalogPackageSummary(
                id: package.id,
                title: package.title,
                author: package.author,
                version: package.version,
                reviewStatus: package.reviewStatus,
                description: package.description,
                actionCount: package.actions.count
            ))

            for action in package.actions {
                if resolvedActions[action.id] != nil {
                    localDiagnostics.append("Duplicate action id '\(action.id)' in package '\(package.id)'.")
                    continue
                }

                if let error = validate(action: action) {
                    localDiagnostics.append("Action '\(action.id)' rejected: \(error)")
                    continue
                }

                resolvedActions[action.id] = action
            }
        }

        var resolvedMenus: [MenuTileType: CatalogMenuDefinition] = [:]
        for menu in menusDocument.menus {
            if resolvedMenus[menu.tileType] != nil {
                localDiagnostics.append("Duplicate menu definition for tile type '\(menu.tileType.rawValue)'.")
                continue
            }

            if let error = validate(menu: menu, actionsByID: resolvedActions) {
                localDiagnostics.append("Menu '\(menu.tileType.rawValue)' rejected: \(error)")
                continue
            }

            resolvedMenus[menu.tileType] = menu
        }

        actionsByID = resolvedActions
        menusByTileType = resolvedMenus
        diagnostics = localDiagnostics
        logDiagnostics()
    }

    private func loadJSON<T: Decodable>(named name: String, subdirectory: String) throws -> T {
        let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: "json")
        guard let url else {
            throw NSError(domain: "MenuCatalogService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing resource \(subdirectory)/\(name).json"])
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    private func validate(action: CatalogActionDefinition) -> String? {
        switch action.kind {
        case .builtin:
            guard let builtinIdentifier = action.builtinIdentifier, BuiltinAction(rawValue: builtinIdentifier) != nil else {
                return "unknown builtin identifier"
            }
        case .applescript:
            guard let targetApp = action.targetApp, !targetApp.isEmpty else {
                return "AppleScript actions require targetApp"
            }
            guard let script = action.script, !script.isEmpty else {
                return "AppleScript actions require script"
            }
            let placeholders = Set(script.placeholders)
            let declaredInputs = Set(action.inputs.map(\.rawValue))
            let unknownPlaceholders = placeholders.subtracting(declaredInputs)
            if !unknownPlaceholders.isEmpty {
                return "unknown placeholders: \(unknownPlaceholders.sorted().joined(separator: ", "))"
            }
        case .menuClick:
            guard let targetApp = action.targetApp, !targetApp.isEmpty else {
                return "menuClick actions require targetApp"
            }
            guard let path = action.path, !path.isEmpty else {
                return "menuClick actions require a non-empty path"
            }
        }

        return nil
    }

    private func validate(menu: CatalogMenuDefinition, actionsByID: [String: CatalogActionDefinition]) -> String? {
        validate(menuItems: menu.items, tileType: menu.tileType, actionsByID: actionsByID)
    }

    private func validate(menuItems: [CatalogMenuItemDefinition], tileType: MenuTileType, actionsByID: [String: CatalogActionDefinition]) -> String? {
        for item in menuItems {
            switch item.type {
            case .action:
                guard let actionID = item.action, let action = actionsByID[actionID] else {
                    return "references unknown action id '\(item.action ?? "")'"
                }
                guard action.tileTypes.contains(tileType) else {
                    return "action '\(actionID)' does not support tile type '\(tileType.rawValue)'"
                }
                if let alternateActionID = item.alternateAction {
                    guard let alternateAction = actionsByID[alternateActionID] else {
                        return "references unknown alternate action id '\(alternateActionID)'"
                    }
                    guard alternateAction.tileTypes.contains(tileType) else {
                        return "alternate action '\(alternateActionID)' does not support tile type '\(tileType.rawValue)'"
                    }
                }
            case .submenu:
                guard let title = item.title, !title.isEmpty else {
                    return "submenu is missing title"
                }
                guard let children = item.children, !children.isEmpty else {
                    return "submenu '\(title)' is empty"
                }
                if let error = validate(menuItems: children, tileType: tileType, actionsByID: actionsByID) {
                    return error
                }
            case .divider:
                break
            }
        }

        return nil
    }

    private func buildMenuItems(from items: [CatalogMenuItemDefinition], context: CatalogActionContext) -> [ContextAction] {
        var resolved: [ContextAction] = []

        for item in items {
            if let condition = item.when, !condition.evaluate(in: context) {
                continue
            }

            switch item.type {
            case .divider:
                if !resolved.isEmpty, resolved.last?.kind != .divider {
                    resolved.append(.divider)
                }
            case .submenu:
                guard let title = item.title, let children = item.children else { continue }
                let submenuItems = buildMenuItems(from: children, context: context)
                guard !submenuItems.isEmpty else { continue }
                resolved.append(.submenu(title, children: submenuItems))
            case .action:
                let resolvedActionID: String
                if let alternateActionID = item.alternateAction,
                   item.alternateActionWhen?.evaluate(in: context) == true {
                    resolvedActionID = alternateActionID
                } else if let actionID = item.action {
                    resolvedActionID = actionID
                } else {
                    continue
                }

                guard
                    let definition = actionsByID[resolvedActionID],
                    definition.when.map({ $0.evaluate(in: context) }) ?? true
                else {
                    continue
                }

                resolved.append(ContextAction.action(
                    resolvedTitle(for: definition, context: context),
                    isDestructive: definition.destructive || (definition.destructiveWhen?.evaluate(in: context) ?? false),
                    isOn: definition.toggleFlag.map { context.value(for: $0) } ?? false
                ) {
                    Task {
                        await ActionExecutionService.shared.perform(action: definition, context: context)
                    }
                })
            }
        }

        while resolved.last?.kind == .divider {
            _ = resolved.popLast()
        }

        return resolved
    }

    private func resolvedTitle(for action: CatalogActionDefinition, context: CatalogActionContext) -> String {
        if let alternateTitle = action.alternateTitle,
           action.alternateTitleWhen?.evaluate(in: context) == true {
            return alternateTitle
        }
        return action.title
    }

    private func makeContext(for tile: Tile, modifierFlags: NSEvent.ModifierFlags) -> CatalogActionContext {
        let finderBundleIdentifier = "com.apple.finder"

        switch tile.content {
        case .app(let app):
            let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
            let isPinned = tile.id.hasPrefix("pinned:")
            return CatalogActionContext(
                tile: tile,
                modifierFlags: modifierFlags,
                bundleIdentifier: app.bundleIdentifier,
                displayName: app.displayName,
                appBundlePath: bundleURL?.path,
                folderPath: nil,
                filePath: bundleURL?.path,
                isRunning: WorkspaceService.shared.isRunning(bundleIdentifier: app.bundleIdentifier),
                isPinned: isPinned,
                canTogglePin: app.bundleIdentifier != finderBundleIdentifier,
                isFinder: app.bundleIdentifier == finderBundleIdentifier
            )
        case .folder(let folder):
            return CatalogActionContext(
                tile: tile,
                modifierFlags: modifierFlags,
                bundleIdentifier: nil,
                displayName: folder.displayName,
                appBundlePath: nil,
                folderPath: folder.url.path,
                filePath: folder.url.path,
                isRunning: false,
                isPinned: true,
                canTogglePin: false,
                isFinder: false
            )
        case .trash:
            return CatalogActionContext(
                tile: tile,
                modifierFlags: modifierFlags,
                bundleIdentifier: nil,
                displayName: "Trash",
                appBundlePath: nil,
                folderPath: nil,
                filePath: nil,
                isRunning: false,
                isPinned: true,
                canTogglePin: false,
                isFinder: false
            )
        case .widget, .smartStack, .spacer, .divider:
            return CatalogActionContext(
                tile: tile,
                modifierFlags: modifierFlags,
                bundleIdentifier: nil,
                displayName: "",
                appBundlePath: nil,
                folderPath: nil,
                filePath: nil,
                isRunning: false,
                isPinned: false,
                canTogglePin: false,
                isFinder: false
            )
        }
    }

    private func tileType(for tile: Tile) -> MenuTileType {
        switch tile.content {
        case .app: return .app
        case .folder: return .folder
        case .trash: return .trash
        case .widget, .smartStack, .spacer, .divider:
            fatalError("Unsupported tile type for context menu catalog")
        }
    }

    private func record(_ message: String) {
        diagnostics.append(message)
        NSLog("[Docky] \(message)")
    }

    private func logDiagnostics() {
        diagnostics.forEach { NSLog("[Docky] \($0)") }
    }
}

private extension String {
    var placeholders: [String] {
        let pattern = #"\{\{([A-Za-z0-9_]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: nsRange).compactMap { match in
            guard match.numberOfRanges == 2,
                  let range = Range(match.range(at: 1), in: self) else {
                return nil
            }
            return String(self[range])
        }
    }
}
