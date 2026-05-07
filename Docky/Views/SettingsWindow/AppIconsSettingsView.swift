//
//  AppIconsSettingsView.swift
//  Docky
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppIconsSettingsView: View {
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared
    @ObservedObject private var workspace = WorkspaceService.shared

    var body: some View {
        Form {
            Section("Trash") {
                Text("Pick custom images for the Trash tile's empty and full states. Both default to the system Trash icons.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(TrashIconState.allCases) { state in
                    TrashIconOverrideRow(state: state)
                        .padding(.vertical, 4)
                }
            }

            Section("Folders") {
                Text("Pick custom images for any folder tile currently in the dock. Each folder defaults to its system icon.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if folderEntries.isEmpty {
                    Text("No folder tiles are currently in the dock.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(folderEntries) { entry in
                        FolderIconOverrideRow(entry: entry)
                            .padding(.vertical, 4)
                    }
                }
            }

            Section("Launchpad") {
                Text("Pick a custom image for the Launchpad tile. Defaults to the system Launchpad icon.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LaunchpadIconOverrideRow()
                    .padding(.vertical, 4)
            }

            Section("Overrides") {
                if !product.isUnlocked(.customAppIcons) {
                    ProFeatureNotice(feature: .customAppIcons)
                }

                Text("Choose a custom image for any app Docky currently knows about. Custom app icons follow Docky's circle tile clipping when circle tiles are enabled.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if appEntries.isEmpty {
                    Text("No apps are currently available for icon overrides.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appEntries) { entry in
                        AppIconOverrideRow(entry: entry)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appEntries: [AppIconSettingsEntry] {
        var bundleIdentifiers: Set<String> = ["com.apple.finder"]
        bundleIdentifiers.formUnion(workspace.runningApps.map(\.bundleIdentifier))
        bundleIdentifiers.formUnion(preferences.appIconOverrides.map(\.bundleIdentifier))
        bundleIdentifiers.formUnion(preferences.widgetPlacements.map(\.ownerBundleIdentifier))

        for item in preferences.pinnedItems {
            if let bundleIdentifier = item.bundleIdentifier {
                bundleIdentifiers.insert(bundleIdentifier)
            }

            bundleIdentifiers.formUnion(item.folderBundleIdentifiers)
        }

        return bundleIdentifiers.compactMap { bundleIdentifier in
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            let displayName = appURL.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleIdentifier
            let subtitle = appURL == nil
                ? "\(bundleIdentifier) • App not currently found on disk"
                : bundleIdentifier

            return AppIconSettingsEntry(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                subtitle: subtitle,
                systemIcon: IconCacheService.shared.icon(forBundleIdentifier: bundleIdentifier)
            )
        }
        .sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier.localizedCaseInsensitiveCompare(rhs.bundleIdentifier) == .orderedAscending
            }
            return comparison == .orderedAscending
        }
    }

    private var folderEntries: [FolderIconSettingsEntry] {
        var seenPaths: Set<String> = []
        var entries: [FolderIconSettingsEntry] = []

        for item in preferences.trailingItems {
            guard item.kind == .folder, let url = item.folderURL else { continue }
            let path = url.path
            guard seenPaths.insert(path).inserted else { continue }
            let displayName = item.folderDisplayName?.isEmpty == false
                ? item.folderDisplayName!
                : FileManager.default.displayName(atPath: path)
            entries.append(FolderIconSettingsEntry(
                folderPath: path,
                displayName: displayName,
                systemIcon: IconCacheService.shared.previewIcon(forFileURL: url)
            ))
        }

        return entries.sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if comparison == .orderedSame {
                return lhs.folderPath.localizedCaseInsensitiveCompare(rhs.folderPath) == .orderedAscending
            }
            return comparison == .orderedAscending
        }
    }
}

private struct AppIconOverrideRow: View {
    let entry: AppIconSettingsEntry

    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.headline)

                    Text(entry.subtitle)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .textSelection(.enabled)

                    if let overrideName {
                        Text("Override: \(overrideName)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Choose Image...") {
                        chooseOverrideImage()
                    }
                    .disabled(!product.isUnlocked(.customAppIcons))

                    if overrideEntry != nil {
                        Button("Clear") {
                            preferences.removeAppIconOverride(bundleIdentifier: entry.bundleIdentifier)
                        }
                        .disabled(!product.isUnlocked(.customAppIcons))
                    }
                }
            }

            if overrideEntry != nil {
                paddingSlider
            }
        }
    }

    /// Per-icon padding slider, shown only when an override is set. The
    /// fraction is stored as 0...0.5 of the smaller cell dimension and
    /// rendered as 0–50 % in the UI.
    private var paddingSlider: some View {
        HStack(spacing: 8) {
            Text("Padding")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: paddingFractionBinding, in: 0...0.5, step: 0.01)
                .controlSize(.small)
                .disabled(!product.isUnlocked(.customAppIcons))

            Text("\(Int((overrideEntry?.paddingFraction ?? 0) * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var paddingFractionBinding: Binding<CGFloat> {
        Binding(
            get: { overrideEntry?.paddingFraction ?? 0 },
            set: { newValue in
                let clamped = min(max(newValue, 0), 0.5)
                preferences.setAppIconPaddingFraction(
                    bundleIdentifier: entry.bundleIdentifier,
                    paddingFraction: clamped == 0 ? nil : clamped
                )
            }
        )
    }

    private var overrideEntry: AppIconOverride? {
        preferences.appIconOverride(forBundleIdentifier: entry.bundleIdentifier)
    }

    private var overrideName: String? {
        guard let iconPath = overrideEntry?.iconPath, !iconPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: iconPath).lastPathComponent
    }

    private var previewImage: NSImage {
        if let overrideURL = overrideEntry?.effectiveIconURL,
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return entry.systemIcon
    }

    private func chooseOverrideImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            preferences.setAppIconOverride(
                bundleIdentifier: entry.bundleIdentifier,
                iconPath: url.path
            )
        }
    }
}

