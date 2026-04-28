//
//  DockEditorOverlayWindowController.swift
//  Docky
//

import AppKit
import Combine
import SwiftUI

private enum DockEditorGalleryCategory: String, CaseIterable, Identifiable {
    case all
    case widgets
    case utility

    var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .all:
            "All"
        case .widgets:
            "Widgets"
        case .utility:
            "Utility"
        }
    }
}

private enum DockEditorPreviewScale: Equatable {
    case card
    case detail

    var tileSize: CGFloat {
        switch self {
        case .card:
            62
        case .detail:
            90
        }
    }

    var tileHeight: CGFloat {
        switch self {
        case .card:
            90
        case .detail:
            122
        }
    }

    var tileSpacing: CGFloat {
        switch self {
        case .card:
            10
        case .detail:
            12
        }
    }

    var utilityWidth: CGFloat {
        switch self {
        case .card:
            174
        case .detail:
            240
        }
    }

    var canvasHeight: CGFloat {
        switch self {
        case .card:
            126
        case .detail:
            236
        }
    }
}

private struct DockEditorGalleryItem: Equatable, Identifiable {
    let paletteItem: DockEditPaletteItem
    let title: String
    let subtitle: String
    let iconName: String
    let category: DockEditorGalleryCategory
    let supportedSpans: [TileSpan]
    let defaultSpan: TileSpan?
    let searchIndex: String

    var id: String {
        paletteItem.id
    }

    var allowsSpanSelection: Bool {
        supportedSpans.count > 1
    }

    var isFixedSpanItem: Bool {
        !supportedSpans.isEmpty && !allowsSpanSelection
    }

    func resolvedSpan(selectedSpan: TileSpan?) -> TileSpan? {
        guard !supportedSpans.isEmpty else {
            return nil
        }

        if let selectedSpan, supportedSpans.contains(selectedSpan) {
            return selectedSpan
        }

        if let defaultSpan, supportedSpans.contains(defaultSpan) {
            return defaultSpan
        }

        return supportedSpans.last ?? supportedSpans.first
    }

    func sizeBadgeText(selectedSpan: TileSpan?) -> String? {
        guard let resolvedSpan = resolvedSpan(selectedSpan: selectedSpan) else {
            return nil
        }

        if isFixedSpanItem {
            return "\(resolvedSpan.rawValue)x"
        }

        if let firstSpan = supportedSpans.first,
           let lastSpan = supportedSpans.last,
           firstSpan != lastSpan {
            return "\(firstSpan.rawValue)-\(lastSpan.rawValue)x"
        }

        return "\(resolvedSpan.rawValue)x"
    }

    func matches(searchText: String) -> Bool {
        let normalizedSearchText = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        guard !normalizedSearchText.isEmpty else {
            return true
        }

        return searchIndex.contains(normalizedSearchText)
    }

    nonisolated static let allItems: [DockEditorGalleryItem] = WidgetCatalog.paletteRegistrations.map(Self.makeWidgetItem)
        + [makeSmartStackItem()]
        + [makeUtilityItem(.spacer), makeUtilityItem(.divider)]

    nonisolated private static func makeWidgetItem(registration: WidgetRegistration) -> Self {
        let paletteItem = DockEditPaletteItem.widget(
            ownerBundleIdentifier: registration.ownerBundleIdentifier,
            kind: registration.kind
        )
        return Self(
            paletteItem: paletteItem,
            title: registration.kind.title,
            subtitle: subtitle(for: registration.kind),
            iconName: iconName(for: paletteItem),
            category: .widgets,
            supportedSpans: registration.kind.supportedSpans,
            defaultSpan: registration.defaultSpan,
            searchIndex: makeSearchIndex(
                title: registration.kind.title,
                subtitle: subtitle(for: registration.kind),
                category: .widgets,
                extraTerms: [registration.kind.rawValue, "widget"]
            )
        )
    }

