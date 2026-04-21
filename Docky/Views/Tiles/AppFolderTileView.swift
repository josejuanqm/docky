//
//  AppFolderTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct AppFolderTileView: View {
    let tile: AppFolderTile
    let isOpen: Bool

    var body: some View {
        VStack(spacing: 2) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            indicatorPlaceholder
        }
    }

    @ViewBuilder
    private var content: some View {
        if isOpen {
            openPlaceholder
        } else {
            GeometryReader { geo in
                iconGrid(in: geo.size)
            }
        }
    }

    private var openPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.primary.opacity(0.16))

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
        }
        .padding(6)
    }

    private func iconGrid(in size: CGSize) -> some View {
        let displayedApps = Array(tile.apps.prefix(4))
        let side = min(size.width, size.height) * 0.36
        let gap = min(size.width, size.height) * 0.06

        return ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }

            VStack(spacing: gap) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            Group {
                                if index < displayedApps.count {
                                    Image(nsImage: IconCacheService.shared.icon(forBundleIdentifier: displayedApps[index].bundleIdentifier))
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.white.opacity(0.06))
                                }
                            }
                            .frame(width: side, height: side)
                        }
                    }
                }
            }
            .padding(size.width * 0.12)
        }
        .padding(4)
    }

    private var indicatorPlaceholder: some View {
        Circle()
            .frame(width: 4, height: 4)
            .foregroundStyle(.clear)
    }
}

struct AppFolderPopoverView: View {
    let tile: AppFolderTile
    @Binding var isPresented: Bool
    let onPopoverSizeChange: (CGSize) -> Void

    private let columns = 3
    private let itemWidth: CGFloat = 112
    private let itemHeight: CGFloat = 132
    private let itemSpacing: CGFloat = 12
    private let contentPadding: CGFloat = 20
    private let headerHeight: CGFloat = 42
    private let maxHeight: CGFloat = 620

    init(
        tile: AppFolderTile,
        isPresented: Binding<Bool>,
        onPopoverSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.tile = tile
        _isPresented = isPresented
        self.onPopoverSizeChange = onPopoverSizeChange
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tile.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, contentPadding)
            .padding(.top, 16)
            .frame(height: headerHeight)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: gridColumns, spacing: itemSpacing) {
                    ForEach(tile.apps, id: \.bundleIdentifier) { app in
                        Button {
                            WorkspaceService.shared.activateOrOpen(bundleIdentifier: app.bundleIdentifier)
                            isPresented = false
                        } label: {
                            VStack(spacing: 8) {
                                Image(nsImage: IconCacheService.shared.icon(forBundleIdentifier: app.bundleIdentifier))
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 72, height: 72)

                                Text(app.displayName)
                                    .font(.callout)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.primary)
                            }
                            .frame(width: itemWidth, height: itemHeight)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(contentPadding)
            }
        }
        .frame(width: popoverSize.width, height: popoverSize.height)
        .background(.ultraThinMaterial)
        .onAppear {
            onPopoverSizeChange(popoverSize)
        }
        .onChange(of: tile.apps.count) { _, _ in
            onPopoverSizeChange(popoverSize)
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(itemWidth), spacing: itemSpacing, alignment: .top), count: columns)
    }

    private var rowCount: Int {
        max(Int(ceil(Double(tile.apps.count) / Double(columns))), 1)
    }

    private var popoverSize: CGSize {
        let width = CGFloat(columns) * itemWidth + CGFloat(columns - 1) * itemSpacing + contentPadding * 2
        let gridHeight = CGFloat(rowCount) * itemHeight + CGFloat(max(rowCount - 1, 0)) * itemSpacing
        let height = min(gridHeight + contentPadding * 2 + headerHeight + 16, maxHeight)
        return CGSize(width: width, height: height)
    }
}

struct AppFolderPopoverPresenter: NSViewRepresentable {
    let tile: AppFolderTile
    @Binding var isPresented: Bool
    let preferredEdge: NSRectEdge

