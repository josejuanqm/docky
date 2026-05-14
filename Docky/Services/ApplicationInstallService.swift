//
//  ApplicationInstallService.swift
//  Docky
//

import AppKit
import Foundation

final class ApplicationInstallService {
    static let shared = ApplicationInstallService()

    private let promptDeferralKey = "docky.applicationInstallPromptDeferredPath"
    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard

    var isRunningFromApplicationsDirectory: Bool {
        let currentBundleURL = Bundle.main.bundleURL.standardizedFileURL
        return applicationDirectories.contains { currentBundleURL.path.hasPrefix($0.path + "/") }
    }

    @discardableResult
    func promptToMoveToApplicationsIfNeeded() -> Bool {
        #if APP_STORE_SANDBOX
        // App Store installs land in /Applications by Apple's machinery;
        // sandboxed apps also can't write outside their container, so
        // this whole prompt is meaningless in MAS.
        return false
        #else
        guard needsToMoveToApplications else {
            clearPromptDeferral()
            return false
        }
        #endif

        guard deferredBundlePath != currentBundlePath else {
            return false
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Move Docky to Applications?")
        alert.informativeText = String(localized: "Docky works best from the Applications folder. Moving it there avoids running from a disk image or temporary location and makes features like Open at Login reliable.")
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))

        if alert.runModal() == .alertFirstButtonReturn {
            return moveToApplicationsAndRelaunch()
        }

        defaults.set(currentBundlePath, forKey: promptDeferralKey)
        return false
    }

    private var needsToMoveToApplications: Bool {
        !isRunningFromApplicationsDirectory
    }

    private var currentBundlePath: String {
        Bundle.main.bundleURL.standardizedFileURL.path
    }

    private var deferredBundlePath: String? {
        defaults.string(forKey: promptDeferralKey)
    }

    private var applicationDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true).standardizedFileURL,
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true).standardizedFileURL
        ]
    }

    @discardableResult
    private func moveToApplicationsAndRelaunch() -> Bool {
        let sourceURL = Bundle.main.bundleURL.standardizedFileURL

        guard let destinationDirectory = preferredApplicationsDirectory() else {
            presentMoveFailureAlert(message: "Docky could not find a writable Applications folder.")
            return false
        }

        let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)

        do {
            try replaceItemIfNeeded(at: destinationURL)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            clearPromptDeferral()
            relaunchMovedApp(at: destinationURL)
            NSApp.terminate(nil)
            return true
        } catch {
            presentMoveFailureAlert(message: error.localizedDescription)
            return false
        }
    }

    private func preferredApplicationsDirectory() -> URL? {
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if fileManager.fileExists(atPath: systemApplications.path), fileManager.isWritableFile(atPath: systemApplications.path) {
            return systemApplications
        }

        let userApplications = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        if !fileManager.fileExists(atPath: userApplications.path) {
            do {
                try fileManager.createDirectory(at: userApplications, withIntermediateDirectories: true)
            } catch {
                NSLog("[Docky] Failed to create ~/Applications: \(error.localizedDescription)")
                return nil
            }
        }

        return fileManager.isWritableFile(atPath: userApplications.path) ? userApplications : nil
    }

    private func replaceItemIfNeeded(at destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Replace existing Docky in Applications?")
        alert.informativeText = String(localized: "An existing copy of Docky is already in Applications. Replacing it will keep the newer copy you just opened.")
        alert.addButton(withTitle: String(localized: "Replace"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            throw CocoaError(.userCancelled)
        }

        var trashedURL: NSURL?
        try fileManager.trashItem(at: destinationURL, resultingItemURL: &trashedURL)
    }

    private func relaunchMovedApp(at destinationURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: destinationURL, configuration: configuration) { _, error in
            if let error {
                NSLog("[Docky] Failed to relaunch moved app: \(error.localizedDescription)")
            }
        }
    }

    private func presentMoveFailureAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Docky could not move to Applications")
        alert.informativeText = message
        alert.runModal()
    }

    private func clearPromptDeferral() {
        defaults.removeObject(forKey: promptDeferralKey)
    }

    private init() {}
}
