//
//  SmartStackTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct SmartStackTileView: View {
    let tile: SmartStackTile

    @State private var selection = 0
    @State private var isHovering = false
    @State private var scrollMonitor: Any?
    @State private var lastScrollAt: TimeInterval = 0

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    ForEach(Array(tile.widgets.enumerated()), id: \.element.identifier) { index, widget in
                        WidgetTileView(tile: widget)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .offset(y: -CGFloat(selection) * proxy.size.height)
                .animation(.easeInOut(duration: 0.2), value: selection)
            }
            .clipped()

            VStack(spacing: 5) {
                ForEach(tile.widgets.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == selection ? Color.primary.opacity(0.9) : Color.primary.opacity(0.22))
                        .frame(width: 3, height: index == selection ? 18 : 8)
                        .animation(.easeInOut(duration: 0.18), value: selection)
                }
            }
            .frame(width: 6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onHover { isHovering = $0 }
        .onAppear(perform: installScrollMonitor)
        .onDisappear(perform: removeScrollMonitor)
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else {
            return
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard isHovering else {
                return event
            }

            if handleScroll(deltaY: event.scrollingDeltaY) {
                return nil
            }

            return event
        }
    }

    private func removeScrollMonitor() {
        guard let scrollMonitor else {
            return
        }

        NSEvent.removeMonitor(scrollMonitor)
        self.scrollMonitor = nil
    }

    private func handleScroll(deltaY: CGFloat) -> Bool {
        guard tile.widgets.count > 1 else {
            return false
        }

        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastScrollAt > 0.2 else {
            return true
        }

        let threshold: CGFloat = 4
        if deltaY <= -threshold {
            selection = min(selection + 1, tile.widgets.count - 1)
            lastScrollAt = now
            return true
        }

        if deltaY >= threshold {
            selection = max(selection - 1, 0)
            lastScrollAt = now
            return true
        }

        return false
    }
}
