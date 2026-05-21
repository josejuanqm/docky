//
//  ProfileSwitcherButtonView.swift
//  Docky
//
//  Prototype: a small circular affordance at the leading edge of the dock
//  that fades in on hover and opens a menu of dock profiles. No persistent
//  state yet — the profile system itself isn't wired up. This file exists
//  to explore the interaction before committing to a storage model.
//

import AppKit
import SwiftUI

struct ProfileSwitcherButtonView: View {
    let dockPosition: ResolvedDockWindowPosition
    /// Length of the scroll viewport along the dock axis. Driven by the
    /// dock window's frame so the strip can extend the full dock width
    /// (or height, for vertical docks) without clipping any names.
    let availableLength: CGFloat
    /// Called whenever the switcher's visibility state changes. The
    /// window controller uses this to mark a main-dock interaction so
    /// the dock doesn't autohide while the user is hovering the ball.
    var onActiveChange: (Bool) -> Void = { _ in }

    @Bindable private var preferences = DockyPreferences.shared
    @Bindable private var profileService = ProfileService.shared
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var layoutService = DockLayoutService.shared
    @State private var isHoveringZone = false
    @State private var isHoveringButton = false
    /// Held true for 1s after the user picks a profile so the ball stays
    /// visible long enough to confirm the change before fading out.
    @State private var heldAfterSelection = false
    @State private var hideAfterSelectionTask: Task<Void, Never>?
    /// Mirrors the scroll picker's centered profile id. Drives — and is
    /// driven by — `ProfileService.activeProfileID`.
    @State private var scrolledProfileID: String?

    private var activeProfileSymbol: String {
        profileService.activeProfile?.symbolName ?? "circle.grid.3x3.fill"
    }

    /// Horizontal docks (top/bottom) scroll horizontally and show names;
    /// vertical docks (left/right) scroll vertically and show icons.
    private var isHorizontalScroll: Bool { !dockPosition.isVertical }

    /// Cross-axis ball thickness — circle diameter on vertical docks,
    /// pill height on horizontal docks. Always 50% of the tile size.
    private var ballSize: CGFloat { dockSettings.displayTileSize * 0.5 }

    /// Cross-axis hover extent. 44pt by default, shrinking with the dock
    /// when tiles are smaller. Always larger-or-equal to `ballSize`.
    private var hoverZoneSize: CGFloat { min(dockSettings.displayTileSize, 44) }

    /// Font used for profile names on horizontal docks. Matched to
    /// SwiftUI's `.headline` (semibold by default) so the measured
    /// widths line up with the rendered text widths.
    private var nameFont: NSFont {
        .preferredFont(forTextStyle: .headline)
    }

