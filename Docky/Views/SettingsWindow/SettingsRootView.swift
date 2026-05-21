//
//  SettingsRootView.swift
//  Docky
//

import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case docky
    case profiles
    case appearanceGeneral
    case appearanceIndicators
    case appearanceTileLayout
    case appearanceWindowShape
    case appearanceWindowBackground
    case appearanceWidgets
    case appearanceThemes
    case appIcons
    case behaviorGeneral
    case behaviorPlacement
    case behaviorVisibility
    case behaviorAppTileClick
    case behaviorAppFolders
    case behaviorWidgets
    case hiddenApps
    case launchpad
    case startMenu
    case windowManagement
    case actions
    case behaviorLaunch
    case behaviorSystemDock
    case permissions
    case updates
    case feedback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .docky: "Docky"
        case .profiles: "Profiles"
        case .appearanceGeneral: "General"
        case .appearanceIndicators: "Indicators"
        case .appearanceTileLayout: "Tile Layout"
        case .appearanceWindowShape: "Window Shape"
        case .appearanceWindowBackground: "Window Background"
        case .appearanceWidgets: "Widgets"
        case .appearanceThemes: "Themes"
        case .appIcons: "App Icons"
        case .behaviorGeneral: "General"
        case .behaviorPlacement: "Placement"
        case .behaviorVisibility: "Visibility"
        case .behaviorAppTileClick: "App Tile Click"
        case .behaviorAppFolders: "App Folders"
        case .behaviorWidgets: "Widgets"
        case .hiddenApps: "Hidden Apps"
        case .launchpad: "Launchpad"
        case .startMenu: "Start Menu"
        case .windowManagement: "Window Management"
        case .actions: "Actions"
        case .behaviorLaunch: "Launch"
        case .behaviorSystemDock: "System Dock"
        case .permissions: "Permissions"
        case .updates: "Updates"
        case .feedback: "Feedback"
        }
    }

    var symbolName: String {
        switch self {
        case .docky: "shippingbox"
        case .profiles: "person.crop.rectangle.stack"
        case .appearanceGeneral: "slider.horizontal.3"
        case .appearanceIndicators: "circle.bottomhalf.filled"
        case .appearanceTileLayout: "square.grid.3x3"
        case .appearanceWindowShape: "rectangle.dashed"
        case .appearanceWindowBackground: "rectangle.fill"
        case .appearanceWidgets: "puzzlepiece.extension.fill"
        case .appearanceThemes: "paintpalette"
        case .appIcons: "app.badge"
        case .behaviorGeneral: "slider.horizontal.3"
        case .behaviorPlacement: "arrow.up.and.down.and.arrow.left.and.right"
        case .behaviorVisibility: "eye"
        case .behaviorAppTileClick: "cursorarrow.click"
        case .behaviorAppFolders: "folder"
        case .behaviorWidgets: "puzzlepiece.extension"
        case .hiddenApps: "eye.slash"
        case .launchpad: "square.grid.3x3.fill"
        case .startMenu: "square.grid.2x2"
        case .windowManagement: "rectangle.on.rectangle"
        case .actions: "list.bullet.rectangle"
        case .behaviorLaunch: "power"
        case .behaviorSystemDock: "dock.rectangle"
        case .permissions: "lock.shield"
        case .updates: "arrow.trianglehead.clockwise"
        case .feedback: "envelope"
        }
    }

    var tileColor: Color {
        switch self {
        case .docky: .purple
        case .profiles: .indigo
        case .appearanceGeneral: .teal
        case .appearanceIndicators: .green
        case .appearanceTileLayout: .orange
        case .appearanceWindowShape: .indigo
        case .appearanceWindowBackground: .blue
        case .appearanceWidgets: .purple
        case .appearanceThemes: .pink
        case .appIcons: .pink
        case .behaviorGeneral: .gray
        case .behaviorPlacement: .teal
        case .behaviorVisibility: .cyan
        case .behaviorAppTileClick: .mint
        case .behaviorAppFolders: .yellow
        case .behaviorWidgets: .purple
        case .hiddenApps: .gray
        case .launchpad: .indigo
        case .startMenu: .mint
        case .windowManagement: .blue
        case .actions: .red
        case .behaviorLaunch: .green
        case .behaviorSystemDock: .gray
        case .permissions: .red
        case .updates: .blue
        case .feedback: .orange
        }
    }

    var isPro: Bool {
        switch self {
        case .launchpad, .windowManagement, .appIcons, .actions:
            true
        default:
            false
        }
    }
}

private struct SettingsSection: Identifiable {
    let id: String
    let title: String?
    let panes: [SettingsPane]
}

private let settingsSections: [SettingsSection] = [
    SettingsSection(id: "product", title: "Product", panes: [.docky]),
    SettingsSection(id: "profiles", title: "Profiles", panes: [.profiles]),
    SettingsSection(id: "appearance", title: "Appearance", panes: [
        .appearanceThemes,
        .appearanceGeneral,
        .appearanceIndicators,
        .appearanceTileLayout,
        .appearanceWindowShape,
        .appearanceWindowBackground,
        .appearanceWidgets,
        .appIcons
    ]),
    SettingsSection(id: "behavior", title: "Behavior", panes: [
        .behaviorGeneral,
        .behaviorPlacement,
        .behaviorVisibility,
        .behaviorAppTileClick,
        .behaviorAppFolders,
        .behaviorWidgets,
        .hiddenApps
    ]),
    SettingsSection(id: "features", title: "Features", panes: [
        .launchpad,
        .startMenu,
        .windowManagement,
        .actions
    ]),
    SettingsSection(id: "system", title: "System", panes: [
        .behaviorLaunch,
        .behaviorSystemDock,
        .permissions,
        .updates
    ]),
    SettingsSection(id: "support", title: "Support", panes: [
        .feedback
    ])
]

