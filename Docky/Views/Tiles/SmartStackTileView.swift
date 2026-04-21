//
//  SmartStackTileView.swift
//  Docky
//

import AppKit
import SwiftUI

struct SmartStackTileView: View {
    let tile: SmartStackTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan

    @State private var selection = 0
    @State private var isHovering = false
    @State private var scrollMonitor: Any?
    @State private var lastScrollAt: TimeInterval = 0

    var body: some View {
        Group {
            if tile.widgets.isEmpty {
                emptyState
            } else {
                HStack(spacing: 8) {
                    GeometryReader { proxy in
                        VStack(spacing: 0) {
                            ForEach(Array(tile.widgets.enumerated()), id: \.element.identifier) { index, widget in
                                WidgetTileView(
                                    tile: widget,
                                    cornerRadius: cornerRadius,
                                    renderedSpan: renderedSpan
                                )
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onHover { isHovering = $0 }
        .onChange(of: tile.widgets.count) { _, count in
            selection = min(selection, max(0, count - 1))
        }
        .onAppear(perform: installScrollMonitor)
        .onDisappear(perform: removeScrollMonitor)
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.black.opacity(0.12))
            .overlay {
                VStack(spacing: 4) {
                    Label("Smart Stack", systemImage: "square.stack.3d.up")
                        .font(.caption.weight(.semibold))
                    Text("No widgets available")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
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
