//
//  PermissionsView.swift
//  Docky
//

import AppKit
import SwiftUI

struct PermissionsView: View {
    @ObservedObject private var service = PermissionsService.shared
    @State private var currentIndex = 0

    let steps: [Permission]
    let onComplete: () -> Void

    private var step: Permission { steps[currentIndex] }
    private var status: PermissionStatus { service.status(for: step) }
    private var isLastStep: Bool { currentIndex == steps.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            content
            Spacer()
            grantActions
            footer
        }
        .padding(28)
        .frame(width: 520, height: 420)
        .onAppear { service.refresh() }
        .task(id: currentIndex) {
            guard step == .finderAutomation, status == .notDetermined else { return }
            _ = await service.requestAutomationPermission(for: step)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to Docky")
                .font(.largeTitle.bold())
            Text("Step \(currentIndex + 1) of \(steps.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                Text(step.title)
                    .font(.title2.bold())
                if let method = grantMethodLabel {
                    Text(method)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            Text(step.explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsAppDragProxy {
                draggableAppProxy
            }
        }
    }

    @ViewBuilder
    private var grantActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(systemSettingsButtonTitle) {
                service.openSystemSettings(for: step)
            }
            if step == .finderAutomation {
                requestButton
            }
        }
    }

    private var showsAppDragProxy: Bool {
        switch step {
        case .userFolders, .accessibility:
            true
        case .finderAutomation:
            false
        }
    }

    private var draggableAppProxy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drag Docky into the list in System Settings to add it without searching.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: dockyAppURL.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Docky.app")
                        .font(.headline)
                    Text("Drag this into the macOS privacy list")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "hand.draw")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15))
            )
            .onDrag {
                NSItemProvider(object: dockyAppURL as NSURL)
            }
        }
        .padding(.top, 4)
    }

    private var dockyAppURL: URL {
        Bundle.main.bundleURL
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Re-check") { service.refresh() }
            Spacer()
            Button(isLastStep ? "Continue" : "Next") { advance() }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
        }
    }

    private var grantMethodLabel: String? {
        switch grantMethod {
        case .fullDiskAccess: return "Full Disk Access"
        case .automation: return "Automation"
        case .accessibility: return "Accessibility"
        case .none: return nil
        }
    }

    @ViewBuilder
    private var requestButton: some View {
        if step == .finderAutomation {
            Button("Request Finder Access") {
                Task {
                    _ = await service.requestAutomationPermission(for: step)
                }
            }
        }
    }

    private var grantMethod: GrantMethod? {
        switch step {
        case .userFolders:
            return service.userFoldersGrantMethod
        case .finderAutomation:
            return service.finderAutomationGrantMethod
        case .accessibility:
            return service.accessibilityGrantMethod
        }
    }

    private var systemSettingsButtonTitle: String {
        switch step {
        case .finderAutomation:
            return "Open System Settings (Automation)"
        case .userFolders:
            return "Open System Settings (Full Disk Access)"
        case .accessibility:
            return "Open System Settings (Accessibility)"
        }
    }

    private var statusIcon: String {
        switch status {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "exclamationmark.triangle.fill"
        case .notDetermined: return "circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .secondary
        }
    }

    private var canAdvance: Bool {
        if step.isRequiredAtLaunch {
            return status == .granted
        }
        return status != .notDetermined
    }

    private func advance() {
        if isLastStep {
            onComplete()
        } else {
            currentIndex += 1
        }
    }
}