    nonisolated private static func makeSmartStackItem() -> Self {
        let paletteItem = DockEditPaletteItem.smartStack
        return Self(
            paletteItem: paletteItem,
            title: "Smart Stack",
            subtitle: "Stacks available widgets into a single tile you can scroll through.",
            iconName: iconName(for: paletteItem),
            category: .widgets,
            supportedSpans: [.three],
            defaultSpan: .three,
            searchIndex: makeSearchIndex(
                title: "Smart Stack",
                subtitle: "Stacks available widgets into a single tile you can scroll through.",
                category: .widgets,
                extraTerms: ["stack", "smart"]
            )
        )
    }

    nonisolated private static func makeUtilityItem(_ paletteItem: DockEditPaletteItem) -> Self {
        Self(
            paletteItem: paletteItem,
            title: title(for: paletteItem),
            subtitle: subtitle(for: paletteItem),
            iconName: iconName(for: paletteItem),
            category: .utility,
            supportedSpans: [],
            defaultSpan: nil,
            searchIndex: makeSearchIndex(
                title: title(for: paletteItem),
                subtitle: subtitle(for: paletteItem),
                category: .utility,
                extraTerms: ["utility"]
            )
        )
    }

    nonisolated private static func title(for item: DockEditPaletteItem) -> String {
        switch item {
        case .spacer:
            "Spacer"
        case .divider:
            "Divider"
        case .widget(_, let kind):
            kind.title
        case .smartStack:
            "Smart Stack"
        }
    }

    nonisolated private static func subtitle(for item: DockEditPaletteItem) -> String {
        switch item {
        case .spacer:
            "Adds breathing room between pinned tiles or folders."
        case .divider:
            "Adds a visual separator to break up sections in the dock."
        case .widget(_, let kind):
            subtitle(for: kind)
        case .smartStack:
            "Stacks available widgets into a single tile you can scroll through."
        }
    }

    nonisolated private static func subtitle(for kind: WidgetKind) -> String {
        switch kind {
        case .calendar:
            "Shows the current date and month at a glance."
        case .calendarDate:
            "Shows the weekday and date number at a glance."
        case .reminders:
            "Shows your open tasks and what needs attention next."
        case .batteries:
            "Shows Mac and accessory battery levels at a glance."
        case .systemStatus:
            "Shows CPU, memory, and network activity at a glance."
        case .nowPlaying:
            "Shows the currently playing media with quick playback control."
        case .weather:
            "Shows current weather for your location."
        }
    }

    nonisolated private static func iconName(for item: DockEditPaletteItem) -> String {
        switch item {
        case .spacer:
            "rectangle.split.3x1"
        case .divider:
            "line.3.horizontal.decrease"
        case .widget(_, let kind):
            switch kind {
            case .calendar, .calendarDate:
                "calendar"
            case .reminders:
                "checklist"
            case .batteries:
                "battery.100percent"
            case .systemStatus:
                "gauge.with.needle"
            case .nowPlaying:
                "waveform"
            case .weather:
                "cloud.sun.fill"
            }
        case .smartStack:
            "square.stack.3d.up"
        }
    }

    nonisolated private static func makeSearchIndex(
        title: String,
        subtitle: String,
        category: DockEditorGalleryCategory,
        extraTerms: [String]
    ) -> String {
        ([title, subtitle, category.title] + extraTerms)
            .joined(separator: " ")
            .localizedLowercase
    }
}

final class DockEditorOverlayWindowController: NSWindowController {
    private weak var mainWindow: MainWindow?
    private var cancellables: Set<AnyCancellable> = []
    private let overlayState = DockEditorOverlayState()

    init(mainWindow: MainWindow) {
        self.mainWindow = mainWindow

        let overlayWindow = DockEditorOverlayWindow()
        let hostingController = NSHostingController(rootView: DockEditorOverlayView(state: overlayState))
        overlayWindow.contentViewController = hostingController

        super.init(window: overlayWindow)

        observeEditMode()
        observeMainWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func observeEditMode() {
        DockEditModeService.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self else { return }
                if isActive {
                    self.presentOverlay()
                } else {
                    self.dismissOverlay()
                }
            }
            .store(in: &cancellables)
    }

