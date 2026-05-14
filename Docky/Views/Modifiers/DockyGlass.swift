//
//  DockyGlass.swift
//  Docky
//
//  Drop-in replacement for `.glassEffect(...)` that gates Liquid Glass on
//  macOS 26+ and falls back to the same SkyLight private-API backdrop blur
//  the dock chrome uses on macOS 13.5–25. Apply `.dockyGlass(in: shape)`
//  on every surface that should follow the platform behavior.
//
//  Fallback rendering: a clipped translucent fill on top of the host
//  NSWindow's `CGSSetWindowBackgroundBlurRadius` blur. The blur itself is
//  installed at the window level — the same mechanism `MainWindow` and
//  the Launchpad overlay use — so multiple glass surfaces in the same
//  window share one blurred backdrop instead of fighting for it.
//

import AppKit
import SwiftUI

enum DockyGlassStyle {
    case regular
    case clear
}

extension View {
    @ViewBuilder
    func dockyGlass<S: Shape>(_ style: DockyGlassStyle = .regular, in shape: S) -> some View {
        modifier(DockyGlassModifier(style: style, shape: AnyShape(shape)))
    }

    @ViewBuilder
    func dockyGlass(_ style: DockyGlassStyle = .regular) -> some View {
        modifier(DockyGlassModifier(style: style, shape: AnyShape(Capsule())))
    }

    /// Adds the dock chrome's gradient stroke "glass" outline on top of
    /// `self`, gated by the `disablesGlassLook` preference. When the user
    /// turns glass off the modifier becomes a no-op so the surface falls
    /// back to whatever else is already drawing borders.
    @ViewBuilder
    func dockyGlassBorder<S: InsettableShape>(in shape: S, lineWidth: CGFloat = 1) -> some View {
        modifier(DockyGlassBorderModifier(shape: shape, lineWidth: lineWidth))
    }
}

/// Shared with `MainWindowView.chromeBackground` so tile glass borders
/// stay in lockstep with the dock chrome's gradient stroke.
let dockyGlassBorderGradient = LinearGradient(
    colors: [
        Color.white.opacity(0.35),
        Color.white.opacity(0.12),
        Color.white.opacity(0.05),
        Color.white.opacity(0.12),
        Color.white.opacity(0.28),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private struct DockyGlassBorderModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let lineWidth: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        // Read `disablesGlassLook` directly instead of subscribing via
        // `@ObservedObject DockyPreferences.shared`. The shared
        // preferences object publishes dozens of unrelated properties
        // (drag state, hover, etc.); subscribing here would invalidate
        // every tile that uses this modifier on every preference write.
        // Tile parents already observe `DockyPreferences` where they
        // need to, so flips to `disablesGlassLook` still propagate via
        // their existing dependency graph and re-evaluate this body.
        content.overlay {
            if !DockyPreferences.shared.effectiveDisablesGlassLook {
                shape.strokeBorder(dockyGlassBorderGradient, lineWidth: lineWidth)
            }
        }
    }
}

private struct DockyGlassModifier: ViewModifier {
    let style: DockyGlassStyle
    let shape: AnyShape

    @ViewBuilder
    func body(content: Content) -> some View {
        if FeatureGate.shared.isAvailable(.liquidGlass), #available(macOS 26.0, *) {
            content.glassEffect(style.glass, in: shape)
        } else {
            content.background(SkyLightGlassFallback(style: style, shape: shape))
        }
    }
}

@available(macOS 26.0, *)
private extension DockyGlassStyle {
    var glass: Glass {
        switch self {
        case .regular: return .regular
        case .clear: return .clear
        }
    }
}

/// Visible glass surrogate for macOS 13.5–25. The translucent fill is the
/// only thing the modifier draws itself; the blur comes from a SkyLight
/// backdrop installed on the host NSWindow. If the host window is opaque
/// the blur won't be visible — same caveat that applies to the existing
/// dock chrome.
private struct SkyLightGlassFallback: View {
    let style: DockyGlassStyle
    let shape: AnyShape

    var body: some View {
        ZStack {
            SkyLightHostBlurInstaller()
            shape.fill(.primary.opacity(tintOpacity))
        }
    }

    /// `.regular` matches the 0.18 tint already used elsewhere in Docky
    /// chrome (e.g. the window switcher card background); `.clear` keeps
    /// the surface barely visible so it reads like the macOS 26 clear
    /// glass treatment.
    private var tintOpacity: Double {
        switch style {
        case .regular: return 0.18
        case .clear: return 0.04
        }
    }
}

/// Empty NSView whose only job is to walk up to the host NSWindow and turn
/// on the SkyLight backdrop blur. Idempotent: safe to attach in many views,
/// the underlying CGS call just resets the radius. Windows that already
/// install their own blur (main window, Launchpad overlay) re-apply their
/// preferred radius on each `order(...)`, so this never wins long-term in
/// those windows — it only matters for windows that don't otherwise ask
/// for any window-level blur.
private struct SkyLightHostBlurInstaller: NSViewRepresentable {
    var blurRadius: Int = 30

    func makeNSView(context: Context) -> InstallerView {
        InstallerView(blurRadius: blurRadius)
    }

    func updateNSView(_ view: InstallerView, context: Context) {
        view.blurRadius = blurRadius
        view.applyToHostWindow()
    }

    final class InstallerView: NSView {
        var blurRadius: Int

        init(blurRadius: Int) {
            self.blurRadius = blurRadius
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not available") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyToHostWindow()
        }

        func applyToHostWindow() {
            guard let window, window.windowNumber > 0 else { return }
            #if !APP_STORE_SANDBOX
            _ = CGSSetWindowBackgroundBlurRadius(
                CGSMainConnectionID(),
                window.windowNumber,
                blurRadius
            )
            #endif
            // MAS path: no-op. The chrome falls back to whatever
            // SwiftUI material the view declared above; the SkyLight
            // amplification is what's missing. Helper-routed blur is
            // a future addition.
        }
    }
}
