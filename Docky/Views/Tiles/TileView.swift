//
//  TileView.swift
//  Docky
//
//  Generic tile wrapper. Picks a concrete content view based on the tile's
//  case and applies any chrome shared across all tile types (hover, etc).
//

import AppKit
import SwiftUI

struct TileView: View {
    let tile: Tile
    @ObservedObject private var preferences = DockyPreferences.shared
    @State private var isTooltipPresented = false
    @State private var isFolderPopoverPresented = false
    @State private var folderSnapshot: FolderContentsSnapshot = .loaded([])

    private var contextActions: [ContextAction] {
        switch tile.content {
        case .folder(let folder):
            return [
                .action("Open in Finder") {
                    Task {
                        _ = await AppleScriptService.shared.openFinderWindow(for: folder.url)
                    }
                },
                .action("Reveal in Finder") {
                    Task {
                        _ = await AppleScriptService.shared.revealInFinder(folder.url)
                    }
                }
            ]
        case .trash:
            return [
                .action("Open Trash") {
                    Task {
                        _ = await AppleScriptService.shared.openTrash()
                    }
                },
                .divider,
                .action("Empty Trash", isDestructive: true) {
                    Task {
                        _ = await AppleScriptService.shared.emptyTrash()
                    }
                }
            ]
        case .app, .widget, .spacer, .divider:
            return []
        }
    }

    var body: some View {
        content
            .padding(.vertical, preferences.tileVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onHover(perform: updateTooltip)
            .onTapGesture(perform: handleTap)
            .onDisappear {
                isTooltipPresented = false
                isFolderPopoverPresented = false
            }
            .background {
                ContextActionMenuPresenter(actions: contextActions)

                if let tooltipTitle {
                    TileTooltipPopoverPresenter(
                        title: tooltipTitle,
                        isPresented: isTooltipPresented
                    )
                    .allowsHitTesting(false)
                }
            }
            .popover(
                isPresented: $isFolderPopoverPresented,
                attachmentAnchor: .point(.top),
                arrowEdge: .bottom
            ) {
                if case .folder(let folder) = tile.content {
                    FolderPopoverView(
                        tile: folder,
                        initialSnapshot: folderSnapshot,
                        isPresented: $isFolderPopoverPresented
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch tile.content {
        case .app(let app):
            AppTileView(tile: app)
        case .widget(let widget):
            WidgetTileView(tile: widget)
        case .folder(let folder):
            FolderTileView(tile: folder, isOpen: isFolderPopoverPresented)
        case .spacer:
            SpacerTileView()
        case .divider:
            DividerTileView()
        case .trash:
            TrashTileView()
        }
    }

    private var tooltipTitle: String? {
        switch tile.content {
        case .app(let app):
            app.displayName
        case .widget(let widget):
            widget.title
        case .folder(let folder):
            folder.displayName
        case .trash:
            "Trash"
        case .spacer, .divider:
            nil
        }
    }

    private func updateTooltip(isHovering: Bool) {
        isTooltipPresented = isHovering && tooltipTitle != nil && !isFolderPopoverPresented
    }

    private func handleTap() {
        switch tile.content {
        case .folder(let folder):
            isTooltipPresented = false

            if isFolderPopoverPresented {
                isFolderPopoverPresented = false
                return
            }

            folderSnapshot = FolderAccessService.shared.snapshot(of: folder.url)
            isFolderPopoverPresented = true
        case .trash:
            Task {
                _ = await AppleScriptService.shared.openTrash()
            }
        case .app, .widget, .spacer, .divider:
            return
        }
    }

}

private struct TileTooltipView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .fixedSize()
    }
}

private struct TileTooltipPopoverPresenter: NSViewRepresentable {
    let title: String
    let isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title)
    }

    func makeNSView(context: Context) -> TooltipAnchorView {
        TooltipAnchorView()
    }

    func updateNSView(_ nsView: TooltipAnchorView, context: Context) {
        context.coordinator.update(title: title)

        if isPresented {
            context.coordinator.show(relativeTo: nsView)
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ nsView: TooltipAnchorView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator {
        private let hostingController = NSHostingController(rootView: TileTooltipView(title: ""))
        private let popover = NSPopover()

        init(title: String) {
            hostingController.rootView = TileTooltipView(title: title)
            popover.contentViewController = hostingController
            popover.animates = false
            popover.behavior = .applicationDefined
            updateContentSize()
        }

        func update(title: String) {
            hostingController.rootView = TileTooltipView(title: title)
            updateContentSize()
        }

        func show(relativeTo view: NSView) {
            guard view.window != nil, !popover.isShown else { return }
            let anchorRect = NSRect(
                x: view.bounds.midX - 0.5,
                y: view.bounds.maxY - 1,
                width: 1,
                height: 1
            )
            popover.show(relativeTo: anchorRect, of: view, preferredEdge: .maxY)
        }

        func close() {
            popover.performClose(nil)
        }

        private func updateContentSize() {
            let view = hostingController.view
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            hostingController.preferredContentSize = size
            popover.contentSize = size
        }
    }
}

private final class TooltipAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