    private func observeMainWindow() {
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: mainWindow)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: mainWindow))
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification, object: mainWindow))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFrame()
            }
            .store(in: &cancellables)
    }

    private func presentOverlay() {
        updateFrame()
        overlayState.ensureSelection(in: DockEditorGalleryItem.allItems)
        guard let window, let mainWindow else {
            return
        }

        window.level = NSWindow.Level.floating
        window.orderFront(nil)
        mainWindow.orderFrontRegardless()
    }

    private func dismissOverlay() {
        guard let window else {
            return
        }

        window.orderOut(nil)
    }

    private func updateFrame() {
        guard let window else {
            return
        }

        let screenFrame = mainWindow?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        window.setFrame(screenFrame.integral, display: true)

        if let mainWindow {
            overlayState.dockFrame = CGRect(
                x: mainWindow.frame.minX - screenFrame.minX,
                y: screenFrame.maxY - mainWindow.frame.maxY,
                width: mainWindow.frame.width,
                height: mainWindow.frame.height
            ).integral
        } else {
            overlayState.dockFrame = .zero
        }
    }
}

private final class DockEditorOverlayState: ObservableObject {
    @Published var dockFrame: CGRect = .zero
    @Published var searchText = ""
    @Published var selectedCategory: DockEditorGalleryCategory = .all
    @Published var selectedItemID: String?
    @Published private var selectedSpansByItemID: [String: TileSpan] = [:]

    func ensureSelection(in items: [DockEditorGalleryItem]) {
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }

        if let selectedItemID, items.contains(where: { $0.id == selectedItemID }) {
            return
        }

        selectedItemID = items[0].id
    }

    func selectedSpan(for item: DockEditorGalleryItem) -> TileSpan? {
        item.resolvedSpan(selectedSpan: selectedSpansByItemID[item.id])
    }

    func setSelectedSpan(_ span: TileSpan, for item: DockEditorGalleryItem) {
        guard item.supportedSpans.contains(span) else {
            return
        }

        selectedSpansByItemID[item.id] = span
    }
}

private final class DockEditorOverlayWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct DockEditorOverlayView: View {
    private let paletteDockGap: CGFloat = 28

    @ObservedObject var state: DockEditorOverlayState
    @ObservedObject private var editMode = DockEditModeService.shared
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        GeometryReader { proxy in
            let cutoutFrame = state.dockFrame
            let cornerRadius = preferences.windowClipShape.resolvedCornerRadius(
                base: preferences.windowCornerRadius,
                maximum: min(cutoutFrame.width, cutoutFrame.height) / 2
            )

            ZStack {
                OverlayCutoutShape(cutoutFrame: cutoutFrame, cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial, style: FillStyle(eoFill: true))
                    .overlay {
                        OverlayCutoutShape(cutoutFrame: cutoutFrame, cornerRadius: cornerRadius)
                            .fill(Color.black.opacity(0.34), style: FillStyle(eoFill: true))
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editMode.exit()
                    }

                layout(in: proxy.size)
                    .padding(28)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func layout(in availableSize: CGSize) -> some View {
        switch position {
        case .bottom:
            VStack {
                Spacer()
                editorBrowser(in: availableSize)
                    .padding(.bottom, paletteInset)
            }
        case .top:
            VStack {
                editorBrowser(in: availableSize)
                    .padding(.top, paletteInset)
                Spacer()
            }
        case .left:
            HStack {
                editorBrowser(in: availableSize)
                    .padding(.leading, paletteInset)
                Spacer()
            }
        case .right:
            HStack {
                Spacer()
                editorBrowser(in: availableSize)
                    .padding(.trailing, paletteInset)
            }
        }
    }

    private func editorBrowser(in availableSize: CGSize) -> some View {
        DockEditorBrowserView(
            state: state,
            panelSize: browserSize(in: availableSize)
        )
    }

    private var position: ResolvedDockWindowPosition {
        preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    private var paletteInset: CGFloat {
        switch position {
        case .bottom, .top:
            state.dockFrame.height + paletteDockGap
        case .left, .right:
            state.dockFrame.width + paletteDockGap
        }
    }

    private func browserSize(in availableSize: CGSize) -> CGSize {
        let crossAxisPadding: CGFloat = 56
        let panelMargin: CGFloat = 48

        let availableWidth = max(
            680,
            availableSize.width - crossAxisPadding - (position.isVertical ? paletteInset : 0)
        )
        let availableHeight = max(
            480,
            availableSize.height - crossAxisPadding - (position.isVertical ? 0 : paletteInset)
        )

        return CGSize(
            width: min(position.isVertical ? 960 : 1120, availableWidth),
            height: min(720, availableHeight - panelMargin)
        )
    }
}

private struct OverlayCutoutShape: Shape {
    let cutoutFrame: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)

        if !cutoutFrame.isEmpty {
            path.addRoundedRect(
                in: cutoutFrame,
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
                style: .continuous
            )
        }

        return path
    }
}

private struct DockEditorGalleryVariant: Identifiable {
    let item: DockEditorGalleryItem
    let span: TileSpan?