    func makeCoordinator() -> Coordinator {
        Coordinator(tile: tile, isPresented: $isPresented, preferredEdge: preferredEdge)
    }

    func makeNSView(context: Context) -> AppFolderPopoverAnchorView {
        AppFolderPopoverAnchorView()
    }

    func updateNSView(_ nsView: AppFolderPopoverAnchorView, context: Context) {
        context.coordinator.update(tile: tile, isPresented: $isPresented, preferredEdge: preferredEdge)

        if isPresented {
            context.coordinator.show(relativeTo: nsView)
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ nsView: AppFolderPopoverAnchorView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        private let popover = NSPopover()
        private let hostingController = NSHostingController(
            rootView: AppFolderPopoverView(
                tile: AppFolderTile(identifier: "", displayName: "", apps: []),
                isPresented: .constant(false)
            )
        )
        private var isPresented: Binding<Bool>
        private var preferredEdge: NSRectEdge
        private var lastContentSize = NSSize(width: 384, height: 240)
        private weak var anchorView: NSView?
        private var isInterruptingAutohide = false

        init(tile: AppFolderTile, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
            super.init()
            popover.contentViewController = hostingController
            popover.animates = true
            popover.behavior = .transient
            popover.delegate = self
            update(tile: tile, isPresented: isPresented, preferredEdge: preferredEdge)
        }

        func update(tile: AppFolderTile, isPresented: Binding<Bool>, preferredEdge: NSRectEdge) {
            self.isPresented = isPresented
            self.preferredEdge = preferredEdge
            hostingController.rootView = AppFolderPopoverView(
                tile: tile,
                isPresented: isPresented,
                onPopoverSizeChange: { [weak self] size in
                    self?.updateContentSize(size)
                }
            )
        }

        func show(relativeTo view: NSView) {
            guard view.window != nil, !popover.isShown else { return }
            anchorView = view
            beginAutohideInterruption(for: view)
            updateContentSize(lastContentSize)
            popover.show(relativeTo: anchorRect(in: view.bounds), of: view, preferredEdge: preferredEdge)
        }

        func close() {
            endAutohideInterruption()
            popover.performClose(nil)
        }

        func popoverDidClose(_ notification: Notification) {
            endAutohideInterruption()
            guard isPresented.wrappedValue else { return }
            DispatchQueue.main.async { [isPresented] in
                isPresented.wrappedValue = false
            }
        }

        private func beginAutohideInterruption(for view: NSView) {
            guard !isInterruptingAutohide else { return }
            (view.window as? MainWindow)?.beginInteraction()
            isInterruptingAutohide = true
        }

        private func endAutohideInterruption() {
            guard isInterruptingAutohide else { return }
            (anchorView?.window as? MainWindow)?.endInteraction()
            isInterruptingAutohide = false
        }

        private func updateContentSize(_ size: CGSize) {
            let contentSize = NSSize(width: size.width, height: size.height)
            guard contentSize.width > 0, contentSize.height > 0 else { return }
            lastContentSize = contentSize
            hostingController.preferredContentSize = contentSize
            popover.contentSize = contentSize
        }

        private func anchorRect(in bounds: NSRect) -> NSRect {
            switch preferredEdge {
            case .minX:
                NSRect(x: bounds.minX, y: bounds.midY - 0.5, width: 1, height: 1)
            case .maxX:
                NSRect(x: bounds.maxX - 1, y: bounds.midY - 0.5, width: 1, height: 1)
            case .minY:
                NSRect(x: bounds.midX - 0.5, y: bounds.minY, width: 1, height: 1)
            case .maxY:
                NSRect(x: bounds.midX - 0.5, y: bounds.maxY - 1, width: 1, height: 1)
            @unknown default:
                NSRect(x: bounds.midX - 0.5, y: bounds.maxY - 1, width: 1, height: 1)
            }
        }
    }
}

final class AppFolderPopoverAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