private struct AppIconSettingsEntry: Identifiable {
    let bundleIdentifier: String
    let displayName: String
    let subtitle: String
    let systemIcon: NSImage

    var id: String { bundleIdentifier }
}

private struct TrashIconOverrideRow: View {
    let state: TrashIconState

    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Trash (\(state.title))")
                        .font(.headline)

                    Text(state == .empty
                         ? "Shown when the Trash is empty."
                         : "Shown when the Trash has items.")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    if let overrideName {
                        Text("Override: \(overrideName)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Choose Image...") {
                        chooseOverrideImage()
                    }
                    .disabled(!product.isUnlocked(.customAppIcons))

                    if overrideEntry != nil {
                        Button("Clear") {
                            preferences.removeTrashIconOverride(state: state)
                        }
                        .disabled(!product.isUnlocked(.customAppIcons))
                    }
                }
            }

            if overrideEntry != nil {
                paddingSlider
            }
        }
    }

    private var paddingSlider: some View {
        HStack(spacing: 8) {
            Text("Padding")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: paddingFractionBinding, in: 0...0.5, step: 0.01)
                .controlSize(.small)
                .disabled(!product.isUnlocked(.customAppIcons))

            Text("\(Int((overrideEntry?.paddingFraction ?? 0) * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var paddingFractionBinding: Binding<CGFloat> {
        Binding(
            get: { overrideEntry?.paddingFraction ?? 0 },
            set: { newValue in
                let clamped = min(max(newValue, 0), 0.5)
                preferences.setTrashIconPaddingFraction(
                    state: state,
                    paddingFraction: clamped == 0 ? nil : clamped
                )
            }
        )
    }

    private var overrideEntry: TrashIconOverride? {
        preferences.trashIconOverride(forState: state)
    }

    private var overrideName: String? {
        guard let iconPath = overrideEntry?.iconPath, !iconPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: iconPath).lastPathComponent
    }

    private var previewImage: NSImage {
        if let overrideURL = overrideEntry?.effectiveIconURL,
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return NSImage(named: state.systemImageName) ?? NSImage()
    }

    private func chooseOverrideImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            preferences.setTrashIconOverride(state: state, iconPath: url.path)
        }
    }
}