/// Deep-link mailbox for the Settings window. Surfaces in the
/// sidebar pane selector when the window opens (or on the next
/// observation tick if the window is already open). Used by the
/// divider context menu's "Send Feedback" entry today; can carry
/// any future "jump to pane X" shortcuts the rest of the app needs.
@MainActor
@Observable
final class SettingsNavigator {
    static let shared = SettingsNavigator()
    private init() {}

    /// String form of `SettingsPane.rawValue`. Untyped here so callers
    /// don't need to import the private enum.
    var pendingPaneID: String?

    func requestPane(id: String) {
        pendingPaneID = id
        (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
    }
}

struct SettingsRootView: View {
    @State private var selection: SettingsPane = .docky
    @State private var history: [SettingsPane] = [.docky]
    @State private var historyIndex: Int = 0
    // Suppresses history pushes when the selection change originated from
    // a back/forward button rather than a fresh user navigation.
    @State private var isNavigatingHistory = false
    @Bindable private var navigator = SettingsNavigator.shared

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        NavigationSplitView {
            List(selection: $selection) {
                ForEach(settingsSections) { section in
                    if let title = section.title {
                        Section(title) {
                            paneRows(section.panes)
                        }
                    } else {
                        Section {
                            paneRows(section.panes)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .listStyle(.sidebar)
        } detail: {
            SettingsDetailView(pane: selection)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 2) {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!canGoBack)
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Back")

                    Button(action: goForward) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoForward)
                    .keyboardShortcut("]", modifiers: .command)
                    .help("Forward")
                }
            }
        }
        .onAppear { consumePendingPane() }
        .onChange(of: navigator.pendingPaneID) { _ in consumePendingPane() }
        .onChange(of: selection) { newPane in recordHistory(newPane) }
    }

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < history.count - 1 }

    private func goBack() {
        guard canGoBack else { return }
        isNavigatingHistory = true
        historyIndex -= 1
        selection = history[historyIndex]
    }

    private func goForward() {
        guard canGoForward else { return }
        isNavigatingHistory = true
        historyIndex += 1
        selection = history[historyIndex]
    }

    private func recordHistory(_ pane: SettingsPane) {
        if isNavigatingHistory {
            isNavigatingHistory = false
            return
        }
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        if history.last != pane {
            history.append(pane)
            historyIndex = history.count - 1
        }
    }

    private func consumePendingPane() {
        guard let id = navigator.pendingPaneID,
              let pane = SettingsPane(rawValue: id) else { return }
        selection = pane
        navigator.pendingPaneID = nil
    }

    @ViewBuilder
    private func paneRows(_ panes: [SettingsPane]) -> some View {
        ForEach(panes) { pane in
            HStack(spacing: 8) {
                PaneIconBadge(symbol: pane.symbolName, color: pane.tileColor)
                Text(pane.title)
                Spacer(minLength: 8)
                if pane.isPro {
                    ProBadge()
                }
            }
            .tag(pane)
        }
    }
}

private struct PaneIconBadge: View {
    let symbol: String
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    private static let tileSize: CGFloat = 22
    private static let symbolSize: CGFloat = 12
    private static let cornerRadius: CGFloat = 5

    var body: some View {
        let isDark = colorScheme == .dark
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(isDark ? Color.black : color)
            .frame(width: Self.tileSize, height: Self.tileSize)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: Self.symbolSize, weight: .semibold))
                    .foregroundStyle(isDark ? color : Color.white)
            }
    }
}

private struct SettingsDetailView: View {
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(pane.title)
    }

    @ViewBuilder
    private var selectedView: some View {
        switch pane {
        case .docky:
            ProductSettingsView()
        case .profiles:
            ProfilesSettingsView()
        case .appearanceGeneral:
            AppearanceSettingsView(subsection: .general)
        case .appearanceIndicators:
            AppearanceSettingsView(subsection: .indicators)
        case .appearanceTileLayout:
            AppearanceSettingsView(subsection: .tileLayout)
        case .appearanceWindowShape:
            AppearanceSettingsView(subsection: .windowShape)
        case .appearanceWindowBackground:
            AppearanceSettingsView(subsection: .windowBackground)
        case .appearanceWidgets:
            AppearanceSettingsView(subsection: .widgets)
        case .appearanceThemes:
            ThemesSettingsView()
        case .appIcons:
            AppIconsSettingsView()
        case .behaviorGeneral:
            BehaviorSettingsView(subsection: .general)
        case .behaviorPlacement:
            BehaviorSettingsView(subsection: .placement)
        case .behaviorVisibility:
            BehaviorSettingsView(subsection: .visibility)
        case .behaviorAppTileClick:
            BehaviorSettingsView(subsection: .appTileClick)
        case .behaviorAppFolders:
            BehaviorSettingsView(subsection: .appFolders)
        case .behaviorWidgets:
            BehaviorSettingsView(subsection: .widgets)
        case .hiddenApps:
            HiddenAppsSettingsView()
        case .launchpad:
            LaunchpadSettingsView()
        case .startMenu:
            StartMenuSettingsView()
        case .windowManagement:
            WindowManagementSettingsView()
        case .actions:
            ActionCatalogSettingsView()
        case .behaviorLaunch:
            BehaviorSettingsView(subsection: .launch)
        case .behaviorSystemDock:
            BehaviorSettingsView(subsection: .systemDock)
        case .permissions:
            PermissionsSettingsView()
        case .updates:
            UpdatesSettingsView()
        case .feedback:
            FeedbackSettingsView()
        }
    }
}
