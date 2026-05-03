//
//  BehaviorSettingsView.swift
//  Docky
//

import SwiftUI

struct BehaviorSettingsView: View {
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared

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

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Display")
                            .font(.headline)

                        Spacer()

                        Picker("Display", selection: $preferences.windowDisplayTarget) {
                            ForEach(DockWindowDisplayTarget.allCases) { target in
                                Text(target.title).tag(target)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Text("Docky uses a single main window. Choose whether it stays on the primary display or follows the display containing the pointer.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Spaces")
                            .font(.headline)

                        Spacer()

                        Picker("Spaces", selection: $preferences.windowSpaceBehavior) {
                            ForEach(DockWindowSpaceBehavior.allCases) { behavior in
                                Text(behavior.title).tag(behavior)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Text("Choose whether Docky appears only in the active Space or joins every Space, including fullscreen auxiliary presentation.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Visibility") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Autohide Window", isOn: $preferences.autohidesWindow)
                        .font(.headline)

                    Text("Slides Docky's window off-screen until the pointer reaches its edge. Hide timing is controlled by Docky's own delay below, so hiding the system Dock does not stretch it.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Autohide Delay")
                        .font(.headline)

                    HStack {
                        Slider(value: $preferences.autohideWindowDelay, in: 0...5, step: 0.05) {
                            Text("Autohide Delay")
                        }
                        .labelsHidden()

                        Text("\(String(format: "%.2f", preferences.autohideWindowDelay)) s")
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }

                    Text("Controls how long Docky waits after the pointer leaves and interactions end before the window hides.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .disabled(!preferences.autohidesWindow)

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
                .disabled(!preferences.showsRunningApps)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show Running Apps", isOn: $preferences.showsRunningApps)
                        .font(.headline)

                    Text("When turned off, unpinned running apps are hidden from Docky so it acts as a static shelf alongside the system Dock.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show Minimized Windows", isOn: $preferences.showsMinimizedWindows)
                        .font(.headline)

                    Text("When turned off, minimized window tiles do not appear in Docky's trailing section.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("App Tile Click") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("When App Is Already Active")
                            .font(.headline)

                        Spacer()

                        Picker("When App Is Already Active", selection: frontmostClickBehaviorBinding) {
                            ForEach(AppTileFrontmostClickBehavior.allCases) { behavior in
                                Text(frontmostClickBehaviorTitle(behavior)).tag(behavior)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Text("Choose what happens when you click the tile of an app that already has the focus. Clicking idle apps always launches, focuses, or restores their last minimized window.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Widgets") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show Expanded Preview on Hover", isOn: $preferences.enablesWidgetHoverPreview)
                        .font(.headline)

                    Text("When enabled, hovering an expandable widget tile shows a larger preview in a separate window. Turn this off to keep widgets at their pinned size.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Apply To Sizes")
                        .font(.headline)

                    ForEach(TileSpan.allCases) { span in
                        Toggle(spanTitle(for: span), isOn: spanBinding(for: span))
                    }

                    Text("Choose which tile sizes trigger the expanded preview. Widgets pinned at other sizes stay at their pinned size on hover.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .disabled(!preferences.enablesWidgetHoverPreview)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Hover Preview Delay")
                        .font(.headline)

                    HStack {
                        Slider(value: $preferences.widgetHoverPreviewDelay, in: 0...2, step: 0.05) {
                            Text("Hover Preview Delay")
                        }
                        .labelsHidden()

                        Text(preferences.widgetHoverPreviewDelay == 0
                            ? "Off"
                            : "\(String(format: "%.2f", preferences.widgetHoverPreviewDelay)) s")
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }

                    Text("Time the cursor must rest on a widget before its expanded preview window appears. Set to zero for an immediate preview.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .disabled(!preferences.enablesWidgetHoverPreview)
            }

            Section("Launch") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Open at Login", isOn: $preferences.opensAtLogin)
                        .font(.headline)

                    Text("Registers Docky as a login item so it starts automatically after you sign in.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("System Dock") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Hide System Dock", isOn: $preferences.hidesSystemDock)
                        .font(.headline)

                    Text("Forces the macOS Dock to autohide with a long delay, disables bouncing and launch animations, and keeps the system Dock aligned with Docky's explicit edge selection while this stays on. Docky snapshots your current Dock settings first and restores them when you turn this off or quit Docky. This no longer affects Docky's own autohide delay.")
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
                if !product.isUnlocked(.groupedAppFolders) {
                    ProFeatureNotice(feature: .groupedAppFolders)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Shows Grouped Opened Apps In Dock", isOn: $preferences.showsGroupedOpenedAppsInDock)
                        .font(.headline)
                        .disabled(!product.isUnlocked(.groupedAppFolders))

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
    }

    private func spanTitle(for span: TileSpan) -> String {
        switch span {
        case .one: "Small"
        case .two: "Medium"
        case .three: "Large"
        }
    }

    private var frontmostClickBehaviorBinding: Binding<AppTileFrontmostClickBehavior> {
        Binding(
            get: { preferences.appTileFrontmostClickBehavior },
            set: { newValue in
                if newValue.requiresPro && product.currentTier != .pro {
                    preferences.appTileFrontmostClickBehavior = .none
                } else {
                    preferences.appTileFrontmostClickBehavior = newValue
                }
            }
        )
    }

    private func frontmostClickBehaviorTitle(_ behavior: AppTileFrontmostClickBehavior) -> String {
        let isLocked = behavior.requiresPro && product.currentTier != .pro
        return isLocked ? "\(behavior.title) (Pro)" : behavior.title
    }

    private func spanBinding(for span: TileSpan) -> Binding<Bool> {
        Binding(
            get: { preferences.widgetHoverPreviewSpans.contains(span) },
            set: { isOn in
                var spans = preferences.widgetHoverPreviewSpans
                if isOn {
                    spans.insert(span)
                } else {
                    spans.remove(span)
                }
                preferences.widgetHoverPreviewSpans = spans
            }
        )
    }

}