    var id: String {
        if let span {
            return "\(item.id):\(span.rawValue)x"
        }

        return item.id
    }

    var title: String {
        guard let span, item.supportedSpans.count > 1 else {
            return item.title
        }

        return "\(item.title) \(span.rawValue)x"
    }

    var subtitle: String {
        item.subtitle
    }

    var sizeBadgeText: String? {
        span.map { "\($0.rawValue)x" }
    }
}

private struct DockEditorGallerySection: Identifiable {
    let item: DockEditorGalleryItem
    let variants: [DockEditorGalleryVariant]

    var id: String {
        item.id
    }

    nonisolated init(item: DockEditorGalleryItem) {
        self.item = item

        if item.supportedSpans.isEmpty {
            variants = [DockEditorGalleryVariant(item: item, span: nil)]
        } else {
            variants = item.supportedSpans.map { span in
                DockEditorGalleryVariant(item: item, span: span)
            }
        }
    }
}

private struct DockEditorBrowserView: View {
    @ObservedObject var state: DockEditorOverlayState
    let panelSize: CGSize

    @ObservedObject private var editMode = DockEditModeService.shared

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3)

    private var visibleSections: [DockEditorGallerySection] {
        DockEditorGalleryItem.allItems
            .filter { $0.matches(searchText: state.searchText) }
            .map(DockEditorGallerySection.init(item:))
    }

    private var totalVisibleVariants: Int {
        visibleSections.reduce(0) { $0 + $1.variants.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            horizontalSeparator

            if visibleSections.isEmpty {
                emptyResultsView
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibleSections.enumerated()), id: \.element.id) { index, section in
                            if index > 0 {
                                horizontalSeparator
                                    .padding(.vertical, 24)
                            }

                            sectionView(section)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 30, y: 16)
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Edit Dock")
                    .font(.title3.weight(.semibold))
                Text("Browse each dock item type below, then drag any variant directly into the dock.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search widgets and utility items", text: $state.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 300)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }


            Button("Done") {
                editMode.exit()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private func sectionView(_ section: DockEditorGallerySection) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(section.item.title)
                    .font(.title3.weight(.semibold))

                Text(section.variants.count == 1 ? "1 variant" : "\(section.variants.count) variants")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                ForEach(section.variants) { variant in
                    DockEditorGalleryVariantCard(
                        variant: variant,
                        onDrag: {
                            startDrag(for: variant)
                        }
                    )
                }
            }
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)

            Text("No matching items")
                .font(.headline)

            Text("Try a different search term to bring sections back into view.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var horizontalSeparator: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
    }

    private func startDrag(for variant: DockEditorGalleryVariant) -> NSItemProvider {
        editMode.beginPaletteDrag(item: variant.item.paletteItem, widgetSpan: variant.span)
        return NSItemProvider(object: variant.id as NSString)
    }
}

