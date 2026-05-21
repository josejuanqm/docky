//
//  ProfilesSettingsView.swift
//  Docky
//
//  Manages dock profiles — create / rename / duplicate / delete / switch.
//  Each profile owns its own tile-store (pinned, trailing, widgets, app
//  widget displays, hidden apps). Everything else (theme, sizing, etc.)
//  stays global.
//

import SwiftUI

struct ProfilesSettingsView: View {
    @Bindable private var profileService = ProfileService.shared

    var body: some View {
        Form {
            Section {
                Text("Dock profiles each keep their own pinned apps, trailing items, widgets, and hidden-app list. Switch between them from the small ball at the leading edge of the dock.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Profiles") {
                ForEach(profileService.profiles) { profile in
                    ProfileRow(profile: profile)
                        .padding(.vertical, 2)
                }

                Button {
                    addProfile()
                } label: {
                    Label("Add Profile", systemImage: "plus.circle")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addProfile() {
        let baseName = "Profile"
        let existingNames = Set(profileService.profiles.map(\.name))
        var name = baseName
        var counter = 1
        while existingNames.contains(name) {
            counter += 1
            name = "\(baseName) \(counter)"
        }
        let created = profileService.createProfile(name: name)
        profileService.setActiveProfile(id: created.id)
    }
}

private struct ProfileRow: View {
    let profile: DockProfile
    @Bindable private var profileService = ProfileService.shared

    static let symbolOptions: [String] = [
        "house.fill",
        "briefcase.fill",
        "person.fill",
        "gamecontroller.fill",
        "moon.stars.fill",
        "sparkles",
        "paintbrush.fill",
        "music.note",
        "film.fill",
        "book.fill",
        "airplane",
        "car.fill",
        "leaf.fill",
        "flame.fill",
        "bolt.fill",
        "heart.fill"
    ]

    private var isActive: Bool {
        profileService.activeProfileID == profile.id
    }

    private var canDelete: Bool {
        profileService.profiles.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                symbolPicker

                TextField("Profile name", text: nameBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Button("Switch") {
                        profileService.setActiveProfile(id: profile.id)
                    }
                }

                Spacer()

                Menu {
                    Button {
                        duplicate()
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }

                    Button(role: .destructive) {
                        profileService.deleteProfile(id: profile.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(!canDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            ProfileTriggersSection(profile: profile)
                .padding(.leading, 40)
        }
    }

    private var symbolPicker: some View {
        Menu {
            ForEach(Self.symbolOptions, id: \.self) { symbol in
                Button {
                    profileService.updateProfileSymbol(id: profile.id, symbolName: symbol)
                } label: {
                    Label(symbol, systemImage: symbol)
                }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                Image(systemName: profile.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: {
                profileService.profiles.first(where: { $0.id == profile.id })?.name ?? ""
            },
            set: { newValue in
                profileService.renameProfile(id: profile.id, to: newValue)
            }
        )
    }

    private func duplicate() {
        let base = profile.name
        let existingNames = Set(profileService.profiles.map(\.name))
        var name = "\(base) Copy"
        var counter = 1
        while existingNames.contains(name) {
            counter += 1
            name = "\(base) Copy \(counter)"
        }
        profileService.createProfile(
            name: name,
            symbolName: profile.symbolName,
            basedOn: profile
        )
    }
}

// MARK: - Triggers

private struct ProfileTriggersSection: View {
    let profile: DockProfile
    @Bindable private var profileService = ProfileService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if profile.triggers.isEmpty {
                Text("No triggers — this profile only activates when picked manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profile.triggers) { trigger in
                    TriggerRow(profile: profile, trigger: trigger)
                }
            }

            Menu {
                Button {
                    profileService.addTrigger(.timeOfDay(TimeOfDayTrigger()), to: profile.id)
                } label: {
                    Label("Time of Day", systemImage: "clock")
                }
                Button {
                    profileService.addTrigger(
                        .frontmostApp(FrontmostAppTrigger(bundleIdentifier: "")),
                        to: profile.id
                    )
                } label: {
                    Label("Frontmost App", systemImage: "app.dashed")
                }
                Button {
                    profileService.addTrigger(
                        .space(SpaceTrigger(bundleIdentifier: "")),
                        to: profile.id
                    )
                } label: {
                    Label("Space with App…", systemImage: "rectangle.3.group")
                }
            } label: {
                Label("Add Trigger…", systemImage: "plus.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

private struct TriggerRow: View {
    let profile: DockProfile
    let trigger: ProfileTrigger
    @Bindable private var profileService = ProfileService.shared

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)

            editor
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                profileService.removeTrigger(trigger.id, from: profile.id)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch trigger {
        case .timeOfDay: return "clock"
        case .frontmostApp: return "app.dashed"
        case .space: return "rectangle.3.group"
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch trigger {
        case .timeOfDay(let t):
            TimeOfDayTriggerEditor(profile: profile, triggerID: trigger.id, model: t)
        case .frontmostApp(let t):
            FrontmostAppTriggerEditor(profile: profile, triggerID: trigger.id, model: t)
        case .space(let t):
            SpaceTriggerEditor(profile: profile, triggerID: trigger.id, model: t)
        }
    }
}

private struct TimeOfDayTriggerEditor: View {
    let profile: DockProfile
    let triggerID: String
    @State var model: TimeOfDayTrigger
    @Bindable private var profileService = ProfileService.shared

    private static let weekdays: [(symbol: String, label: String)] = [
        (symbol: "1", label: "Sun"),
        (symbol: "2", label: "Mon"),
        (symbol: "3", label: "Tue"),
        (symbol: "4", label: "Wed"),
        (symbol: "5", label: "Thu"),
        (symbol: "6", label: "Fri"),
        (symbol: "7", label: "Sat")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                DatePicker(
                    "From",
                    selection: startBinding,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()

                Text("to")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                DatePicker(
                    "To",
                    selection: endBinding,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            }

            HStack(spacing: 4) {
                ForEach(Self.weekdays, id: \.label) { day in
                    let weekdayIndex = Int(day.symbol) ?? 1
                    let isOn = model.weekdays.contains(weekdayIndex)
                    Button {
                        if isOn {
                            model.weekdays.remove(weekdayIndex)
                        } else {
                            model.weekdays.insert(weekdayIndex)
                        }
                        commit()
                    } label: {
                        Text(day.label)
                            .font(.caption2)
                            .frame(minWidth: 30)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isOn ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1))
                            )
                            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { Self.date(from: model.startMinuteOfDay) },
            set: { date in
                model.startMinuteOfDay = Self.minutesFrom(date: date)
                commit()
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { Self.date(from: model.endMinuteOfDay) },
            set: { date in
                model.endMinuteOfDay = Self.minutesFrom(date: date)
                commit()
            }
        )
    }

    private static func date(from minutes: Int) -> Date {
        let calendar = Calendar.current
        let components = DateComponents(hour: minutes / 60, minute: minutes % 60)
        return calendar.date(from: components) ?? Date()
    }

    private static func minutesFrom(date: Date) -> Int {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func commit() {
        profileService.updateTrigger(.timeOfDay(model), in: profile.id)
    }
}

private struct FrontmostAppTriggerEditor: View {
    let profile: DockProfile
    let triggerID: String
    @State var model: FrontmostAppTrigger
    @Bindable private var profileService = ProfileService.shared

    var body: some View {
        HStack(spacing: 8) {
            Text("When")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(runningApps(), id: \.bundleIdentifier) { app in
                    Button {
                        model.bundleIdentifier = app.bundleIdentifier
                        commit()
                    } label: {
                        Text(app.displayName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(displayLabel)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Text("is frontmost")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var displayLabel: String {
        if model.bundleIdentifier.isEmpty { return "Pick app…" }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: model.bundleIdentifier) {
            return FileManager.default.displayName(atPath: app.path)
        }
        return model.bundleIdentifier
    }

    private struct AppEntry {
        let bundleIdentifier: String
        let displayName: String
    }

    private func runningApps() -> [AppEntry] {
        NSWorkspace.shared.runningApplications
            .compactMap { app -> AppEntry? in
                guard let bundleID = app.bundleIdentifier,
                      app.activationPolicy == .regular
                else { return nil }
                let name = app.localizedName ?? bundleID
                return AppEntry(bundleIdentifier: bundleID, displayName: name)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func commit() {
        profileService.updateTrigger(.frontmostApp(model), in: profile.id)
    }
}

private struct SpaceTriggerEditor: View {
    let profile: DockProfile
    let triggerID: String
    @State var model: SpaceTrigger
    @Bindable private var profileService = ProfileService.shared

    var body: some View {
        HStack(spacing: 8) {
            Text("When on space with")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(runningApps(), id: \.bundleIdentifier) { app in
                    Button {
                        model.bundleIdentifier = app.bundleIdentifier
                        commit()
                    } label: {
                        Text(app.displayName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(displayLabel)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var displayLabel: String {
        if model.bundleIdentifier.isEmpty { return "Pick app…" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: model.bundleIdentifier) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return model.bundleIdentifier
    }

    private struct AppEntry {
        let bundleIdentifier: String
        let displayName: String
    }

    private func runningApps() -> [AppEntry] {
        NSWorkspace.shared.runningApplications
            .compactMap { app -> AppEntry? in
                guard let bundleID = app.bundleIdentifier,
                      app.activationPolicy == .regular
                else { return nil }
                let name = app.localizedName ?? bundleID
                return AppEntry(bundleIdentifier: bundleID, displayName: name)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func commit() {
        profileService.updateTrigger(.space(model), in: profile.id)
    }
}
