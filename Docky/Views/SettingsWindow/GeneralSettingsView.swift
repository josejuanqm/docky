//
//  GeneralSettingsView.swift
//  Docky
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        Form {
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Window Position")
                        .font(.headline)

                    Picker("Window Position", selection: $preferences.windowPosition) {
                        ForEach(DockWindowPosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Choose where Docky sits on screen, or mirror the macOS Dock position.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Autohide Window", isOn: $preferences.autohidesWindow)
                        .font(.headline)

                    Text("Slides Docky's window off-screen until the pointer reaches its edge. Reveal and hide timing still follows the system Dock settings.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Shows Grouped Opened Apps In Dock", isOn: $preferences.showsGroupedOpenedAppsInDock)
                        .font(.headline)

                    Text("Shows running apps from an app folder immediately to the right of that folder, and lets the folder reflect how many grouped apps are open.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Indicator Shape")
                        .font(.headline)

                    Picker("Active Indicator Shape", selection: $preferences.activeIndicatorShape) {
                        ForEach(DockTileIndicatorShape.allCases) { shape in
                            Text(shape.title).tag(shape)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Choose whether running apps are marked with the classic dot or a pill.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tile Vertical Padding")
                        .font(.headline)

                    HStack {
                        Slider(value: $preferences.tileVerticalPadding, in: 8...32, step: 1) {
                            Text("Tile Vertical Padding")
                        }
                        Text("\(Int(preferences.tileVerticalPadding)) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    Text("Controls the top and bottom inset inside each dock tile.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Window Corner Radius")
                        .font(.headline)

                    HStack {
                        Slider(value: windowCornerRadiusBinding, in: 0...maximumCornerRadius, step: 1) {
                            Text("Window Corner Radius")
                        }
                        Text("\(Int(min(preferences.windowCornerRadius, maximumCornerRadius))) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    Text("Controls the roundness of the main dock window and its border, up to a full capsule.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tile Spacing")
                        .font(.headline)

                    HStack {
                        Slider(value: $preferences.tileSpacing, in: 0...16, step: 1) {
                            Text("Tile Spacing")
                        }
                        Text("\(Int(preferences.tileSpacing)) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }

                    Text("Controls the horizontal gap between adjacent dock tiles.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
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
        let iconHeight = dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize
        return (iconHeight + preferences.tileVerticalPadding * 2) / 2
    }

    private var windowCornerRadiusBinding: Binding<CGFloat> {
        Binding(
            get: { min(preferences.windowCornerRadius, maximumCornerRadius) },
            set: { preferences.windowCornerRadius = $0 }
        )
    }
}