    private func nameWidth(_ name: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: nameFont]
        return (name as NSString).size(withAttributes: attrs).width
    }

    /// Width of the widest profile name. Sizes the scroll viewport so
    /// any item can travel to the centered position.
    private var maxNameWidth: CGFloat {
        profileService.profiles.map { nameWidth($0.name) }.max() ?? ballSize
    }

    /// Width of the *currently active* profile's name. The capsule
    /// resizes to this as the user scrolls so the glass always hugs
    /// the centered label.
    private var activeNameWidth: CGFloat {
        guard let profile = profileService.activeProfile else { return ballSize }
        return nameWidth(profile.name)
    }

    /// Per-side scroll-strip padding. Each side uses the first/last
    /// item's own width so that item can scroll to center, regardless
    /// of whether it's the widest.
    private var leadingStripPadding: CGFloat {
        guard let first = profileService.profiles.first else { return 0 }
        return max((viewportLength - nameWidth(first.name)) / 2, 0)
    }

    private var trailingStripPadding: CGFloat {
        guard let last = profileService.profiles.last else { return 0 }
        return max((viewportLength - nameWidth(last.name)) / 2, 0)
    }

    /// Capsule glass length along the dock axis. Adapts to the active
    /// profile's name on horizontal docks; degenerates to a circle of
    /// `ballSize` on vertical docks.
    private var pillLength: CGFloat {
        isHorizontalScroll ? max(activeNameWidth + 18, ballSize) : ballSize
    }

    /// Scroll viewport length. Matches the dock window's along-axis
    /// extent so every profile name has room to breathe with no
    /// clipping at the dock edges. Falls back to a sensible minimum
    /// when the dock frame hasn't been measured yet.
    private var viewportLength: CGFloat {
        let fallback = isHorizontalScroll
            ? max(maxNameWidth + 156, ballSize * 5)
            : ballSize * 3
        return max(availableLength, fallback)
    }

    /// Outer hover-catcher frame. Spans the full viewport along the
    /// scroll axis and `hoverZoneSize` on the cross axis.
    private var componentWidth: CGFloat {
        isHorizontalScroll ? viewportLength : hoverZoneSize
    }

    private var componentHeight: CGFloat {
        isHorizontalScroll ? hoverZoneSize : viewportLength
    }

    /// Visible glass capsule dimensions — pill on horizontal, circle on
    /// vertical. Always `ballSize` on the cross axis.
    private var ballWidth: CGFloat {
        isHorizontalScroll ? pillLength : ballSize
    }

    private var ballHeight: CGFloat {
        isHorizontalScroll ? ballSize : pillLength
    }

    /// Scroll viewport dimensions — wider than the capsule so overflow
    /// (adjacent labels) is visible. Cross axis matches the capsule.
    private var scrollViewportWidth: CGFloat {
        isHorizontalScroll ? viewportLength : ballSize
    }

    private var scrollViewportHeight: CGFloat {
        isHorizontalScroll ? ballSize : viewportLength
    }
    
    private var maximumCornerRadius: CGFloat {
        let iconHeight = layoutService.scaled(dockSettings.displayTileSize)
        return (iconHeight + layoutService.scaled(preferences.effectiveTileVerticalPadding) * 2) / 2
    }
    
    /// Per-corner radii used by every chrome shape (fill, glass clip,
    /// border). Each corner is the theme/user override clamped to the
    /// max curve, falling through to the uniform value when unset.
    private var chromeCornerRadii: RectangleCornerRadii {
        let cap = maximumCornerRadius
        return RectangleCornerRadii(
            topLeading: min(preferences.effectiveWindowCornerRadiusTopLeading, cap),
            bottomLeading: min(preferences.effectiveWindowCornerRadiusBottomLeading, cap),
            bottomTrailing: min(preferences.effectiveWindowCornerRadiusBottomTrailing, cap),
            topTrailing: min(preferences.effectiveWindowCornerRadiusTopTrailing, cap)
        )
    }

    var body: some View {
        ZStack {
            // Always-on hover target. Renders behind the other layers and
            // doesn't visually contribute — its only job is to catch
            // hovers in the cross-axis rim that the scroll picker
            // doesn't cover.
            Color.black.opacity(0.001)
                .frame(width: componentWidth, height: componentHeight)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringZone = hovering
                }
                .zIndex(-1)

            // Layer 0 — tint capsule, painted under the selector.
            Color(nsColor: preferences.effectiveWindowTintColor)
                .frame(width: ballWidth, height: ballHeight)
                .clipShape(Capsule())
                .opacity(isVisible ? preferences.effectiveWindowTintOpacity : 0)
                .allowsHitTesting(false)
                .zIndex(0)

            // Layer 1 — scroll picker text/icons; the only hit-testable
            // visual so scrolls and taps land here.
            profileScroller
                .opacity(isVisible ? 1 : 0)
                .onHover { hovering in
                    isHoveringButton = hovering
                }
                .contextMenu {
                    Button("Manage Profiles…") {
                        SettingsNavigator.shared.requestPane(id: "profiles")
                    }
                }
                .zIndex(1)

            // Layer 2 — glass capsule + border on top, non-interactive
            // so scroll/tap pass through to the picker beneath.
            ball
                .allowsHitTesting(false)
                .opacity(isVisible ? 1 : 0)
                .zIndex(2)
        }
        .frame(width: componentWidth, height: componentHeight)
        .animation(.easeOut(duration: 0.18), value: isVisible)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: profileService.activeProfileID)
        .onChange(of: isVisible) { _, newValue in
            onActiveChange(newValue)
        }
        .padding(1)
    }

    private var isVisible: Bool {
        isHoveringZone || isHoveringButton || heldAfterSelection
    }

    /// Pin the ball visible for 1s after a profile pick, then release.
    /// Cancels any previously-scheduled release so back-to-back picks
    /// each get the full second.
    private func scheduleHideAfterSelection() {
        hideAfterSelectionTask?.cancel()
        heldAfterSelection = true
        hideAfterSelectionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            heldAfterSelection = false
        }
    }

    /// Scroll picker behind the glass capsule. Horizontal docks (top/
    /// bottom) scroll horizontally and show profile names; vertical
    /// docks (left/right) scroll vertically and show profile symbols.
    /// The viewport is wider/taller than the capsule so adjacent items
    /// overflow on either side of the selector — they "land below" the
    /// capsule in z-order. Mirrors the segmented-glass selector idea
    /// from the iPhone Camera app.
    @ViewBuilder
    private var profileScroller: some View {
        if isHorizontalScroll {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(profileService.profiles) { profile in
                        Text(profile.name)
                            .font(.headline)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(.white)
                            .blendMode(.difference)
                            .opacity(profile.id == profileService.activeProfileID ? 1 : 0.5)
                            .frame(height: ballSize)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                profileService.setActiveProfile(id: profile.id)
                                scheduleHideAfterSelection()
                            }
                            .id(profile.id)
                    }
                }
                .padding(.leading, leadingStripPadding)
                .padding(.trailing, trailingStripPadding)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $scrolledProfileID, anchor: .center)
            .frame(width: scrollViewportWidth, height: scrollViewportHeight)
            .modifier(ScrollSyncModifier(
                scrolledID: $scrolledProfileID,
                profileService: profileService,
                onLand: scheduleHideAfterSelection
            ))
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(profileService.profiles) { profile in
                        Image(systemName: profile.symbolName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .blendMode(.difference)
                            .opacity(profile.id == profileService.activeProfileID ? 1 : 0.5)
                            .frame(width: ballSize, height: ballSize)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                profileService.setActiveProfile(id: profile.id)
                                scheduleHideAfterSelection()
                            }
                            .id(profile.id)
                    }
                }
                .padding(.vertical, (viewportLength - ballSize) / 2)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $scrolledProfileID, anchor: .center)
            .frame(width: scrollViewportWidth, height: scrollViewportHeight)
            .modifier(ScrollSyncModifier(
                scrolledID: $scrolledProfileID,
                profileService: profileService,
                onLand: scheduleHideAfterSelection
            ))
        }
    }

    private var ball: some View {
        // NSGlassEffectView variant 19 — the lens-flavored member of the
        // same private glass family the chrome uses (variant 11). The
        // uniform corner radius of `ballSize / 2` makes a circle when
        // width == height and a capsule when wider.
        Color.clear
            .frame(width: ballWidth, height: ballHeight)
            .background {
                if !preferences.effectiveDisablesGlassLook,
                   FeatureGate.shared.isAvailable(.liquidGlass),
                   #available(macOS 26.0, *) {
                    LiquidGlassChromeView(
                        variant: 19,
                        cornerRadius: ballSize / 2
                    )
                }
            }
            .dockyGlassBorder(in: Capsule(), lineWidth: 1)
    }
}

/// Bridges the scroll picker's centered profile id with
/// `ProfileService.activeProfileID`. Extracted so the two scroll-axis
/// branches in `profileScroller` don't have to repeat the wiring.
private struct ScrollSyncModifier: ViewModifier {
    @Binding var scrolledID: String?
    let profileService: ProfileService
    let onLand: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                scrolledID = profileService.activeProfileID
            }
            .onChange(of: scrolledID) { _, newID in
                guard let newID, newID != profileService.activeProfileID else { return }
                profileService.setActiveProfile(id: newID)
                onLand()
            }
            .onChange(of: profileService.activeProfileID) { _, newID in
                if scrolledID != newID {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        scrolledID = newID
                    }
                }
            }
    }
}
