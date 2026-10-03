//
//  AppearanceSettingsView.swift
//  Docky
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    enum Subsection {
        case general
        case indicators
        case tileLayout
        case windowShape
        case windowBackground
        case widgets
    }

    let subsection: Subsection

    private let dockSettings = DockSettingsService.shared
    @Bindable private var preferences = DockyPreferences.shared
    @State private var isShowingResetConfirmation = false

    var body: some View {
        Form {
            switch subsection {
            case .general:
                generalSection
            case .indicators:
                indicatorsSection
            case .tileLayout:
                tileLayoutSection
            case .windowShape:
                windowShapeSection
            case .windowBackground:
                windowBackgroundSection
            case .widgets:
                widgetsSection
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset appearance settings?",
            isPresented: $isShowingResetConfirmation
        ) {
            Button("Reset Appearance", role: .destructive) {
                DockyPreferences.shared.resetAppearanceToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Indicators, tile layout, window shape, window background, and the glass toggle will return to their defaults. App icons, behavior, widgets, and other settings are unaffected. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var generalSection: some View {
        Section("Glass") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Disable Glass Look", isOn: $preferences.disablesGlassLook)
                    .font(.headline)

                Text("Removes the main window's glossy gradient border and Liquid Glass material while keeping the existing blur and background tinting.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }

        Section("Reset Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Restores the appearance preferences (indicators, tile layout, window shape, window background, glass) to their defaults. App icons, behavior, widgets, launchpad, and window-management settings keep their current values.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Reset Appearance", role: .destructive) {
                    isShowingResetConfirmation = true
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var indicatorsSection: some View {
        Section("Activity Indicator") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Active Indicator Shape")
                        .font(.headline)

                    Spacer()

                    Picker("Active Indicator Shape", selection: $preferences.activeIndicatorShape) {
                        ForEach(DockTileIndicatorShape.allCases) { shape in
                            Text(L10n.text(shape.title)).tag(shape)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                if preferences.activeIndicatorShape == .image {
                    HStack {
                        Button("Choose Image...") {
                            chooseActiveIndicatorImage()
                        }

                        if preferences.activeIndicatorImagePath != nil {
                            Button("Clear") {
                                preferences.activeIndicatorImagePath = nil
                            }
                        }
                    }

                    if let selectedActiveIndicatorImageName {
                        Text(selectedActiveIndicatorImageName)
                            .foregroundStyle(.secondary)
                    }
                }

                if showsIndicatorColorControls {
                    Divider()

                    Toggle("Use Custom Indicator Color", isOn: usesCustomActiveIndicatorColorBinding)
                        .font(.headline)

                    if preferences.activeIndicatorColor != nil {
                        ColorPicker("Indicator Color", selection: activeIndicatorColorBinding, supportsOpacity: false)
                    }
                }

                Text("Choose whether running apps use no marker, the classic dot, a pill, or a custom image.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            sliderRow(
                title: "Inward Offset",
                value: $preferences.activeIndicatorOffset,
                range: -20...20,
                step: 1,
                format: { "\(Int($0)) pt" },
                description: "Shifts the indicator further from or closer to the screen edge."
            )

            sliderRow(
                title: "Size",
                value: $preferences.activeIndicatorScale,
                range: 0.5...2.0,
                step: 0.05,
                format: { String(format: "%.2fx", $0) },
                description: "Scales the indicator's rendered size."
            )
        }

        Section("Dividers") {
            customDividerImageControls
        }
    }

    @ViewBuilder
    private var customDividerImageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Divider Image")
                .font(.headline)

            dividerImageRow(
                title: "Center",
                path: preferences.dividerImagePath,
                onChoose: { chooseDividerImage(slot: .global) },
                onClear: { preferences.dividerImagePath = nil }
            )

            Divider()

            dividerImageRow(
                title: "Left Side",
                path: preferences.leftDividerImagePath,
                onChoose: { chooseDividerImage(slot: .left) },
                onClear: { preferences.leftDividerImagePath = nil }
            )

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Right Side")
                    Spacer()
                    Toggle("Mirror Left Side", isOn: $preferences.mirrorsLeftDividerOnRight)
                        .toggleStyle(.switch)
                }

                if !preferences.mirrorsLeftDividerOnRight {
                    dividerImageRow(
                        title: nil,
                        path: preferences.rightDividerImagePath,
                        onChoose: { chooseDividerImage(slot: .right) },
                        onClear: { preferences.rightDividerImagePath = nil }
                    )
                }
            }

            Text("Use a custom image for dividers. The center image applies to dividers near the middle of the dock; the left and right overrides target dividers near each end. Mirror reuses the left image flipped on the right side. In vertical docks the image is rotated 90° to follow the dock's axis.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)

        sliderRow(
            title: "Padding",
            value: $preferences.dividerPaddingFraction,
            range: 0...0.5,
            step: 0.01,
            format: { "\(Int(($0 * 100).rounded()))%" },
            description: "Controls how much each divider is inset along its short axis, as a fraction of the tile size."
        )

        sliderRow(
            title: "Vertical Offset",
            value: $preferences.dividerOffset,
            range: -20...20,
            step: 1,
            format: { "\(Int($0)) pt" },
            description: "Shifts dividers along the tile's short axis. Positive values move them up in horizontal docks or right in vertical docks."
        )

        sliderRow(
            title: "Image Size",
            value: $preferences.dividerImageScale,
            range: 0.5...2.0,
            step: 0.05,
            format: { String(format: "%.2fx", $0) },
            description: "Scales custom divider images. Has no effect on the default line."
        )

        sliderRow(
            title: "Opacity",
            value: $preferences.dividerOpacity,
            range: 0...1,
            step: 0.05,
            format: { "\(Int(($0 * 100).rounded()))%" },
            description: "Controls how visible dividers are. 100% is fully opaque; 0% hides them entirely."
        )

        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use Custom Divider Color", isOn: usesCustomDividerColorBinding)
                .font(.headline)

            if preferences.effectiveDividerColor != nil {
                ColorPicker("Divider Color", selection: dividerColorBinding, supportsOpacity: false)
            }

            Text("Replaces the default text-tracking color of the plain divider line. Has no effect on dividers that use a custom image.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var alphaBadge: some View {
        Text("ALPHA")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(.orange.opacity(0.4), lineWidth: 0.5))
            .accessibilityLabel(L10n.text("Alpha feature"))
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        format: @escaping (CGFloat) -> String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title))
                .font(.headline)

            HStack {
                Slider(value: value, in: range, step: step) {
                    Text(L10n.text(title))
                }
                .labelsHidden()

                Text(format(value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }

            Text(L10n.text(description))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dividerImageRow(title: String?, path: String?, onChoose: @escaping () -> Void, onClear: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(L10n.text(title))
            }

            HStack {
                Button("Choose Image...", action: onChoose)

                if path != nil {
                    Button("Clear", action: onClear)
                }

                if let name = path.flatMap({ $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent }) {
                    Text(name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder
    private var tileLayoutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tile Clip Shape")
                        .font(.headline)

                    Spacer()

                    Picker("Tile Clip Shape", selection: $preferences.tileClipShape) {
                        ForEach(DockClipShape.allCases) { shape in
                            Text(L10n.text(shape.title)).tag(shape)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Text("Choose whether Docky tile chrome keeps the current rounded corners or uses a full circle or capsule clip.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tile Vertical Padding")
                        .font(.headline)

                    Spacer()

                    HStack {
                        Slider(value: $preferences.tileVerticalPadding, in: 8...32, step: 1) {
                            Text("Tile Vertical Padding")
                        }
                        .labelsHidden()

                        Text("\(Int(preferences.tileVerticalPadding)) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Text("Controls the top and bottom inset inside each dock tile.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tile Spacing")
                        .font(.headline)

                    Spacer()

                    HStack {
                        Slider(value: $preferences.tileSpacing, in: 0...16, step: 1) {
                            Text("Tile Spacing")
                        }
                        .labelsHidden()
                        Text("\(Int(preferences.tileSpacing)) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Text("Controls the horizontal gap between adjacent dock tiles.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Tile Size")
                    .font(.headline)

                HStack {
                    Slider(value: systemDockTileSizeBinding, in: 16...128, step: 1) {
                        Text("Tile Size")
                    }
                    .labelsHidden()

                    Text("\(Int(dockSettings.tileSize.rounded())) pt")
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                Text("Controls the base width and height of each dock tile.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tile Icon Padding")
                        .font(.headline)

                    Spacer()

                    HStack {
                        Slider(value: $preferences.tileIconPadding, in: 0...24, step: 1) {
                            Text("Tile Icon Padding")
                        }
                        .labelsHidden()
                        Text("\(Int(preferences.effectiveTileIconPadding)) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Text("Shrinks the rendered icon inside each tile without changing the tile's layout box. Useful for Windows-style chunky tile slots.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Tile Hover Effect")
                    .font(.headline)

                Toggle("Use Hover Background", isOn: usesHoverBackgroundColorBinding)

                if preferences.tileHoverBackgroundColor != nil {
                    ColorPicker("Hover Background Color", selection: hoverBackgroundColorBinding, supportsOpacity: false)
                }

                HStack {
                    Text("Hover Background Image")
                    Spacer()
                    Button("Choose Image...") { chooseTileHoverBackgroundImage() }
                    if preferences.tileHoverBackgroundImagePath != nil {
                        Button("Clear") { preferences.tileHoverBackgroundImagePath = nil }
                    }
                }

                if let name = selectedHoverBackgroundImageName {
                    Text(name)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                HStack {
                    Text("Background Opacity")
                    Slider(value: hoverBackgroundOpacityBinding, in: 0...1, step: 0.05) {
                        Text("Hover Background Opacity")
                    }
                    .labelsHidden()
                    Text("\(Int((preferences.effectiveTileHoverBackgroundOpacity * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
                .disabled(!hasHoverBackgroundSource)

                HStack {
                    Text("Background Corner Radius")
                    Slider(value: hoverBackgroundCornerRadiusBinding, in: 0...32, step: 1) {
                        Text("Hover Background Corner Radius")
                    }
                    .labelsHidden()
                    Text("\(Int(preferences.effectiveTileHoverBackgroundCornerRadius)) pt")
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
                .disabled(!hasHoverBackgroundSource)

                HStack {
                    Text("Hover Scale")
                    Slider(value: hoverScaleBinding, in: 0.8...1.4, step: 0.01) {
                        Text("Hover Scale")
                    }
                    .labelsHidden()
                    Text(String(format: "%.2f×", preferences.effectiveTileHoverScale))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }

                HStack {
                    Text("Hover Opacity")
                    Slider(value: hoverOpacityBinding, in: 0...1, step: 0.05) {
                        Text("Hover Opacity")
                    }
                    .labelsHidden()
                    Text("\(Int((preferences.effectiveTileHoverOpacity * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }

                Text("Layered hover treatment: a background fill (color or image), plus optional scale and opacity multipliers applied to the icon while hovered.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Active App Background")
                    .font(.headline)

                Toggle("Use Active Background", isOn: usesActiveBackgroundColorBinding)

                if preferences.tileActiveBackgroundColor != nil {
                    ColorPicker("Active Background Color", selection: activeBackgroundColorBinding, supportsOpacity: false)
                }

                HStack {
                    Text("Active Background Image")
                    Spacer()
                    Button("Choose Image...") { chooseTileActiveBackgroundImage() }
                    if preferences.tileActiveBackgroundImagePath != nil {
                        Button("Clear") { preferences.tileActiveBackgroundImagePath = nil }
                    }
                }

                if let name = selectedActiveBackgroundImageName {
                    Text(name)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                HStack {
                    Text("Background Opacity")
                    Slider(value: activeBackgroundOpacityBinding, in: 0...1, step: 0.05) {
                        Text("Active Background Opacity")
                    }
                    .labelsHidden()
                    Text("\(Int((preferences.effectiveTileActiveBackgroundOpacity * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
                .disabled(!hasActiveBackgroundSource)

                HStack {
                    Text("Background Corner Radius")
                    Slider(value: activeBackgroundCornerRadiusBinding, in: 0...32, step: 1) {
                        Text("Active Background Corner Radius")
                    }
                    .labelsHidden()
                    Text("\(Int(preferences.effectiveTileActiveBackgroundCornerRadius)) pt")
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
                .disabled(!hasActiveBackgroundSource)

                Text("Background fill drawn under every running app tile, independent of hover. Useful for taskbar-style \"highlighted active app\" looks.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use Icon Shadow", isOn: usesIconShadowBinding)
                    .font(.headline)

                if preferences.effectiveIconShadowColor != nil {
                    ColorPicker("Shadow Color", selection: iconShadowColorBinding, supportsOpacity: false)

                    HStack {
                        Text("Radius")
                        Slider(value: $preferences.iconShadowRadius, in: 0...32, step: 0.5) {
                            Text("Shadow Radius")
                        }
                        .labelsHidden()
                        Text(String(format: "%.1f pt", preferences.effectiveIconShadowRadius))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }

                    HStack {
                        Text("Opacity")
                        Slider(value: $preferences.iconShadowOpacity, in: 0...1, step: 0.05) {
                            Text("Shadow Opacity")
                        }
                        .labelsHidden()
                        Text("\(Int((preferences.effectiveIconShadowOpacity * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }

                Text("Adds a drop shadow behind every icon-bearing tile. Has no visible effect on spacers and dividers.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: systemDockMagnificationBinding) {
                    HStack(spacing: 8) {
                        Text("Magnification")
                        alphaBadge
                    }
                }
                .font(.headline)

                if dockSettings.magnification {
                    HStack {
                        Slider(value: systemDockLargeSizeBinding, in: largeSizeRange, step: 1) {
                            Text("Magnified Size")
                        }
                        .labelsHidden()

                        Text("\(Int(dockSettings.largeSize.rounded())) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Text("Tiles near the pointer grow toward the magnified size and smoothly fall off with distance. Alpha: known issues with certain tile types and during reorder.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var windowShapeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Chrome Clip Shape")
                        .font(.headline)

                    Spacer()

                    Picker("Chrome Clip Shape", selection: $preferences.windowClipShape) {
                        ForEach(DockClipShape.allCases) { shape in
                            Text(L10n.text(shape.title)).tag(shape)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Text("Choose whether the dock chrome keeps the current rounded corners or uses a full circle or capsule clip.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Window Corner Radius")
                        .font(.headline)

                    Spacer()

                    HStack {
                        Slider(value: windowCornerRadiusBinding, in: 0...maximumCornerRadius, step: 1) {
                            Text("Window Corner Radius")
                        }
                        .labelsHidden()
                        Text("\(Int(min(preferences.windowCornerRadius, maximumCornerRadius))) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Text(windowCornerRadiusDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .disabled(preferences.windowClipShape == .circle)

            DisclosureGroup("Per-Corner Radii") {
                cornerRadiusRow(
                    label: "Top Leading",
                    binding: $preferences.windowCornerRadiusTopLeading,
                    effective: preferences.effectiveWindowCornerRadiusTopLeading
                )
                cornerRadiusRow(
                    label: "Top Trailing",
                    binding: $preferences.windowCornerRadiusTopTrailing,
                    effective: preferences.effectiveWindowCornerRadiusTopTrailing
                )
                cornerRadiusRow(
                    label: "Bottom Leading",
                    binding: $preferences.windowCornerRadiusBottomLeading,
                    effective: preferences.effectiveWindowCornerRadiusBottomLeading
                )
                cornerRadiusRow(
                    label: "Bottom Trailing",
                    binding: $preferences.windowCornerRadiusBottomTrailing,
                    effective: preferences.effectiveWindowCornerRadiusBottomTrailing
                )

                Text("Each corner that's set overrides only itself; unset corners inherit the uniform radius above. Use this to flatten only the screen-facing edge (taskbar look).")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(preferences.windowClipShape == .circle)
            .padding(.vertical, 4)

            DisclosureGroup("Per-Edge Content Insets") {
                contentInsetRow(label: "Top", value: $preferences.windowContentInsetTop)
                contentInsetRow(label: "Leading", value: $preferences.windowContentInsetLeading)
                contentInsetRow(label: "Bottom", value: $preferences.windowContentInsetBottom)
                contentInsetRow(label: "Trailing", value: $preferences.windowContentInsetTrailing)

                Text("Padding between the dock panel and the chrome view, per edge. Full-axis mode forces these to 0 regardless.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use Custom Border", isOn: usesCustomWindowBorderBinding)
                    .font(.headline)

                if preferences.effectiveWindowBorderColor != nil {
                    ColorPicker("Border Color", selection: windowBorderColorBinding, supportsOpacity: false)

                    HStack {
                        Text("Border Width")
                        Slider(value: $preferences.windowBorderWidth, in: 0...8, step: 0.5) {
                            Text("Border Width")
                        }
                        .labelsHidden()
                        Text(String(format: "%.1f pt", preferences.effectiveWindowBorderWidth))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }

                Text("Override the chrome outline with a solid color. When off, Docky uses its default glass stroke (or no stroke when Glass is disabled).")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var widgetsSection: some View {
        Section {
            widgetSpanBlock(
                title: "1x Widgets",
                paddingBinding: $preferences.widget1xContentPadding,
                radiusBinding: $preferences.widget1xCornerRadius,
                effectivePadding: preferences.effectiveWidgetContentPadding(for: .one),
                effectiveRadius: preferences.effectiveWidgetCornerRadius(for: .one)
            )
            widgetSpanBlock(
                title: "2x Widgets",
                paddingBinding: $preferences.widget2xContentPadding,
                radiusBinding: $preferences.widget2xCornerRadius,
                effectivePadding: preferences.effectiveWidgetContentPadding(for: .two),
                effectiveRadius: preferences.effectiveWidgetCornerRadius(for: .two)
            )
            widgetSpanBlock(
                title: "3x Widgets",
                paddingBinding: $preferences.widget3xContentPadding,
                radiusBinding: $preferences.widget3xCornerRadius,
                effectivePadding: preferences.effectiveWidgetContentPadding(for: .three),
                effectiveRadius: preferences.effectiveWidgetCornerRadius(for: .three)
            )

            Text("Each rendering size can opt into its own content padding and corner radius. Unset values inherit the tile-chrome defaults, useful for letting wide widgets bleed edge-to-edge while keeping the 1x form rounded.")
                .foregroundStyle(.secondary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func widgetSpanBlock(
        title: String,
        paddingBinding: Binding<CGFloat?>,
        radiusBinding: Binding<CGFloat?>,
        effectivePadding: CGFloat?,
        effectiveRadius: CGFloat?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title)).font(.headline)

            widgetOverrideRow(
                label: "Content Padding",
                binding: paddingBinding,
                effective: effectivePadding,
                range: 0...32
            )
            widgetOverrideRow(
                label: "Corner Radius",
                binding: radiusBinding,
                effective: effectiveRadius,
                range: 0...32
            )
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func widgetOverrideRow(
        label: String,
        binding: Binding<CGFloat?>,
        effective: CGFloat?,
        range: ClosedRange<Double>
    ) -> some View {
        // Three-state row: the toggle is the user's intent (override
        // this span's value or inherit). The slider becomes editable
        // only when the override is on. Unset state shows "inherited"
        // rather than a meaningless number.
        let isOverriding = Binding<Bool>(
            get: { binding.wrappedValue != nil },
            set: { uses in
                if uses {
                    binding.wrappedValue = effective ?? 0
                } else {
                    binding.wrappedValue = nil
                }
            }
        )
        let sliderValue = Binding<Double>(
            get: { Double(binding.wrappedValue ?? effective ?? 0) },
            set: { binding.wrappedValue = CGFloat($0) }
        )
        HStack {
            Toggle(isOn: isOverriding) {
                Text(L10n.text(label)).frame(width: 140, alignment: .leading)
            }
            .toggleStyle(.checkbox)
            Slider(value: sliderValue, in: range, step: 1) {
                Text(L10n.text(label))
            }
            .labelsHidden()
            .disabled(!isOverriding.wrappedValue)
            Text(isOverriding.wrappedValue
                 ? "\(Int(sliderValue.wrappedValue)) pt"
                 : (effective.map { "\(Int($0)) pt" } ?? "inherited"))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }

    private var windowBackgroundSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Window Background Image")
                    .font(.headline)

                HStack {
                    Button("Choose Image...") {
                        chooseWindowBackgroundImage()
                    }

                    if preferences.windowBackgroundImagePath != nil {
                        Button("Clear") {
                            preferences.windowBackgroundImagePath = nil
                        }
                    }
                }

                if let selectedWindowBackgroundImageName {
                    Text(selectedWindowBackgroundImageName)
                        .foregroundStyle(.secondary)
                }

                Text("Use an image with aspect fill behind the dock tiles. When set, it replaces the material tint and opacity until cleared.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("Background Image Mode")

                    Spacer()

                    Picker("Background Image Mode", selection: $preferences.windowBackgroundImageMode) {
                        ForEach(DockBackgroundImageMode.allCases) { mode in
                            Text(L10n.text(mode.title)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(preferences.windowBackgroundImagePath == nil)
                }

                Text("Sprite mode keeps the leading and trailing thirds of the image pinned and stretches the middle along the dock's axis.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use Custom Window Tint", isOn: usesCustomWindowTintBinding)
                    .font(.headline)

                if preferences.windowTintColor != nil {
                    ColorPicker("Window Tint", selection: windowTintBinding, supportsOpacity: false)
                }

                Text("Override the translucent tint behind the main dock window. Leave this off to keep following the system material color.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .disabled(usesWindowBackgroundImage)

            VStack(alignment: .leading, spacing: 8) {
                Text("Window Tint Opacity")
                    .font(.headline)

                HStack {
                    Slider(value: windowTintOpacityBinding, in: 0...1, step: 0.01) {
                        Text("Window Tint Opacity")
                    }
                    Text("\(Int(preferences.effectiveWindowTintOpacity * 100))%")
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                Text("Controls how strongly the tint color is laid over the window blur.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .disabled(usesWindowBackgroundImage)
        }
    }

    private var maximumCornerRadius: CGFloat {
        (dockSettings.displayTileSize + preferences.tileVerticalPadding * 2) / 2
    }

    private var systemDockTileSizeBinding: Binding<Double> {
        Binding(
            get: { Double(dockSettings.tileSize) },
            set: { dockSettings.setTileSize(CGFloat($0)) }
        )
    }

    private var systemDockMagnificationBinding: Binding<Bool> {
        Binding(
            get: { dockSettings.magnification },
            set: { dockSettings.setMagnification($0) }
        )
    }

    private var systemDockLargeSizeBinding: Binding<Double> {
        Binding(
            get: { Double(dockSettings.largeSize) },
            set: { dockSettings.setLargeSize(CGFloat($0)) }
        )
    }

    private var largeSizeRange: ClosedRange<Double> {
        let lower = Double(dockSettings.tileSize)
        return lower...max(lower, 256)
    }

    private var windowCornerRadiusBinding: Binding<CGFloat> {
        Binding(
            get: { min(preferences.windowCornerRadius, maximumCornerRadius) },
            set: { preferences.windowCornerRadius = $0 }
        )
    }

    private var windowCornerRadiusDescription: String {
        switch preferences.windowClipShape {
        case .rounded:
            "Controls the roundness of the main dock window and its border, up to a full capsule."
        case .circle:
            "Circle mode uses the maximum radius automatically, so square chrome becomes circular and wider chrome becomes a capsule."
        }
    }

    private var usesCustomWindowTintBinding: Binding<Bool> {
        Binding(
            get: { preferences.windowTintColor != nil },
            set: { usesCustomTint in
                preferences.windowTintColor = usesCustomTint
                    ? (preferences.windowTintColor ?? DockColor(nsColor: preferences.effectiveWindowTintColor))
                    : nil
            }
        )
    }

    private var windowTintBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: preferences.effectiveWindowTintColor) },
            set: { newValue in
                guard let tintColor = DockColor(nsColor: NSColor(newValue)) else {
                    return
                }

                preferences.windowTintColor = tintColor
            }
        )
    }

    private var showsIndicatorColorControls: Bool {
        switch preferences.activeIndicatorShape {
        case .dot, .pill, .underline:
            true
        case .none, .image:
            false
        }
    }

    private var usesCustomActiveIndicatorColorBinding: Binding<Bool> {
        Binding(
            get: { preferences.activeIndicatorColor != nil },
            set: { usesCustomColor in
                preferences.activeIndicatorColor = usesCustomColor
                    ? (preferences.activeIndicatorColor ?? DockColor(nsColor: preferences.effectiveActiveIndicatorColor))
                    : nil
            }
        )
    }

    private var activeIndicatorColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: preferences.effectiveActiveIndicatorColor) },
            set: { newValue in
                guard let indicatorColor = DockColor(nsColor: NSColor(newValue)) else {
                    return
                }

                preferences.activeIndicatorColor = indicatorColor
            }
        )
    }

    private var windowTintOpacityBinding: Binding<CGFloat> {
        Binding(
            get: { preferences.effectiveWindowTintOpacity },
            set: { preferences.windowTintOpacity = min(max($0, 0), 1) }
        )
    }

    private var usesCustomWindowBorderBinding: Binding<Bool> {
        Binding(
            get: { preferences.effectiveWindowBorderColor != nil },
            set: { usesBorder in
                if usesBorder {
                    let seed = preferences.effectiveWindowBorderColor ?? .labelColor
                    preferences.windowBorderColor = DockColor(nsColor: seed)
                } else {
                    preferences.windowBorderColor = nil
                }
            }
        )
    }

    private var windowBorderColorBinding: Binding<Color> {
        Binding(
            get: {
                let nsColor = preferences.effectiveWindowBorderColor ?? .labelColor
                return Color(nsColor: nsColor)
            },
            set: { newValue in
                guard let color = DockColor(nsColor: NSColor(newValue)) else { return }
                preferences.windowBorderColor = color
            }
        )
    }

    private var usesIconShadowBinding: Binding<Bool> {
        Binding(
            get: { preferences.effectiveIconShadowColor != nil },
            set: { usesShadow in
                if usesShadow {
                    let seed = preferences.effectiveIconShadowColor ?? .black
                    preferences.iconShadowColor = DockColor(nsColor: seed)
                } else {
                    preferences.iconShadowColor = nil
                }
            }
        )
    }

    private var iconShadowColorBinding: Binding<Color> {
        Binding(
            get: {
                let nsColor = preferences.effectiveIconShadowColor ?? .black
                return Color(nsColor: nsColor)
            },
            set: { newValue in
                guard let color = DockColor(nsColor: NSColor(newValue)) else { return }
                preferences.iconShadowColor = color
            }
        )
    }

    private var usesCustomDividerColorBinding: Binding<Bool> {
        Binding(
            get: { preferences.effectiveDividerColor != nil },
            set: { usesColor in
                if usesColor {
                    let seed = preferences.effectiveDividerColor ?? .labelColor
                    preferences.dividerColor = DockColor(nsColor: seed)
                } else {
                    preferences.dividerColor = nil
                }
            }
        )
    }

    private var dividerColorBinding: Binding<Color> {
        Binding(
            get: {
                let nsColor = preferences.effectiveDividerColor ?? .labelColor
                return Color(nsColor: nsColor)
            },
            set: { newValue in
                guard let color = DockColor(nsColor: NSColor(newValue)) else { return }
                preferences.dividerColor = color
            }
        )
    }

    private var usesWindowBackgroundImage: Bool {
        preferences.effectiveWindowBackgroundImageURL != nil
    }

    private var selectedWindowBackgroundImageName: String? {
        guard let path = preferences.windowBackgroundImagePath, !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var selectedActiveIndicatorImageName: String? {
        guard let path = preferences.activeIndicatorImagePath, !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func chooseActiveIndicatorImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Image"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        preferences.activeIndicatorImagePath = url.path
    }

    private func chooseWindowBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Image"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        preferences.windowBackgroundImagePath = url.path
    }

    private func chooseTileActiveBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Image"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        preferences.tileActiveBackgroundImagePath = url.path
    }

    private var selectedActiveBackgroundImageName: String? {
        guard let path = preferences.tileActiveBackgroundImagePath, !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var hasActiveBackgroundSource: Bool {
        preferences.effectiveTileActiveBackgroundColor != nil
            || preferences.effectiveTileActiveBackgroundImageURL != nil
    }

    private var usesActiveBackgroundColorBinding: Binding<Bool> {
        Binding(
            get: { preferences.effectiveTileActiveBackgroundColor != nil },
            set: { uses in
                if uses {
                    let seed = preferences.effectiveTileActiveBackgroundColor ?? .controlAccentColor
                    preferences.tileActiveBackgroundColor = DockColor(nsColor: seed)
                } else {
                    preferences.tileActiveBackgroundColor = nil
                }
            }
        )
    }

    private var activeBackgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                let ns = preferences.effectiveTileActiveBackgroundColor ?? .controlAccentColor
                return Color(nsColor: ns)
            },
            set: { newValue in
                guard let color = DockColor(nsColor: NSColor(newValue)) else { return }
                preferences.tileActiveBackgroundColor = color
            }
        )
    }

    private var activeBackgroundOpacityBinding: Binding<Double> {
        Binding(
            get: { Double(preferences.effectiveTileActiveBackgroundOpacity) },
            set: { preferences.tileActiveBackgroundOpacity = CGFloat($0) }
        )
    }

    private var activeBackgroundCornerRadiusBinding: Binding<Double> {
        Binding(
            get: { Double(preferences.effectiveTileActiveBackgroundCornerRadius) },
            set: { preferences.tileActiveBackgroundCornerRadius = CGFloat($0) }
        )
    }

    private func chooseTileHoverBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Image"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        preferences.tileHoverBackgroundImagePath = url.path
    }

    private var selectedHoverBackgroundImageName: String? {
        guard let path = preferences.tileHoverBackgroundImagePath, !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var hasHoverBackgroundSource: Bool {
        preferences.effectiveTileHoverBackgroundColor != nil
            || preferences.effectiveTileHoverBackgroundImageURL != nil
    }

    private var usesHoverBackgroundColorBinding: Binding<Bool> {
        Binding(
            get: { preferences.effectiveTileHoverBackgroundColor != nil },
            set: { uses in
                if uses {
                    let seed = preferences.effectiveTileHoverBackgroundColor ?? .white
                    preferences.tileHoverBackgroundColor = DockColor(nsColor: seed)
                } else {
                    preferences.tileHoverBackgroundColor = nil
                }
            }
        )
    }

    private var hoverBackgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                let ns = preferences.effectiveTileHoverBackgroundColor ?? .white
                return Color(nsColor: ns)
            },
            set: { newValue in
                guard let color = DockColor(nsColor: NSColor(newValue)) else { return }
                preferences.tileHoverBackgroundColor = color
            }
        )
    }

    private var hoverBackgroundOpacityBinding: Binding<Double> {
        Binding(
            get: { Double(preferences.effectiveTileHoverBackgroundOpacity) },
            set: { preferences.tileHoverBackgroundOpacity = CGFloat($0) }
        )
    }

    private var hoverBackgroundCornerRadiusBinding: Binding<Double> {
        Binding(
            get: { Double(preferences.effectiveTileHoverBackgroundCornerRadius) },
            set: { preferences.tileHoverBackgroundCornerRadius = CGFloat($0) }
        )
    }

    private var hoverScaleBinding: Binding<Double> {
        Binding(
            get: { Double(preferences.effectiveTileHoverScale) },
            set: { preferences.tileHoverScale = CGFloat($0) }
        )
    }

    private var hoverOpacityBinding: Binding<Double> {
        Binding(
            get: { Double(preferences.effectiveTileHoverOpacity) },
            set: { preferences.tileHoverOpacity = CGFloat($0) }
        )
    }

    @ViewBuilder
    private func cornerRadiusRow(
        label: String,
        binding: Binding<CGFloat?>,
        effective: CGFloat
    ) -> some View {
        // Three-state row: the toggle is the user's *intent* (override this
        // corner or inherit the uniform value); the slider only matters
        // when the override is on. Mirrors `usesCustomWindowBorderBinding`
        // pattern, flipping the toggle off restores nil + clears the
        // appearance-override flag so the theme/uniform value comes back.
        let usesOverride = Binding<Bool>(
            get: { binding.wrappedValue != nil },
            set: { uses in
                if uses {
                    binding.wrappedValue = effective
                } else {
                    binding.wrappedValue = nil
                }
            }
        )
        let value = Binding<Double>(
            get: { Double(binding.wrappedValue ?? effective) },
            set: { binding.wrappedValue = CGFloat($0) }
        )

        HStack {
            Toggle(isOn: usesOverride) {
                Text(L10n.text(label)).frame(width: 120, alignment: .leading)
            }
            .toggleStyle(.checkbox)
            Slider(value: value, in: 0...maximumCornerRadius, step: 1) {
                Text(L10n.text(label))
            }
            .labelsHidden()
            .disabled(!usesOverride.wrappedValue)
            Text("\(Int(effective)) pt")
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func contentInsetRow(label: String, value: Binding<CGFloat>) -> some View {
        HStack {
            Text(L10n.text(label)).frame(width: 120, alignment: .leading)
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = CGFloat($0) }
            ), in: 0...16, step: 1) {
                Text(L10n.text(label))
            }
            .labelsHidden()
            Text("\(Int(value.wrappedValue)) pt")
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private enum DividerImageSlot {
        case global, left, right
    }

    private func chooseDividerImage(slot: DividerImageSlot) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Image"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        switch slot {
        case .global:
            preferences.dividerImagePath = url.path
        case .left:
            preferences.leftDividerImagePath = url.path
        case .right:
            preferences.rightDividerImagePath = url.path
        }
    }
}
