//
//  ContextActionPopover.swift
//  Docky
//

import AppKit
import SwiftUI

struct ContextAction: Identifiable {
    enum Kind {
        case action
        case divider
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let isDestructive: Bool
    let handler: () -> Void

    static func action(_ title: String, isDestructive: Bool = false, handler: @escaping () -> Void) -> Self {
        Self(kind: .action, title: title, isDestructive: isDestructive, handler: handler)
    }

    static var divider: Self {
        Self(kind: .divider, title: "", isDestructive: false, handler: {})
    }
}

struct ContextActionMenuPresenter: NSViewRepresentable {
    let actions: [ContextAction]

    func makeCoordinator() -> Coordinator {
        Coordinator(actions: actions)
    }

    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        context.coordinator.update(actions: actions)
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
        private var actions: [ContextAction]

        init(actions: [ContextAction]) {
            self.actions = actions
            super.init()
        }

        func update(actions: [ContextAction]) {
            self.actions = actions
        }

        func installIfNeeded(for anchorView: NSView) {
            self.anchorView = anchorView

            guard !actions.isEmpty else {
                uninstall()
                return
            }

            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                self?.handleContextClick(event) ?? event
            }
        }

        func uninstall() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }

            eventMonitor = nil
            anchorView = nil
        }

        private func handleContextClick(_ event: NSEvent) -> NSEvent? {
            guard let view = anchorView, let window = view.window, event.window === window, !actions.isEmpty else {
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

            let menu = buildMenu()
            popUpCartouche(menu: menu, in: view)
            return nil
        }

        private func popUpCartouche(menu: NSMenu, in view: NSView) {
            let selector = NSSelectorFromString("_popUpMenuRelativeToRect:inView:preferredEdge:")
            if menu.responds(to: selector) {
                typealias Fn = @convention(c) (NSMenu, Selector, NSRect, NSView?, NSRectEdge) -> Void
                let imp = menu.method(for: selector)
                let fn = unsafeBitCast(imp, to: Fn.self)
                fn(menu, selector, view.bounds, view, .maxY)
                return
            }

            menu.update()
            let anchor = NSPoint(
                x: view.bounds.midX - menu.size.width / 2,
                y: view.bounds.maxY
            )
            menu.popUp(positioning: menu.items.last, at: anchor, in: view)
        }

        private func buildMenu() -> NSMenu {
            let menu = NSMenu()
            for action in actions {
                switch action.kind {
                case .action:
                    let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = action
                    if action.isDestructive {
                        item.attributedTitle = NSAttributedString(
                            string: action.title,
                            attributes: [.foregroundColor: NSColor.systemRed]
                        )
                    }
                    menu.addItem(item)
                case .divider:
                    menu.addItem(.separator())
                }
            }
            return menu
        }

        @objc private func runAction(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? ContextAction else { return }
            action.handler()
        }
    }
}

final class AnchorView: NSView {}
