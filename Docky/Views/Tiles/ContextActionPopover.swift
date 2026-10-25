//
//  ContextActionPopover.swift
//  Docky
//

import AppKit
import ObjectiveC
import SwiftUI

struct ContextAction: Identifiable {
    enum Kind: Equatable {
        case action
        case submenu
        case lazySubmenu
        case customView
        case divider
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let image: NSImage?
    let customView: NSView?
    let isDestructive: Bool
    let isOn: Bool
    let children: [ContextAction]
    let childrenProvider: (() -> [ContextAction])?
    let handler: () -> Void

    static func action(
        _ title: String,
        image: NSImage? = nil,
        isDestructive: Bool = false,
        isOn: Bool = false,
        handler: @escaping () -> Void
    ) -> Self {
        Self(
            kind: .action,
            title: title,
            image: image,
            customView: nil,
            isDestructive: isDestructive,
            isOn: isOn,
            children: [],
            childrenProvider: nil,
            handler: handler
        )
    }

    static func submenu(_ title: String, children: [ContextAction]) -> Self {
        Self(
            kind: .submenu,
            title: title,
            image: nil,
            customView: nil,
            isDestructive: false,
            isOn: false,
            children: children,
            childrenProvider: nil,
            handler: {}
        )
    }

    static func lazySubmenu(
        _ title: String,
        image: NSImage? = nil,
        childrenProvider: @escaping () -> [ContextAction]
    ) -> Self {
        Self(
            kind: .lazySubmenu,
            title: title,
            image: image,
            customView: nil,
            isDestructive: false,
            isOn: false,
            children: [],
            childrenProvider: childrenProvider,
            handler: {}
        )
    }

    static func customView(_ view: NSView) -> Self {
        Self(
            kind: .customView,
            title: "",
            image: nil,
            customView: view,
            isDestructive: false,
            isOn: false,
            children: [],
            childrenProvider: nil,
            handler: {}
        )
    }

    static var divider: Self {
        Self(
            kind: .divider,
            title: "",
            image: nil,
            customView: nil,
            isDestructive: false,
            isOn: false,
            children: [],
            childrenProvider: nil,
            handler: {}
        )
    }
}

struct ContextActionMenuPresenter: NSViewRepresentable {
    let actionProvider: (NSEvent.ModifierFlags) -> [ContextAction]
    let preferredEdge: NSRectEdge
    let onPresentationChanged: (Bool) -> Void

