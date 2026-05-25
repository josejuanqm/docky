//
//  LaunchpadSettingsView.swift
//  Docky
//

import SwiftUI

struct LaunchpadSettingsView: View {
    /// Hides the "Availability" section (Pro upsell + global enable
    /// toggle). The detached inspector that floats over the launchpad
    /// sets this so users live-tuning the grid don't see a switch that
    /// would hide the very surface they're standing on.
    var hidesAvailabilitySection: Bool = false

    @Bindable private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared
    @State private var isRecordingShortcut = false

    var body: some View {
        Form {
            if !hidesAvailabilitySection {
                Section("Availability") {
                    if !product.isUnlocked(.launchpad) {
                        ProFeatureNotice(feature: .launchpad)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable Launchpad", isOn: $preferences.enablesLaunchpadOverlay)
                            .font(.headline)
                            .disabled(!product.isUnlocked(.launchpad))

                        Text("Turn Docky's Launchpad overlay on or off without removing its shortcut or layout preferences.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Shortcut") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Global Shortcut")
                                .font(.headline)

                            Text("Optionally assign a global shortcut that toggles Docky's Launchpad overlay from anywhere.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        ShortcutRecorderControl(
                            shortcut: preferences.launchpadShortcut,
                            isRecording: $isRecordingShortcut,
                            resetShortcut: nil
                        ) { shortcut in
                            preferences.launchpadShortcut = shortcut
                        }
                        .disabled(!product.isUnlocked(.launchpad) || !preferences.enablesLaunchpadOverlay)
                    }

                    Text("Leave this unset if you only want to open Launchpad from the Docky tile or context menu.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Layout") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Scroll Direction")
                            .font(.headline)

                        Spacer()

                        Picker("Scroll Direction", selection: $preferences.launchpadLayoutAxis) {
                            ForEach(LaunchpadLayoutAxis.allCases) { axis in
                                Text(axis.title).tag(axis)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .disabled(!product.isUnlocked(.launchpad) || !preferences.enablesLaunchpadOverlay)
                    }

                    Text(preferences.launchpadLayoutAxis.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    HStack {
                        Text("Grid Columns")
                            .font(.headline)

                        Spacer()

                        Stepper("\(preferences.launchpadGridColumnCount)", value: $preferences.launchpadGridColumnCount, in: 1...12)
                            .foregroundStyle(.secondary)
                            .disabled(!product.isUnlocked(.launchpad) || !preferences.enablesLaunchpadOverlay)
                    }

                    HStack {
                        Text("Grid Rows")
                            .font(.headline)

                        Spacer()

                        Stepper("\(preferences.launchpadGridRowCount)", value: $preferences.launchpadGridRowCount, in: 1...10)
                            .foregroundStyle(.secondary)
                            // Rows are only consulted in paged mode;
                            // vertical mode grows as long as needed.
                            .disabled(!product.isUnlocked(.launchpad)
                                      || !preferences.enablesLaunchpadOverlay
                                      || preferences.launchpadLayoutAxis == .vertical)
                    }

                    Text("Sets the Launchpad grid dimensions. Docky uses these counts when the icons fit on screen, defaulting to 7 columns × 5 rows. Row count is ignored when scroll direction is continuous.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    HStack {
                        Text("Icon Size")
                            .font(.headline)

                        Spacer()

                        Text("\(Int(preferences.launchpadBaseIconSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $preferences.launchpadBaseIconSize,
                        in: 48...192,
                        step: 1
                    )
                    .disabled(!product.isUnlocked(.launchpad) || !preferences.enablesLaunchpadOverlay)

                    Text("Maximum icon edge on a 1440p screen. Smaller displays scale down from this value; larger ones are clamped to it. Default is 128 pt.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    HStack {
                        Text("Column Spacing")
                            .font(.headline)

                        Spacer()

                        Text("\(Int(preferences.launchpadColumnSpacing)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $preferences.launchpadColumnSpacing,
                        in: 0...96,
                        step: 1
                    )
                    .disabled(!product.isUnlocked(.launchpad) || !preferences.enablesLaunchpadOverlay)

                    Text("Horizontal gap between icons at the reference height. Lower values pack icons tighter, higher values spread them out.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Transparency")
                            .font(.headline)

                        Spacer()

                        Text("\(Int(preferences.launchpadOverlayTransparency * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: launchpadTransparencyBinding, in: 0...1, step: 0.01)
                        .disabled(!product.isUnlocked(.launchpad) || !preferences.enablesLaunchpadOverlay)

                    Text("Adjusts how transparent the Launchpad backdrop is. Lower values darken the screen behind the grid; higher values let more of your desktop show through.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private var launchpadTransparencyBinding: Binding<CGFloat> {
        Binding(
            get: { preferences.launchpadOverlayTransparency },
            set: { preferences.launchpadOverlayTransparency = min(max($0, 0), 1) }
        )
    }
}