private struct DockEditorGalleryVariantCard: View {
    let variant: DockEditorGalleryVariant
    let onDrag: () -> NSItemProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                DockEditorItemPreview(item: variant.item, selectedSpan: variant.span, scale: .card)
                    .onDrag(onDrag)
            }
            .frame(maxWidth: .infinity, minHeight: DockEditorPreviewScale.card.canvasHeight)

            VStack(alignment: .center, spacing: 4) {
                Text(variant.title)
                    .font(.headline)

                Text(variant.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct DockEditorItemPreview: View {
    let item: DockEditorGalleryItem
    let selectedSpan: TileSpan?
    let scale: DockEditorPreviewScale

    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        let previewSize = size
        let cornerRadius = preferences.tileClipShape.resolvedCornerRadius(
            base: previewSize.height * 0.22,
            maximum: previewSize.height / 2
        )

        ZStack {
            switch item.paletteItem {
            case .widget(let ownerBundleIdentifier, let kind):
                WidgetTileView(
                    tile: WidgetTile(
                        identifier: "editor-preview:\(item.id)",
                        title: item.title,
                        kind: kind,
                        ownerBundleIdentifier: ownerBundleIdentifier,
                        span: item.resolvedSpan(selectedSpan: selectedSpan) ?? .one
                    ),
                    cornerRadius: cornerRadius,
                    renderedSpan: item.resolvedSpan(selectedSpan: selectedSpan) ?? .one,
                    isWithinStack: false
                )
                .frame(width: previewSize.width, height: previewSize.height)
            case .smartStack:
                SmartStackTileView(
                    tile: SmartStackTile(
                        identifier: "editor-preview:smart-stack",
                        title: item.title,
                        widgets: WidgetCatalog.smartStackRegistrations.map { $0.makeTile() },
                        span: .three
                    ),
                    cornerRadius: cornerRadius,
                    renderedSpan: .three
                )
                .frame(width: previewSize.width, height: previewSize.height)
            case .spacer:
                DockEditorUtilityPreview(kind: .spacer, scale: scale)
                    .frame(width: previewSize.width, height: previewSize.height)
            case .divider:
                DockEditorUtilityPreview(kind: .divider, scale: scale)
                    .frame(width: previewSize.width, height: previewSize.height)
            }
        }
        .frame(maxWidth: .infinity, minHeight: scale.canvasHeight)
    }

    private var size: CGSize {
        switch item.paletteItem {
        case .widget:
            let span = CGFloat((item.resolvedSpan(selectedSpan: selectedSpan) ?? .one).rawValue)
            return CGSize(
                width: max(scale.tileSize + scale.tileSpacing, scale.tileHeight) * span,
                height: scale.tileHeight
            )
        case .smartStack:
            let span: CGFloat = 3
            return CGSize(
                width: scale.tileSize * span + scale.tileSpacing * max(CGFloat(0), span - 1),
                height: scale.tileHeight
            )
        case .spacer, .divider:
            return CGSize(width: scale.utilityWidth, height: scale.tileHeight)
        }
    }
}

private struct DockEditorUtilityPreview: View {
    enum Kind {
        case spacer
        case divider
    }

    let kind: Kind
    let scale: DockEditorPreviewScale

    var body: some View {
        HStack(spacing: scale.tileSpacing + 6) {
            tileBlock

            switch kind {
            case .spacer:
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.32), style: StrokeStyle(lineWidth: 2, dash: [5, 6]))
                    .frame(width: scale == .card ? 34 : 48, height: 10)
            case .divider:
                Rectangle()
                    .fill(.white.opacity(0.28))
                    .frame(width: 1, height: scale.tileHeight * 0.72)
            }

            tileBlock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tileBlock: some View {
        RoundedRectangle(cornerRadius: scale.tileHeight * 0.24, style: .continuous)
            .fill(.white.opacity(0.14))
            .frame(width: scale.tileHeight * 0.78, height: scale.tileHeight * 0.78)
            .overlay {
                RoundedRectangle(cornerRadius: scale.tileHeight * 0.24, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
    }
}