    init(
        actionProvider: @escaping (NSEvent.ModifierFlags) -> [ContextAction],
        preferredEdge: NSRectEdge = .maxY,
        onPresentationChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.actionProvider = actionProvider
        self.preferredEdge = preferredEdge
        self.onPresentationChanged = onPresentationChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            actionProvider: actionProvider,
            preferredEdge: preferredEdge,
            onPresentationChanged: onPresentationChanged
        )
    }

    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        context.coordinator.update(
            actionProvider: actionProvider,
            preferredEdge: preferredEdge,
            onPresentationChanged: onPresentationChanged
        )
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(for: nsView)
        }
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject {
        private weak var anchorView: NSView?
        private var eventMonitor: Any?
        private var actionProvider: (NSEvent.ModifierFlags) -> [ContextAction]
        private var preferredEdge: NSRectEdge
        private var onPresentationChanged: (Bool) -> Void
        private var isInterruptingAutohide = false

        init(
            actionProvider: @escaping (NSEvent.ModifierFlags) -> [ContextAction],
            preferredEdge: NSRectEdge,
            onPresentationChanged: @escaping (Bool) -> Void
        ) {
            self.actionProvider = actionProvider
            self.preferredEdge = preferredEdge
            self.onPresentationChanged = onPresentationChanged
            super.init()
        }

        func update(
            actionProvider: @escaping (NSEvent.ModifierFlags) -> [ContextAction],
            preferredEdge: NSRectEdge,
            onPresentationChanged: @escaping (Bool) -> Void
        ) {
            self.actionProvider = actionProvider
            self.preferredEdge = preferredEdge
            self.onPresentationChanged = onPresentationChanged
        }

        func installIfNeeded(for anchorView: NSView) {
            self.anchorView = anchorView

            // The monitor is installed regardless of whether the menu has
            // entries. This runs on every view update, and asking the
            // provider here built the whole menu each time just to discard
            // it. `handleContextClick` builds it on demand and lets the
            // click through when it turns out empty.
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                self?.handleContextClick(event) ?? event
            }
        }

        func uninstall() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }

            endAutohideInterruption()
            eventMonitor = nil
            anchorView = nil
        }

        private func handleContextClick(_ event: NSEvent) -> NSEvent? {
            guard let view = anchorView, let window = view.window, event.window === window else {
                return event
            }

            let isRightClick = event.type == .rightMouseDown
            let isControlClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
            guard isRightClick || isControlClick else {
                return event
            }

            let location = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(location) else {
                return event
            }

            let actions = actionProvider(event.modifierFlags)
            guard !actions.isEmpty else {
                return event
            }

            let menu = buildMenu(actions: actions)
            popUpCartouche(menu: menu, in: view)
            return nil
        }

        private func popUpCartouche(menu: NSMenu, in view: NSView) {
            onPresentationChanged(true)
            defer { onPresentationChanged(false) }
            beginAutohideInterruption(for: view)
            defer { endAutohideInterruption() }

            let selector = NSSelectorFromString("_popUpMenuRelativeToRect:inView:preferredEdge:")
            if menu.responds(to: selector) {
                typealias Fn = @convention(c) (NSMenu, Selector, NSRect, NSView?, NSRectEdge) -> Void
                let imp = menu.method(for: selector)
                let fn = unsafeBitCast(imp, to: Fn.self)
                fn(menu, selector, view.bounds, view, preferredEdge)
                return
            }

            menu.update()
            let anchor: NSPoint
            let anchorRect = view.bounds
            switch preferredEdge {
            case .minX:
                anchor = NSPoint(x: anchorRect.minX, y: anchorRect.midY)
            case .maxX:
                anchor = NSPoint(x: anchorRect.maxX, y: anchorRect.midY)
            case .minY:
                anchor = NSPoint(x: anchorRect.midX - menu.size.width / 2, y: anchorRect.minY)
            case .maxY:
                anchor = NSPoint(x: anchorRect.midX - menu.size.width / 2, y: anchorRect.maxY)
            @unknown default:
                anchor = NSPoint(x: anchorRect.midX - menu.size.width / 2, y: anchorRect.maxY)
            }
            menu.popUp(positioning: menu.items.last, at: anchor, in: view)
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

        private func buildMenu(actions: [ContextAction]) -> NSMenu {
            let menu = NSMenu()
            for action in actions {
                addMenuItem(for: action, to: menu)
            }
            return menu
        }

        private func addMenuItem(for action: ContextAction, to menu: NSMenu) {
            switch action.kind {
            case .action:
                let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action
                item.state = action.isOn ? .on : .off
                item.image = thumbnailImage(action.image)
                if action.isDestructive {
                    item.attributedTitle = NSAttributedString(
                        string: action.title,
                        attributes: [.foregroundColor: NSColor.systemRed]
                    )
                }
                menu.addItem(item)
            case .submenu:
                let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
                item.image = thumbnailImage(action.image)
                item.submenu = buildMenu(actions: action.children)
                menu.addItem(item)
            case .lazySubmenu:
                let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
                item.image = thumbnailImage(action.image)
                let submenu = NSMenu(title: action.title)
                let provider = action.childrenProvider ?? { [] }
                let controller = LazyMenuController(provider: provider) { [weak self] menu, children in
                    guard let self else { return }
                    menu.removeAllItems()
                    for child in children {
                        self.addMenuItem(for: child, to: menu)
                    }
                }
                submenu.delegate = controller
                objc_setAssociatedObject(submenu, &lazyMenuControllerKey, controller, .OBJC_ASSOCIATION_RETAIN)
                item.submenu = submenu
                menu.addItem(item)
            case .customView:
                let item = NSMenuItem()
                item.view = action.customView
                menu.addItem(item)
            case .divider:
                menu.addItem(.separator())
            }
        }

        private func thumbnailImage(_ image: NSImage?) -> NSImage? {
            guard let image else { return nil }
            guard let copy = image.copy() as? NSImage else { return image }
            copy.size = NSSize(width: 16, height: 16)
            return copy
        }

        @objc private func runAction(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ContextAction else { return }
            action.handler()
        }
    }
}

private var lazyMenuControllerKey: UInt8 = 0

private final class LazyMenuController: NSObject, NSMenuDelegate {
    private let provider: () -> [ContextAction]
    private let populate: (NSMenu, [ContextAction]) -> Void

    init(
        provider: @escaping () -> [ContextAction],
        populate: @escaping (NSMenu, [ContextAction]) -> Void
    ) {
        self.provider = provider
        self.populate = populate
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu, provider())
    }
}

final class AnchorView: NSView {}

