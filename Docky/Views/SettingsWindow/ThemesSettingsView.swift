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
                HStack {
                    Button {
                        importTheme()
                    } label: {
                        Label("Import Theme…", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        revealThemesFolder()
                    } label: {
                        Label("Reveal Themes Folder", systemImage: "folder")
                    }

                    Button {
                        manager.refreshInstalled()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
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

            Button(role: .destructive) {
                themeIDPendingDeletion = theme.manifest.id
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this theme")
        }
    }

    // MARK: - Actions

    private func revealThemesFolder() {
        let url = manager.themesDirectoryURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.title = "Import Theme"
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
}

/// Square color/image preview chip used in the installed-themes list.
/// Falls back to the theme's tint color when no background image is
/// bundled, and to a neutral fill when neither is supplied.
private struct ThemePreviewBadge: View {
    let manifest: ThemeManifest

    var body: some View {
        let fill = manifest.appearance.window?.tintColor?.dockColor.nsColor
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill.map(Color.init(nsColor:)) ?? Color.secondary.opacity(0.2))
            .frame(width: 44, height: 44)
            .overlay {
                if let imageURL = backgroundImageURL,
                   let nsImage = NSImage(contentsOf: imageURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
    }

    private var backgroundImageURL: URL? {
        guard let asset = manifest.appearance.window?.backgroundImage else { return nil }
        guard manifest.id == ThemeManager.shared.activeThemeID
            || ThemeManager.shared.installedThemes[manifest.id] != nil else {
            return nil
        }
        // Use the manager's resolver so previews stay consistent with
        // rendering paths (and pick up the same file-existence check).
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
