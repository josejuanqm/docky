//
//  AppearanceSettingsView.swift
//  Docky
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        Form {
            Section("Indicators") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Active Indicator Shape")
                            .font(.headline)
                        
                        Spacer()

                        Picker("Active Indicator Shape", selection: $preferences.activeIndicatorShape) {
                            ForEach(DockTileIndicatorShape.allCases) { shape in
                                Text(shape.title).tag(shape)
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
            }

            Section("Tile Layout") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tile Clip Shape")
                            .font(.headline)
                        
                        Spacer()

                        Picker("Tile Clip Shape", selection: $preferences.tileClipShape) {
                            ForEach(DockClipShape.allCases) { shape in
                                Text(shape.title).tag(shape)
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

                    Text("Seeded from the macOS Dock when you sync, then adjusted locally for Docky without writing back to the system Dock.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Magnification", isOn: systemDockMagnificationBinding)
                        .font(.headline)

                    Text("Seeded from the macOS Dock when you sync, then adjusted locally for Docky without writing back to the system Dock.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Magnified Size")
                        .font(.headline)

                    HStack {
                        Slider(value: systemDockLargeSizeBinding, in: max(16, Double(dockSettings.tileSize.rounded()))...192, step: 1) {
                            Text("Magnified Size")
                        }
                        .labelsHidden()

                        Text("\(Int(dockSettings.largeSize.rounded())) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    Text("Sets Docky's larger icon size after the last system Dock sync, without writing back to the system Dock.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .disabled(!dockSettings.magnification)
            }

            Section("Window Shape") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Chrome Clip Shape")
                            .font(.headline)
                        
                        Spacer()

                        Picker("Chrome Clip Shape", selection: $preferences.windowClipShape) {
                            ForEach(DockClipShape.allCases) { shape in
                                Text(shape.title).tag(shape)
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

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Disable Glass Look", isOn: $preferences.disablesGlassLook)
                        .font(.headline)

                    Text("Removes the main window's glossy gradient border while keeping the existing blur and background tinting.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Window Background") {
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

            Section {
                Button("Reset to Defaults") {
                    preferences.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
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
            set: { dockSettings.setLargeSize(CGFloat(max($0, Double(dockSettings.tileSize)))) }
        )
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
        case .dot, .pill:
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
}