extension ContextActionMenuPresenter {
    /// Imperative entry point for popping the same context menu the
    /// right-click handler would show, anchored to an arbitrary NSView
    /// (typically the background view of a SwiftUI "more" button). The
    /// menu build, autohide interruption, and private
    /// `_popUpMenuRelativeToRect:` call are delegated to a transient
    /// Coordinator so the visual is byte-identical to the right-click
    /// path.
    static func popUpMenu(
        actions: [ContextAction],
        from anchorView: NSView,
        preferredEdge: NSRectEdge = .maxY,
        onPresentationChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        guard !actions.isEmpty else { return }
        let coordinator = Coordinator(
            actionProvider: { _ in actions },
            preferredEdge: preferredEdge,
            onPresentationChanged: onPresentationChanged
        )
        coordinator.presentMenu(actions: actions, from: anchorView)
    }
}

extension ContextActionMenuPresenter.Coordinator {
    /// Exposed for `ContextActionMenuPresenter.popUpMenu` so a button
    /// can imperatively show the menu without going through the
    /// right-click event monitor.
    fileprivate func presentMenu(actions: [ContextAction], from anchorView: NSView) {
        let menu = NSMenu()
        for action in actions {
            addMenuItem(for: action, to: menu)
        }
        popUpCartouche(menu: menu, in: anchorView)
    }
}

/// Glass-styled overlay button that mirrors a card's right-click menu so
/// users with trackpads (or anyone who didn't think to right-click) get
/// the same actions on demand. Wraps an NSView anchor (used both for
/// menu positioning and for hover detection) behind a SwiftUI label so
/// the visual matches Docky's chrome — `.ultraThinMaterial` capsule
/// with a hairline border and a soft shadow against the desaturated
/// thumbnail below it.
struct MoreActionsButton: View {
    let actionProvider: (NSEvent.ModifierFlags) -> [ContextAction]
    let preferredEdge: NSRectEdge
    let onPresentationChanged: (Bool) -> Void

    @State private var triggerCount: Int = 0

    init(
        preferredEdge: NSRectEdge = .maxY,
        onPresentationChanged: @escaping (Bool) -> Void = { _ in },
        actionProvider: @escaping (NSEvent.ModifierFlags) -> [ContextAction]
    ) {
        self.preferredEdge = preferredEdge
        self.onPresentationChanged = onPresentationChanged
        self.actionProvider = actionProvider
    }

    var body: some View {
        Button {
            triggerCount &+= 1
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .help("More actions")
        .background(
            MoreActionsMenuAnchor(
                trigger: triggerCount,
                actionProvider: actionProvider,
                preferredEdge: preferredEdge,
                onPresentationChanged: onPresentationChanged
            )
        )
    }
}

/// Hidden NSView positioned behind `MoreActionsButton` that serves as
/// the menu anchor and listens for trigger changes. Each `trigger`
/// increment from the SwiftUI side pops the menu exactly once.
private struct MoreActionsMenuAnchor: NSViewRepresentable {
    let trigger: Int
    let actionProvider: (NSEvent.ModifierFlags) -> [ContextAction]
    let preferredEdge: NSRectEdge
    let onPresentationChanged: (Bool) -> Void

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        let coordinator = context.coordinator
        coordinator.actionProvider = actionProvider
        coordinator.preferredEdge = preferredEdge
        coordinator.onPresentationChanged = onPresentationChanged

        guard trigger != coordinator.lastTrigger else { return }
        coordinator.lastTrigger = trigger

        // Defer to the next runloop tick so the view has had a chance
        // to be inserted into its window before we try to anchor a
        // menu against it. The first updateNSView fires before the
        // host SwiftUI view is committed.
        DispatchQueue.main.async {
            guard nsView.window != nil else { return }
            let actions = coordinator.actionProvider(NSEvent.modifierFlags)
            ContextActionMenuPresenter.popUpMenu(
                actions: actions,
                from: nsView,
                preferredEdge: coordinator.preferredEdge,
                onPresentationChanged: coordinator.onPresentationChanged
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            actionProvider: actionProvider,
            preferredEdge: preferredEdge,
            onPresentationChanged: onPresentationChanged
        )
    }

    final class Coordinator {
        var actionProvider: (NSEvent.ModifierFlags) -> [ContextAction]
        var preferredEdge: NSRectEdge
        var onPresentationChanged: (Bool) -> Void
        var lastTrigger: Int = 0

        init(
            actionProvider: @escaping (NSEvent.ModifierFlags) -> [ContextAction],
            preferredEdge: NSRectEdge,
            onPresentationChanged: @escaping (Bool) -> Void
        ) {
            self.actionProvider = actionProvider
            self.preferredEdge = preferredEdge
            self.onPresentationChanged = onPresentationChanged
        }
    }
}
