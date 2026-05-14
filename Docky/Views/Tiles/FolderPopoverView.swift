//
//  FolderPopoverView.swift
//  Docky
//

import AppKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct FolderPopoverView: View {
    let tile: FolderTile
    let initialSnapshot: FolderContentsSnapshot
    @Binding var isPresented: Bool
    let onPopoverSizeChange: (CGSize) -> Void

    @ObservedObject private var permissions = PermissionsService.shared
    @ObservedObject private var folderAccess = FolderAccessService.shared
    @State private var currentEntry: FolderPopoverEntry
    @State private var backHistory: [FolderPopoverEntry]
    @State private var selectedItemID: String?
    @State private var watchedEntryURL: URL?
    @State private var springLoadingItemID: String?
    @State private var springLoadTask: Task<Void, Never>?
    private let subfolderSpringLoadDwell: TimeInterval = 0.7

    private let maxGridColumnCount = 8
    private let gridItemWidth: CGFloat = 144
    private let gridItemHeight: CGFloat = 158
    private let gridItemSpacing: CGFloat = 4
    private let contentPadding: CGFloat = 20
    private let minGridWidth: CGFloat = 320
    private let minGridHeight: CGFloat = 240
    private let maxGridHeight: CGFloat = 840
    private let headerHeight: CGFloat = 38

    init(
        tile: FolderTile,
        initialSnapshot: FolderContentsSnapshot,
        isPresented: Binding<Bool>,
        onPopoverSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.tile = tile
        self.initialSnapshot = initialSnapshot
        _isPresented = isPresented
        self.onPopoverSizeChange = onPopoverSizeChange
        let rootEntry = FolderPopoverEntry(
            url: tile.url,
            displayName: tile.displayName,
            snapshot: initialSnapshot
        )
        _currentEntry = State(initialValue: rootEntry)
        _backHistory = State(initialValue: [])
        _selectedItemID = State(initialValue: nil)
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        bodyContent
            .task(id: reloadKey) {
                syncWatchedFolder()
                currentEntry = refreshedEntry(for: currentEntry)
                backHistory = backHistory.map(refreshedEntry(for:))
                selectDefaultItemIfNeeded()
                reportPopoverSize()
            }
            .background {
                FolderPopoverKeyMonitor { event in
                    handleKeyDown(event)
                }
            }
            .onAppear {
                syncWatchedFolder()
                selectDefaultItemIfNeeded()
                reportPopoverSize()
            }
            .onDisappear {
                stopWatchingCurrentFolder()
            }
            .onChange(of: popoverSize) { _ in
                reportPopoverSize()
            }
    }

    @ViewBuilder
    private var bodyContent: some View {
        VStack(spacing: 0) {
            navigationHeader

            if case .unreadable = currentEntry.snapshot {
                unreadableState
            } else if items.isEmpty {
                emptyState
            } else {
                gridContentsView
            }
        }
        .frame(width: popoverWidth, height: popoverHeight)
        .background(.ultraThickMaterial)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            moveDroppedFiles(providers: providers, into: currentEntry.url)
            return true
        }
    }

    private var items: [URL] {
        FolderAccessService.shared.sortedItems(in: currentEntry.snapshot, sortMode: tile.sortMode)
    }

    private var popoverItems: [FolderPopoverItem] {
        items.map(FolderPopoverItem.url) + [.action(openInFinderItem)]
    }

    private var openInFinderItem: FolderPopoverAction {
        FolderPopoverAction(
            id: "open-in-finder",
            title: "Open in Finder",
            systemImageName: "arrowshape.turn.up.right.circle"
        ) {
            openCurrentFolderInFinder()
        }
    }

    private var gridContentsView: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: gridColumns, spacing: gridItemSpacing) {
                ForEach(popoverItems) { item in
                    cardButton(for: item) {
                        switch item {
                        case .url(let itemURL):
                            FolderPopoverItemView(url: itemURL)
                        case .action(let action):
                            FolderPopoverActionItemView(action: action)
                        }
                    }
                }
            }
            .padding(contentPadding)
        }
    }

    @ViewBuilder
    private func cardButton<Label: View>(for item: FolderPopoverItem, @ViewBuilder label: () -> Label) -> some View {
        switch item {
        case .url(let itemURL):
            let isFolder = isNavigableFolder(itemURL)
            Button {
                selectedItemID = item.id
                handleSelection(of: itemURL)
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .onDrag {
                dragItemProvider(for: itemURL)
            }
            .onHover { isHovering in
                guard isHovering else { return }
                selectedItemID = item.id
            }
            .background {
                ContextActionMenuPresenter { _ in
                    contextActions(for: itemURL)
                }
            }
            // Folder-only drop target: hover-dwell navigates into the folder
            // (classic spring-loaded folders), and releasing files there moves
            // them into that folder rather than the popover's current folder.
            // Non-folder items pass through to the body-level drop.
            .onDrop(
                of: isFolder ? [UTType.fileURL.identifier] : [],
                isTargeted: isFolder ? subfolderSpringLoadBinding(for: itemURL) : nil,
                perform: { providers in
                    guard isFolder else { return false }
                    cancelSubfolderSpringLoad()
                    moveDroppedFiles(providers: providers, into: itemURL)
                    return true
                }
            )
        case .action(let action):
            Button(action: action.handler) {
                label()
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                guard isHovering else { return }
                selectedItemID = item.id
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(nsImage: IconCacheService.shared.icon(forFileURL: currentEntry.url))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 112, height: 112)

            Text("No visible items")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(currentEntry.displayName)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var unreadableState: some View {
        VStack(spacing: 12) {
            Image(nsImage: IconCacheService.shared.icon(forFileURL: currentEntry.url))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 112, height: 112)

            Text("Can't read folder contents")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(currentEntry.displayName)
                .font(.callout)
                .foregroundStyle(.secondary)

            // Sandboxed (MAS) build: the only way to recover read
            // access is for the user to confirm the folder via an
            // NSOpenPanel so we can store a security-scoped bookmark.
            // We surface this button in both builds because the
            // unreadable state can also happen in the Dev ID build
            // when FDA was revoked, and re-bookmarking is a valid
            // workaround there too.
            Button {
                if folderAccess.requestAccess(to: currentEntry.url) {
                    currentEntry = refreshedEntry(for: currentEntry)
                }
            } label: {
                Text("Grant Access")
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var navigationHeader: some View {
        HStack(spacing: 12) {
            if !backHistory.isEmpty {
                Button(action: navigateBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.14))
                    )
                }
                .buttonStyle(.plain)
            }

            Text(currentEntry.displayName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, contentPadding)
        .padding(.top, 16)
        .frame(height: headerHeight, alignment: .center)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(gridItemWidth), spacing: gridItemSpacing, alignment: .top),
            count: gridColumnCount
        )
    }

    private var gridColumnCount: Int {
        min(max(popoverItems.count, 1), maxGridColumnCount)
    }

    private var gridRowCount: Int {
        max(Int(ceil(Double(popoverItems.count) / Double(gridColumnCount))), 1)
    }

    private var popoverWidth: CGFloat {
        if case .unreadable = currentEntry.snapshot {
            return 360
        }

        if items.isEmpty {
            return 320
        }

        let gridWidth = CGFloat(gridColumnCount) * gridItemWidth + CGFloat(max(gridColumnCount - 1, 0)) * gridItemSpacing
        return max(minGridWidth, gridWidth + contentPadding * 2)
    }

    private var popoverHeight: CGFloat {
        if case .unreadable = currentEntry.snapshot {
            return 258
        }

        if items.isEmpty {
            return 218
        }

        let gridHeight = CGFloat(gridRowCount) * gridItemHeight + CGFloat(max(gridRowCount - 1, 0)) * gridItemSpacing
        let totalHeight = gridHeight + contentPadding * 2 + headerHeight + 16
        return min(max(totalHeight, minGridHeight), maxGridHeight)
    }

    private var popoverSize: CGSize {
        CGSize(width: popoverWidth, height: popoverHeight)
    }

    private var reloadKey: String {
        "\(currentEntry.url.path)|\(permissions.userFolders)|\(folderAccess.changeToken)|\(isPresented)"
    }

    private var watcherOwnerID: String {
        "folder-popover:\(tile.url.standardizedFileURL.path)"
    }

    private func handleSelection(of itemURL: URL) {
        if isNavigableFolder(itemURL) {
            backHistory.append(currentEntry)
            currentEntry = FolderPopoverEntry(
                url: itemURL,
                displayName: displayName(for: itemURL),
                snapshot: FolderAccessService.shared.snapshot(of: itemURL)
            )
            selectDefaultItemIfNeeded()
            return
        }

        open(itemURL)
    }

    private func navigateBack() {
        guard let previousEntry = backHistory.popLast() else { return }
        currentEntry = previousEntry
        selectDefaultItemIfNeeded()
    }

    private func open(_ itemURL: URL) {
        let opened = NSWorkspace.shared.open(itemURL)
        if opened {
            isPresented = false
        }
    }

    private func contextActions(for itemURL: URL) -> [ContextAction] {
        var actions: [ContextAction] = []
        if isNavigableFolder(itemURL) {
            actions.append(.action(String(localized: "Reveal in Finder"), image: contextMenuSymbol("rectangle.stack.badge.plus")) {
                revealInFinder(itemURL)
            })
            actions.append(.action(String(localized: "Open in Finder"), image: contextMenuSymbol("folder")) {
                openInFinder(itemURL)
            })
            return actions
        }

        actions = fileContextActions(for: itemURL)
        actions.append(.divider)
        actions.append(.action(String(localized: "Reveal in Finder"), image: contextMenuSymbol("rectangle.stack.badge.plus")) {
            revealInFinder(itemURL)
        })
        return actions
    }

    private func revealInFinder(_ itemURL: URL) {
        Task {
            if await AppleScriptService.shared.revealInFinder(itemURL) {
                isPresented = false
            }
        }
    }

    private func openInFinder(_ itemURL: URL) {
        Task {
            if await AppleScriptService.shared.openFinderWindow(for: itemURL) {
                isPresented = false
            }
        }
    }

    private func isNavigableFolder(_ itemURL: URL) -> Bool {
        let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    private func displayName(for itemURL: URL) -> String {
        (try? itemURL.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? itemURL.lastPathComponent
    }

    private func openCurrentFolderInFinder() {
        openInFinder(currentEntry.url)
    }

    private func dragItemProvider(for itemURL: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: itemURL as NSURL)
        provider.suggestedName = displayName(for: itemURL)
        return provider
    }

    /// Spring-loaded drop landing: moves the dragged URLs into `destination`.
    /// Cross-volume drops fall back to a copy. Skips items that already live
    /// in the destination folder.
    private func moveDroppedFiles(providers: [NSItemProvider], into destination: URL) {
        let typeID = UTType.fileURL.identifier
        let group = DispatchGroup()
        var collected: [URL] = []
        let queue = DispatchQueue(label: "docky.folder.drop")

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(typeID) else { continue }
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                defer { group.leave() }
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                queue.sync { collected.append(url) }
            }
        }

        group.notify(queue: .main) {
            for source in collected {
                let target = destination.appendingPathComponent(source.lastPathComponent)
                guard target.standardizedFileURL != source.standardizedFileURL else { continue }
                do {
                    try FileManager.default.moveItem(at: source, to: target)
                } catch {
                    // Cross-volume moves throw; copy as a fallback so the
                    // user still gets something at the destination.
                    try? FileManager.default.copyItem(at: source, to: target)
                }
            }
            isPresented = false
            DockDragService.shared.clear()
        }
    }

    /// Drives subfolder spring-loading: when a drag enters a folder card,
    /// schedule a navigation; when it leaves, cancel. The navigation pushes
    /// the current entry onto backHistory and replaces it with the subfolder
    /// — the same code path the user gets when they click into a folder.
    private func subfolderSpringLoadBinding(for itemURL: URL) -> Binding<Bool> {
        let itemID = itemURL.absoluteString
        return Binding(
            get: { springLoadingItemID == itemID },
            set: { isTargeted in
                if isTargeted {
                    scheduleSubfolderSpringLoad(into: itemURL)
                } else if springLoadingItemID == itemID {
                    cancelSubfolderSpringLoad()
                }
            }
        )
    }

    private func scheduleSubfolderSpringLoad(into itemURL: URL) {
        let itemID = itemURL.absoluteString
        guard springLoadingItemID != itemID else { return }
        springLoadTask?.cancel()
        springLoadingItemID = itemID
        let dwell = subfolderSpringLoadDwell
        springLoadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(dwell * 1_000_000_000))
            guard !Task.isCancelled, springLoadingItemID == itemID else { return }
            springLoadingItemID = nil
            handleSelection(of: itemURL)
        }
    }

    private func cancelSubfolderSpringLoad() {
        springLoadTask?.cancel()
        springLoadTask = nil
        springLoadingItemID = nil
    }

    private func selectDefaultItemIfNeeded() {
        if let selectedItemID, popoverItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        selectedItemID = popoverItems.first(where: { item in
            if case .url = item {
                return true
            }
            return false
        })?.id ?? popoverItems.first?.id
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return false }
        guard event.charactersIgnoringModifiers == " " else { return false }
        guard let itemURL = selectedItemURL else { return false }

        FolderQuickLookController.shared.preview(itemURL)
        return true
    }

    private var selectedItemURL: URL? {
        guard let selectedItemID else { return nil }

        for item in popoverItems {
            guard item.id == selectedItemID else { continue }
            if case .url(let url) = item {
                return url
            }
        }

        return nil
    }

    private func refreshedEntry(for entry: FolderPopoverEntry) -> FolderPopoverEntry {
        FolderPopoverEntry(
            url: entry.url,
            displayName: entry.displayName,
            snapshot: FolderAccessService.shared.snapshot(of: entry.url)
        )
    }

    private func syncWatchedFolder() {
        let normalizedCurrentURL = currentEntry.url.standardizedFileURL
        if let watchedEntryURL, watchedEntryURL != normalizedCurrentURL {
            folderAccess.endWatching(watchedEntryURL, ownerID: watcherOwnerID)
        }

        watchedEntryURL = normalizedCurrentURL
        folderAccess.beginWatching(normalizedCurrentURL, ownerID: watcherOwnerID)
    }

    private func stopWatchingCurrentFolder() {
        guard let watchedEntryURL else {
            return
        }

        folderAccess.endWatching(watchedEntryURL, ownerID: watcherOwnerID)
        self.watchedEntryURL = nil
    }

    private func reportPopoverSize() {
        onPopoverSizeChange(popoverSize)
    }

}