private struct FolderIconSettingsEntry: Identifiable {
    let folderPath: String
    let displayName: String
    let systemIcon: NSImage

    var id: String { folderPath }
}

private struct FolderIconOverrideRow: View {
    let entry: FolderIconSettingsEntry

    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.headline)

                    Text(entry.folderPath)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let overrideName {
                        Text("Override: \(overrideName)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Choose Image...") {
                        chooseOverrideImage()
                    }
                    .disabled(!product.isUnlocked(.customAppIcons))

                    if overrideEntry != nil {
                        Button("Clear") {
                            preferences.removeFolderIconOverride(folderPath: entry.folderPath)
                        }
                        .disabled(!product.isUnlocked(.customAppIcons))
                    }
                }
            }

            if overrideEntry != nil {
                paddingSlider
            }
        }
    }

    private var paddingSlider: some View {
        HStack(spacing: 8) {
            Text("Padding")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: paddingFractionBinding, in: 0...0.5, step: 0.01)
                .controlSize(.small)
                .disabled(!product.isUnlocked(.customAppIcons))

            Text("\(Int((overrideEntry?.paddingFraction ?? 0) * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var paddingFractionBinding: Binding<CGFloat> {
        Binding(
            get: { overrideEntry?.paddingFraction ?? 0 },
            set: { newValue in
                let clamped = min(max(newValue, 0), 0.5)
                preferences.setFolderIconPaddingFraction(
                    folderPath: entry.folderPath,
                    paddingFraction: clamped == 0 ? nil : clamped
                )
            }
        )
    }

    private var overrideEntry: FolderIconOverride? {
        preferences.folderIconOverride(forPath: entry.folderPath)
    }

    private var overrideName: String? {
        guard let iconPath = overrideEntry?.iconPath, !iconPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: iconPath).lastPathComponent
    }

    private var previewImage: NSImage {
        if let overrideURL = overrideEntry?.effectiveIconURL,
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return entry.systemIcon
    }

    private func chooseOverrideImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            preferences.setFolderIconOverride(folderPath: entry.folderPath, iconPath: url.path)
        }
    }
}

private struct LaunchpadIconOverrideRow: View {
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Launchpad")
                        .font(.headline)

                    Text("Replaces the Launchpad tile's icon.")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    if let overrideName {
                        Text("Override: \(overrideName)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Choose Image...") {
                        chooseOverrideImage()
                    }
                    .disabled(!product.isUnlocked(.customAppIcons))

                    if hasOverride {
                        Button("Clear") {
                            preferences.launchpadIconPath = nil
                            preferences.launchpadIconPaddingFraction = nil
                        }
                        .disabled(!product.isUnlocked(.customAppIcons))
                    }
                }
            }

            if hasOverride {
                paddingSlider
            }
        }
    }

    private var paddingSlider: some View {
        HStack(spacing: 8) {
            Text("Padding")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: paddingFractionBinding, in: 0...0.5, step: 0.01)
                .controlSize(.small)
                .disabled(!product.isUnlocked(.customAppIcons))

            Text("\(Int((preferences.launchpadIconPaddingFraction ?? 0) * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var paddingFractionBinding: Binding<CGFloat> {
        Binding(
            get: { preferences.launchpadIconPaddingFraction ?? 0 },
            set: { newValue in
                let clamped = min(max(newValue, 0), 0.5)
                preferences.launchpadIconPaddingFraction = clamped == 0 ? nil : clamped
            }
        )
    }

    private var hasOverride: Bool {
        guard let path = preferences.launchpadIconPath else { return false }
        return !path.isEmpty
    }

    private var overrideName: String? {
        guard let path = preferences.launchpadIconPath, !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var previewImage: NSImage {
        if let overrideURL = preferences.effectiveLaunchpadIconOverrideURL,
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }
        return IconCacheService.shared.icon(forBundleIdentifier: LaunchpadTile.spotlightBundleIdentifier)
    }

    private func chooseOverrideImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            preferences.launchpadIconPath = url.path
        }
    }
}
