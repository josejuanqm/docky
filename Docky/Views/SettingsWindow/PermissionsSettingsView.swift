//
//  PermissionsSettingsView.swift
//  Docky
//

import SwiftUI

struct PermissionsSettingsView: View {
    @ObservedObject private var service = PermissionsService.shared

    var body: some View {
        Form {
            permissionSection(for: .userFolders)
            permissionSection(for: .finderAutomation)
            permissionSection(for: .accessibility)
            permissionSection(for: .screenCapture)
            permissionSection(for: .location)
            permissionSection(for: .calendar)
            permissionSection(for: .reminders)

            Section {
                Button("Re-check Permissions") {
                    service.refresh()
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func permissionSection(for permission: Permission) -> some View {
        Section(permission.title) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status")
                        .font(.headline)

                    Spacer()

                    Text(statusText(for: permission))
                        .foregroundStyle(statusColor(for: permission))
                }

                if let grantMethod = grantMethodText(for: permission) {
                    Divider()

                    HStack {
                        Text("Access Via")
                            .font(.headline)

                        Spacer()

                        Text(grantMethod)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(permission.explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button("Open System Settings") {
                        service.openSystemSettings(for: permission)
                    }

                    if permission == .finderAutomation || permission == .accessibility || permission == .screenCapture || permission == .location || permission == .calendar || permission == .reminders {
                        requestButton(for: permission)
                    }

                    if permission == .finderAutomation, service.finderAutomation != .notDetermined {
                        Button("Forget Status") {
                            service.clearAutomationStatus(for: permission)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func requestButton(for permission: Permission) -> some View {
        if permission == .finderAutomation || permission == .accessibility || permission == .screenCapture || permission == .location || permission == .calendar || permission == .reminders {
            Button(buttonTitle(for: permission)) {
                Task {
                    _ = await service.requestPermission(for: permission)
                }
            }
        }
    }

    private func statusText(for permission: Permission) -> String {
        switch service.status(for: permission) {
        case .granted: return String(localized: "Granted")
        case .denied: return String(localized: "Missing")
        case .notDetermined: return String(localized: "Not Determined")
        }
    }

    private func statusColor(for permission: Permission) -> Color {
        switch service.status(for: permission) {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .secondary
        }
    }

    private func grantMethodText(for permission: Permission) -> String? {
        switch grantMethod(for: permission) {
        case .fullDiskAccess: return String(localized: "Full Disk Access")
        case .automation: return String(localized: "Automation")
        case .accessibility: return String(localized: "Accessibility")
        case .screenCapture: return String(localized: "Screen Recording")
        case .location: return String(localized: "Location")
        case .none: return nil
        }
    }

    private func grantMethod(for permission: Permission) -> GrantMethod? {
        switch permission {
        case .userFolders:
            return service.userFoldersGrantMethod
        case .finderAutomation:
            return service.finderAutomationGrantMethod
        case .systemEventsAutomation:
            return service.systemEventsAutomationGrantMethod
        case .accessibility:
            return service.accessibilityGrantMethod
        case .screenCapture:
            return service.screenCaptureGrantMethod
        case .location:
            return service.locationGrantMethod
        case .calendar, .reminders:
            return nil
        }
    }

    private func buttonTitle(for permission: Permission) -> String {
        switch permission {
        case .userFolders: return String(localized: "Open System Settings")
        case .finderAutomation: return String(localized: "Request Finder Access")
        case .systemEventsAutomation: return String(localized: "Request System Events Access")
        case .accessibility: return String(localized: "Request Accessibility Access")
        case .screenCapture: return String(localized: "Request Screen Recording Access")
        case .location: return String(localized: "Request Location Access")
        case .calendar: return String(localized: "Request Calendar Access")
        case .reminders: return String(localized: "Request Reminders Access")
        }
    }
}