private struct FolderPopoverEntry: Equatable {
    let url: URL
    let displayName: String
    let snapshot: FolderContentsSnapshot
}

private enum FolderPopoverItem: Identifiable {
    case url(URL)
    case action(FolderPopoverAction)

    var id: String {
        switch self {
        case .url(let url):
            url.absoluteString
        case .action(let action):
            action.id
        }
    }
}

private struct FolderPopoverAction: Identifiable {
    let id: String
    let title: String
    let systemImageName: String
    let handler: () -> Void
}

private struct FolderPopoverItemView: View {
    let url: URL

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: IconCacheService.shared.previewIcon(forFileURL: url))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 112, height: 112)

            Text(displayName)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var displayName: String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
    }
}

private struct FolderPopoverActionItemView: View {
    let action: FolderPopoverAction

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: action.systemImageName)
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.primary)
                .frame(width: 112, height: 112)

            Text(action.title)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct FolderPopoverKeyMonitor: NSViewRepresentable {
    let keyDownHandler: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(keyDownHandler: keyDownHandler)
    }

    func makeNSView(context: Context) -> KeyMonitorView {
        let view = KeyMonitorView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: KeyMonitorView, context: Context) {
        context.coordinator.keyDownHandler = keyDownHandler
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: KeyMonitorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var keyDownHandler: (NSEvent) -> Bool
        private weak var view: NSView?
        private var eventMonitor: Any?

        init(keyDownHandler: @escaping (NSEvent) -> Bool) {
            self.keyDownHandler = keyDownHandler
        }

        func attach(to view: NSView) {
            self.view = view

            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let view = self.view, view.window?.isKeyWindow == true else {
                    return event
                }

                return self.keyDownHandler(event) ? nil : event
            }
        }

        func detach() {
            guard let eventMonitor else { return }
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        deinit {
            detach()
        }
    }
}

private final class KeyMonitorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class FolderQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = FolderQuickLookController()

    private var previewURL: URL?

    func preview(_ url: URL) {
        previewURL = url

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }
}
