//
//  ThemesSettingsView.swift
//  Docky
//
//  Settings pane that lists installed `.dockytheme` bundles and lets
//  the user activate, deactivate, and delete them. Installed themes
//  persist on disk under `~/Library/Application Support/Docky/Themes/`
//  regardless of which is active — WordPress-style install/activate.
//
//  Bundle import via zip is handled in a separate commit; for now the
//  pane includes a "Reveal Themes Folder" affordance so users can drop
//  unzipped bundles in directly while iterating.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ThemesSettingsView: View {
    @Bindable private var manager = ThemeManager.shared
    @Bindable private var preferences = DockyPreferences.shared
    @State private var themeIDPendingDeletion: String?
    @State private var importErrorMessage: String?

    var body: some View {
        Form {
            Section("Active") {
                if let active = manager.activeManifest {
                    activeThemeRow(active)
                } else {
                    Text("No theme is active. Your appearance customizations are applied directly.")
                        .foregroundStyle(.secondary)
                }

                if !preferences.userOverriddenAppearanceKeys.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You have \(preferences.userOverriddenAppearanceKeys.count) appearance override(s).")
                                .font(.callout)
                            Text("These take precedence over the active theme. Clear them to let the theme show through.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Button("Clear Overrides") {
                            preferences.clearAllAppearanceOverrides()
                        }
                    }
                }
            }

            Section("Installed Themes") {
                let installed = manager.installedThemes.values
                    .sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }

                if installed.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No themes installed yet.")
                            .font(.callout)
                        Text("Drop an unzipped `.dockytheme` folder into the Themes directory, then refresh.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(installed, id: \.manifest.id) { theme in
                        installedThemeRow(theme)
                    }
                }
            }

            Section {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        themesActionButton(
                            "Import Theme…",
                            systemImage: "square.and.arrow.down",
                            action: importTheme
                        )
                        themesActionButton(
                            "Export to Theme…",
                            systemImage: "square.and.arrow.up",
                            action: exportTheme
                        )
                    }
                    GridRow {
                        themesActionButton(
                            "Reveal Themes Folder",
                            systemImage: "folder",
                            action: revealThemesFolder
                        )
                        themesActionButton(
                            "Refresh",
                            systemImage: "arrow.clockwise",
                            action: manager.refreshInstalled
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete this theme?",
            isPresented: deletionDialogBinding,
            presenting: themeIDPendingDeletion
        ) { id in
            Button("Delete", role: .destructive) {
                try? manager.deleteTheme(id: id)
                themeIDPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                themeIDPendingDeletion = nil
            }
        } message: { _ in
            Text("The theme bundle will be removed from disk. This cannot be undone.")
        }
        .alert(
            "Could not import theme",
            isPresented: importErrorBinding,
            presenting: importErrorMessage
        ) { _ in
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func activeThemeRow(_ manifest: ThemeManifest) -> some View {
        HStack(spacing: 12) {
            ThemePreviewBadge(manifest: manifest)
            VStack(alignment: .leading, spacing: 2) {
                Text(manifest.name)
                    .font(.headline)
                if let author = manifest.author, !author.isEmpty {
                    Text("by \(author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Button("Deactivate") {
                manager.clearActive()
            }
        }
    }

    @ViewBuilder
    private func installedThemeRow(_ theme: InstalledTheme) -> some View {
        let isActive = manager.activeThemeID == theme.manifest.id

        HStack(spacing: 12) {
            ThemePreviewBadge(manifest: theme.manifest)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(theme.manifest.name)
                        .font(.headline)
                    if isActive {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    if theme.isBundled {
                        Text("Built-in")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                if let author = theme.manifest.author, !author.isEmpty {
                    Text("by \(author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let description = theme.manifest.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)

            if isActive {
                Button("Deactivate") {
                    manager.clearActive()
                }
            } else {
                Button("Apply") {
                    manager.setActive(theme.manifest.id)
                }
            }

            if !theme.isBundled {
                Button(role: .destructive) {
                    themeIDPendingDeletion = theme.manifest.id
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this theme")
            }
        }
    }

    // MARK: - Actions

    private func revealThemesFolder() {
        let url = manager.themesDirectoryURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Theme")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ThemesSettingsView.importContentTypes

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try manager.importTheme(from: url)
        } catch {
            importErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func exportTheme() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Theme")
        panel.nameFieldStringValue = defaultExportName()
        panel.allowedContentTypes = ThemesSettingsView.importContentTypes
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // The filename (sans extension) becomes the theme's display
        // name; the slugified version is the manifest id. This keeps
        // export as a single-click flow without an extra naming sheet.
        let name = url.deletingPathExtension().lastPathComponent
        do {
            try manager.exportCurrentAppearance(name: name, to: url)
        } catch {
            importErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func defaultExportName() -> String {
        if let active = manager.activeManifest {
            return "\(active.name) Copy.dockytheme"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "My Docky Theme \(formatter.string(from: Date())).dockytheme"
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { themeIDPendingDeletion != nil },
            set: { newValue in
                if !newValue { themeIDPendingDeletion = nil }
            }
        )
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { newValue in
                if !newValue { importErrorMessage = nil }
            }
        )
    }

    /// File types accepted by the import panel. Accept both the custom
    /// `.dockytheme` extension and a plain `.zip` so users can grab
    /// either flavor from a release archive.
    private static let importContentTypes: [UTType] = {
        var types: [UTType] = [.zip]
        if let custom = UTType(filenameExtension: "dockytheme") {
            types.insert(custom, at: 0)
        }
        return types
    }()

    /// Grid cell used for every Themes action button. Mirrors the
    /// onboarding's `.bordered` + `.large` styling so on macOS 26+
    /// each cell picks up the system Liquid Glass material for free,
    /// and stretches to fill its column for a uniform two-column row.
    @ViewBuilder
    private func themesActionButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

/// 16:9 cover/preview tile used in the installed-themes list.
///
/// Preference order:
///   1. `cover_image.png` (or `.jpg`/`.jpeg`) at the bundle root —
///      theme-author-supplied artwork.
///   2. The theme's `appearance.window.backgroundImage` asset,
///      scaled to fill — synthesizes a usable preview from the
///      same asset the dock chrome would render.
///   3. The manifest's `appearance.window.tintColor` — flat-color
///      placeholder so a bare manifest still reads visually.
///   4. A neutral secondary fill when none of the above apply.
private struct ThemePreviewBadge: View {
    let manifest: ThemeManifest

    private static let size = CGSize(width: 96, height: 54)
    private static let cornerRadius: CGFloat = 8

    var body: some View {
        let tint = manifest.appearance.window?.tintColor?.nsColor
        let cover = coverImageURL.flatMap { NSImage(contentsOf: $0) }
        let background: NSImage? = cover == nil
            ? backgroundImageURL.flatMap { NSImage(contentsOf: $0) }
            : nil
        let clipShape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)

        // The outer `.clipShape` guarantees the fill, image overlay,
        // and anything added later are all confined to the rounded
        // bounds — `scaledToFill` will gladly render outside the
        // frame, and per-image clipping has been forgotten before.
        Rectangle()
            .fill(tint.map(Color.init(nsColor:)) ?? Color.secondary.opacity(0.2))
            .frame(width: Self.size.width, height: Self.size.height)
            .overlay {
                if let cover {
                    Image(nsImage: cover)
                        .resizable()
                        .scaledToFill()
                } else if let background {
                    Image(nsImage: background)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(clipShape)
            .overlay {
                clipShape.strokeBorder(.separator, lineWidth: 0.5)
            }
    }

    private var coverImageURL: URL? {
        ThemeManager.shared.installedThemes[manifest.id]?.coverImageURL
    }

    private var backgroundImageURL: URL? {
        guard let asset = manifest.appearance.window?.backgroundImage else { return nil }
        // Use the manager's resolver when this theme is active so
        // previews stay in lockstep with what the dock chrome renders.
        if ThemeManager.shared.activeThemeID == manifest.id {
            return ThemeManager.shared.activeAssetURL(asset)
        }
        guard let bundle = ThemeManager.shared.installedThemes[manifest.id]?.bundleURL else {
            return nil
        }
        let url = bundle.appending(path: asset, directoryHint: .notDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
