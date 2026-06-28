//
//  WidgetsSettingsView.swift
//  Docky
//
//  Widget Store pane: browse the marketplace (community-submitted
//  widgets fetched from getdocky.com/api/widgets), install
//  `*.dockywidget` bundles from disk, and manage what's already
//  installed. Loading external widget bundles is a Pro feature; users
//  on the free tier see a Pro notice instead of the marketplace and
//  installed lists.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WidgetsSettingsView: View {
    @State private var entries: [WidgetEntry] = []
    @State private var marketplaceState: MarketplaceState = .loading
    @State private var hasPendingChanges = false
    @State private var bundleURLPendingDeletion: URL?
    @State private var installErrorMessage: String?
    @State private var installingIdentifiers: Set<String> = []

    var body: some View {
        Form {
            unlockedContent
        }
        .formStyle(.grouped)
        .navigationTitle("Widget Store")
        .onAppear {
            refresh()
            loadMarketplace()
        }
        .confirmationDialog(
            "Delete this widget?",
            isPresented: deletionDialogBinding,
            presenting: bundleURLPendingDeletion
        ) { url in
            Button("Delete", role: .destructive) {
                deleteBundle(at: url)
                bundleURLPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                bundleURLPendingDeletion = nil
            }
        } message: { url in
            Text("\(url.lastPathComponent) will be removed from disk. It will keep running until you restart Docky.")
        }
        .alert(
            "Could not install widget",
            isPresented: installErrorBinding,
            presenting: installErrorMessage
        ) { _ in
            Button("OK", role: .cancel) { installErrorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private var unlockedContent: some View {
        if hasPendingChanges {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.tint)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restart Docky to apply changes")
                            .font(.callout.weight(.medium))
                        Text("Widget bundles are loaded once per launch. New installs and removals take effect after a restart.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("Quit Docky") {
                        NSApp.terminate(nil)
                    }
                }
            }
        }

        Section("Marketplace") {
            marketplaceSection
        }

        Section("Installed Widgets") {
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No widgets installed yet.")
                        .font(.callout)
                    Text("Pick one from the Marketplace above or install a `.dockywidget` file manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(entries) { entry in
                    entryRow(entry)
                }
            }
        }

        Section {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    actionButton(
                        "Install from File…",
                        systemImage: "square.and.arrow.down",
                        action: installWidget
                    )
                    actionButton(
                        "Reveal Widgets Folder",
                        systemImage: "folder",
                        action: revealWidgetsFolder
                    )
                }
                GridRow {
                    actionButton(
                        "Refresh",
                        systemImage: "arrow.clockwise",
                        action: refresh
                    )
                    Color.clear
                }
            }
        }
    }

    // MARK: - Marketplace

    @ViewBuilder
    private var marketplaceSection: some View {
        switch marketplaceState {
        case .loading:
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading marketplace…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't load the marketplace.")
                    .font(.callout)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try again") { loadMarketplace() }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
            }
        case .loaded(let widgets):
            if widgets.isEmpty {
                Text("No widgets in the marketplace yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(widgets) { widget in
                    marketplaceRow(widget)
                }
            }
        }
    }

    @ViewBuilder
    private func marketplaceRow(_ widget: MarketplaceWidget) -> some View {
        let isInstalled = entries.contains { $0.identifier == widget.identifier }
        let isInstalling = installingIdentifiers.contains(widget.identifier)
        HStack(spacing: 12) {
            Image(systemName: widget.systemImageName ?? "puzzlepiece.extension")
                .font(.title2)
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.accentColor)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(widget.title)
                    .font(.headline)
                Text("\(widget.author) • \(widget.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let description = widget.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            Group {
                if isInstalling {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 90, alignment: .trailing)
                } else if isInstalled {
                    Text("Installed")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        installFromMarketplace(widget)
                    } label: {
                        Text("Install")
                            .frame(minWidth: 70)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private func loadMarketplace() {
        marketplaceState = .loading
        Task {
            do {
                let widgets = try await MarketplaceClient.shared.fetch()
                await MainActor.run { marketplaceState = .loaded(widgets) }
            } catch {
                await MainActor.run {
                    marketplaceState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func installFromMarketplace(_ widget: MarketplaceWidget) {
        let identifier = widget.identifier
        installingIdentifiers.insert(identifier)
        Task {
            defer {
                Task { @MainActor in installingIdentifiers.remove(identifier) }
            }
            do {
                let downloadedURL = try await MarketplaceClient.shared.download(widget)
                _ = try ExternalWidgetLoader.shared.installBundle(from: downloadedURL)
                try? FileManager.default.removeItem(at: downloadedURL.deletingLastPathComponent())
                await MainActor.run {
                    hasPendingChanges = true
                    refresh()
                }
            } catch {
                await MainActor.run {
                    installErrorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    // MARK: - Installed row

    @ViewBuilder
    private func entryRow(_ entry: WidgetEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.systemImageName)
                .font(.title2)
                .frame(width: 32, height: 32)
                .foregroundStyle(entry.status.iconColor)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(entry.status.iconColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.headline)
                    if let badge = entry.status.badgeText {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(entry.status.badgeColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text("\(entry.author) • \(entry.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .failed(let reason) = entry.status {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 12)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([entry.bundleURL])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            Button(role: .destructive) {
                bundleURLPendingDeletion = entry.bundleURL
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this widget")
        }
    }

    // MARK: - Actions

    private func refresh() {
        let registry = ExternalWidgetRegistry.shared
        let loader = ExternalWidgetLoader.shared
        let registrationsByURL = Dictionary(
            uniqueKeysWithValues: registry.registrations.map { ($0.bundleURL.standardizedFileURL, $0) }
        )

        let onDisk = loader.installedBundleURLs()
        var combined: [WidgetEntry] = []
        var seenURLs: Set<URL> = []

        for url in onDisk {
            let standardized = url.standardizedFileURL
            seenURLs.insert(standardized)

            if let registration = registrationsByURL[standardized] {
                combined.append(WidgetEntry(
                    bundleURL: url,
                    identifier: registration.metadata.identifier,
                    displayName: registration.metadata.displayName,
                    systemImageName: registration.metadata.systemImageName,
                    author: registration.metadata.author,
                    version: registration.metadata.version,
                    status: .loaded
                ))
            } else if let failure = loader.loadFailures[standardized] {
                combined.append(WidgetEntry(
                    bundleURL: url,
                    identifier: url.lastPathComponent,
                    displayName: url.deletingPathExtension().lastPathComponent,
                    systemImageName: "exclamationmark.triangle",
                    author: "Unknown",
                    version: "—",
                    status: .failed(failure.localizedReason)
                ))
            } else {
                combined.append(WidgetEntry(
                    bundleURL: url,
                    identifier: url.lastPathComponent,
                    displayName: url.deletingPathExtension().lastPathComponent,
                    systemImageName: "puzzlepiece.extension",
                    author: "Unknown",
                    version: "—",
                    status: .needsRestart
                ))
            }
        }

        for registration in registry.registrations {
            let standardized = registration.bundleURL.standardizedFileURL
            if seenURLs.contains(standardized) { continue }
            combined.append(WidgetEntry(
                bundleURL: registration.bundleURL,
                identifier: registration.metadata.identifier,
                displayName: registration.metadata.displayName + " (file missing)",
                systemImageName: registration.metadata.systemImageName,
                author: registration.metadata.author,
                version: registration.metadata.version,
                status: .loaded
            ))
        }

        entries = combined.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func installWidget() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Install Widget")
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [UTType(exportedAs: "com.docky.widget")]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try ExternalWidgetLoader.shared.installBundle(from: url)
            hasPendingChanges = true
            refresh()
        } catch {
            installErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func deleteBundle(at url: URL) {
        do {
            try ExternalWidgetLoader.shared.uninstallBundle(at: url)
            hasPendingChanges = true
            refresh()
        } catch {
            installErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func revealWidgetsFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([ExternalWidgetLoader.shared.widgetsDirectory])
    }

    // MARK: - Bindings + helpers

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { bundleURLPendingDeletion != nil },
            set: { newValue in
                if !newValue { bundleURLPendingDeletion = nil }
            }
        )
    }

    private var installErrorBinding: Binding<Bool> {
        Binding(
            get: { installErrorMessage != nil },
            set: { newValue in
                if !newValue { installErrorMessage = nil }
            }
        )
    }

    @ViewBuilder
    private func actionButton(
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

private struct WidgetEntry: Identifiable {
    let bundleURL: URL
    let identifier: String
    let displayName: String
    let systemImageName: String
    let author: String
    let version: String
    let status: Status

    var id: String { bundleURL.standardizedFileURL.path }

    enum Status {
        case loaded
        case needsRestart
        case failed(String)

        var badgeText: String? {
            switch self {
            case .loaded: nil
            case .needsRestart: "Needs Restart"
            case .failed: "Failed to Load"
            }
        }

        var badgeColor: Color {
            switch self {
            case .loaded: .accentColor
            case .needsRestart: .accentColor
            case .failed: .red
            }
        }

        var iconColor: Color {
            switch self {
            case .loaded: .accentColor
            case .needsRestart: .secondary
            case .failed: .red
            }
        }
    }
}

private enum MarketplaceState {
    case loading
    case loaded([MarketplaceWidget])
    case failed(String)
}
