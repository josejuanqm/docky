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
    @State private var currentEntry: FolderPopoverEntry
    @State private var backHistory: [FolderPopoverEntry]
    @State private var selectedItemID: String?
    @State private var isDropTargeted = false

    private let maxGridColumnCount = 6
    private let gridItemWidth: CGFloat = 144
    private let gridItemHeight: CGFloat = 158
    private let gridItemSpacing: CGFloat = 8
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
        bodyContent
            .onDrop(of: [UTType.fileURL], delegate: FolderPopoverDropDelegate(
                destinationURL: currentEntry.url,
                isTargeted: $isDropTargeted,
                onDrop: handleDroppedItems
            ))
            .task(id: reloadKey) {
                currentEntry = refreshedEntry(for: currentEntry)
                backHistory = backHistory.map(refreshedEntry(for:))
                selectDefaultItemIfNeeded()
                reportPopoverSize()
            }
            .background(.ultraThinMaterial)
            .background {
                FolderPopoverKeyMonitor { event in
                    handleKeyDown(event)
                }
            }
            .onAppear {
                selectDefaultItemIfNeeded()
                reportPopoverSize()
            }
            .onChange(of: popoverSize) { _, _ in
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
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 2)
                    .padding(8)
                    .allowsHitTesting(false)
            }
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
                            FolderPopoverItemView(url: itemURL, isSelected: selectedItemID == item.id)
                        case .action(let action):
                            FolderPopoverActionItemView(action: action, isSelected: selectedItemID == item.id)
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
                    [
                        .action("Reveal in Finder") {
                            revealInFinder(itemURL)
                        },
                        .action("Open in Finder") {
                            openInFinder(itemURL)
                        }
                    ]
                }
            }
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
        "\(tile.url.path)|\(permissions.userFolders)|\(isPresented)"
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

    private func reportPopoverSize() {
        onPopoverSizeChange(popoverSize)
    }

    private func handleDroppedItems(_ itemURLs: [URL]) {
        guard !itemURLs.isEmpty else { return }

        let destinationURL = currentEntry.url
        let didMoveAnyItems = itemURLs.reduce(into: false) { didMoveAnyItems, itemURL in
            guard shouldAcceptDrop(itemURL, into: destinationURL) else {
                return
            }

            let destinationItemURL = uniqueDestinationURL(for: itemURL, in: destinationURL)
            do {
                try FileManager.default.moveItem(at: itemURL, to: destinationItemURL)
                didMoveAnyItems = true
            } catch {
                presentDropError(for: itemURL, error: error)
            }
        }

        guard didMoveAnyItems else { return }
        currentEntry = refreshedEntry(for: currentEntry)
        backHistory = backHistory.map(refreshedEntry(for:))
        selectDefaultItemIfNeeded()
        reportPopoverSize()
    }

    private func shouldAcceptDrop(_ itemURL: URL, into destinationURL: URL) -> Bool {
        let standardizedItemURL = itemURL.standardizedFileURL
        let standardizedDestinationURL = destinationURL.standardizedFileURL

        guard standardizedItemURL != standardizedDestinationURL else {
            return false
        }

        return !standardizedDestinationURL.path.hasPrefix(standardizedItemURL.path + "/")
    }

    private func uniqueDestinationURL(for itemURL: URL, in destinationURL: URL) -> URL {
        let fileManager = FileManager.default
        let fileExtension = itemURL.pathExtension
        let baseName = itemURL.deletingPathExtension().lastPathComponent
        var candidateURL = destinationURL.appending(path: itemURL.lastPathComponent)
        var duplicateIndex = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            let candidateName = if fileExtension.isEmpty {
                "\(baseName) \(duplicateIndex)"
            } else {
                "\(baseName) \(duplicateIndex).\(fileExtension)"
            }
            candidateURL = destinationURL.appending(path: candidateName)
            duplicateIndex += 1
        }

        return candidateURL
    }

    private func presentDropError(for itemURL: URL, error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't add item to folder"
        alert.informativeText = "Docky couldn't move \(displayName(for: itemURL)) into \(currentEntry.displayName). \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct FolderPopoverDropDelegate: DropDelegate {
    let destinationURL: URL
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = validateDrop(info: info)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false

        let providers = info.itemProviders(for: [UTType.fileURL])
        guard !providers.isEmpty else {
            return false
        }

        resolveURLs(from: providers) { itemURLs in
            let acceptedURLs = itemURLs.filter { $0.isFileURL }
            guard !acceptedURLs.isEmpty else { return }
            DispatchQueue.main.async {
                onDrop(acceptedURLs)
            }
        }
        return true
    }

    private func resolveURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let dispatchGroup = DispatchGroup()
        let lock = NSLock()
        var resolvedURLs: [URL] = []

        for provider in providers {
            dispatchGroup.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { dispatchGroup.leave() }
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                lock.lock()
                resolvedURLs.append(url)
                lock.unlock()
            }
        }

        dispatchGroup.notify(queue: .global(qos: .userInitiated)) {
            completion(resolvedURLs)
        }
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
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: IconCacheService.shared.icon(forFileURL: url))
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? .white.opacity(0.12) : .white.opacity(0.001))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? .white.opacity(0.22) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var displayName: String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
    }
}

private struct FolderPopoverActionItemView: View {
    let action: FolderPopoverAction
    let isSelected: Bool

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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? .white.opacity(0.12) : .white.opacity(0.001))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? .white.opacity(0.22) : .clear)
        )
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

private final class FolderQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
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
