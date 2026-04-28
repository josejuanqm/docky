//
//  BehaviorSettingsView.swift
//  Docky
//

import SwiftUI

struct BehaviorSettingsView: View {
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        Form {
            Section("Placement") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Window Position")
                            .font(.headline)

                        Spacer()

                        Picker("Window Position", selection: $preferences.windowPosition) {
                            ForEach(DockWindowPosition.allCases) { position in
                                Text(position.title).tag(position)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Text("Choose where Docky sits on screen, or mirror the macOS Dock position.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Visibility") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Autohide Window", isOn: $preferences.autohidesWindow)
                        .font(.headline)

                    Text("Slides Docky's window off-screen until the pointer reaches its edge. Reveal and hide timing still follows the system Dock settings.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Overflow Behavior")
                            .font(.headline)

                        Spacer()

                        Picker("Overflow Behavior", selection: $preferences.overflowBehavior) {
                            ForEach(DockOverflowBehavior.allCases) { behavior in
                                Text(behavior.title).tag(behavior)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Text("Choose whether Docky shrinks to fit the screen or keeps its size and scrolls when it runs out of room on the current dock axis.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Window Axis Size")
                            .font(.headline)

                        Spacer()

                        Picker("Window Axis Size", selection: $preferences.windowAxisSizing) {
                            ForEach(DockWindowAxisSizing.allCases) { sizing in
                                Text(sizing.title).tag(sizing)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Text("Choose whether Docky hugs its tiles or stretches across the full screen width or height of the current dock axis.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show Active/Pinned Separator", isOn: $preferences.showsActivePinnedSeparator)
                        .font(.headline)

                    Text("When turned off, unpinned running apps are merged into the pinned section so the dock behaves like a single app strip.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("System Dock") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Hide System Dock", isOn: $preferences.hidesSystemDock)
                        .font(.headline)

                    Text("Forces the macOS Dock to autohide with a long delay and disables bouncing and launch animations. Docky snapshots your current Dock settings first and restores them when you turn this off or quit Docky.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Restore System Dock") {
                        preferences.hidesSystemDock = false
                    }
                    .disabled(!preferences.hidesSystemDock)
                }
                .padding(.vertical, 4)
            }

            Section("App Folders") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Shows Grouped Opened Apps In Dock", isOn: $preferences.showsGroupedOpenedAppsInDock)
                        .font(.headline)

                    Text("Shows running apps from an app folder immediately to the right of that folder, and lets the folder reflect how many grouped apps are open.")
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
}
