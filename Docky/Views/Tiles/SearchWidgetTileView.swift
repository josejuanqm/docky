//
//  SearchWidgetTileView.swift
//  Docky
//
//  1x: static magnifying-glass affordance. Tap (handled in
//  `TileView.handleWidgetTap`) opens `https://www.google.com`.
//
//  2x / 3x: a real, inline `TextField`, type, hit Enter, the typed
//  query is URL-encoded and `https://www.google.com/search?q=...` opens
//  in the default browser. To make this work the dock window has to
//  accept key status while the field is focused; we toggle
//  `MainWindow.allowsKeyWindow` on focus changes and ask the host
//  window to (un)make-key in lockstep so SwiftUI can route keystrokes
//  into the field without ever bringing Docky to the foreground (the
//  `.nonactivatingPanel` style mask keeps app activation suppressed).
//

import AppKit
import SwiftUI

struct SearchWidgetTileView: View {
    @Environment(\.widgetTextScale) private var textScale

    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool
    var isExpanded: Bool = false
    var isExpandedPreviewOpen: Bool = false

    @State private var query: String = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        GeometryReader { proxy in
            let metrics = layout(in: proxy.size)
            ZStack {
                Rectangle()
                    .fill(.primary)
                content(metrics: metrics)
            }
            .colorScheme(.dark)
            .padding(.horizontal, renderedSpan != .one ? 12 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onChange(of: isFieldFocused) { focused in
            // Flip the panel's key-window eligibility in lockstep with
            // focus so keystrokes reach the field, then ask AppKit to
            // (un)make-key now (`canBecomeKey` alone doesn't change the
            // current key window, it just gates future requests).
            MainWindow.allowsKeyWindow = focused
            DispatchQueue.main.async {
                guard let window = NSApp.windows.first(where: { $0 is MainWindow }) else { return }
                if focused {
                    window.makeKey()
                } else {
                    window.resignKey()
                }
            }
        }
    }

    @ViewBuilder
    private func content(metrics: LayoutMetrics) -> some View {
        switch renderedSpan {
        case .one:
            Image(systemName: "magnifyingglass")
                .font(.system(size: metrics.iconSize, weight: .semibold))
                .foregroundStyle(.background)
        case .two, .three, .four:
            HStack(spacing: metrics.iconTextSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .opacity(0.9)
                // ZStack so we can paint a black placeholder explicitly ,
                // SwiftUI's TextField placeholder inherits secondary
                // styling from the system, not the surrounding
                // `.foregroundStyle(.black)`, so without the manual
                // overlay it renders washed-out gray. The placeholder
                // hides once typing starts.
                ZStack(alignment: .leading) {
                    if query.isEmpty {
                        Text("Search Google")
                            .font(.system(size: NSFont.systemFontSize * textScale))
                            .foregroundStyle(Color.black)
                    }
                    TextField("", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: NSFont.systemFontSize * textScale))
                        .focused($isFieldFocused)
                        .onSubmit(performSearch)
                        .background(.clear)
                }
            }
            .padding(.horizontal, metrics.horizontalInset)
            .padding(.vertical, 4)
            .background(.clear)
            .foregroundStyle(.background)
            .preferredColorScheme(.dark)
        }
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Empty submit: just open google.com so Enter on an empty
            // field isn't a dead key.
            if let url = URL(string: "https://www.google.com") {
                NSWorkspace.shared.open(url)
            }
            isFieldFocused = false
            return
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
        query = ""
        isFieldFocused = false
    }

    private func layout(in size: CGSize) -> LayoutMetrics {
        let shortSide = min(size.width, size.height)
        return LayoutMetrics(
            iconSize: max(10, shortSide * 0.42),
            labelSize: max(10, shortSide * 0.34),
            iconTextSpacing: max(4, shortSide * 0.12),
            horizontalInset: max(8, shortSide * 0.18)
        )
    }

    private struct LayoutMetrics {
        let iconSize: CGFloat
        let labelSize: CGFloat
        let iconTextSpacing: CGFloat
        let horizontalInset: CGFloat
    }
}
