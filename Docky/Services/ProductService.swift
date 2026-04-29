//
//  ProductService.swift
//  Docky
//

import Combine
import Foundation
import Security

enum ProductTier: String, Codable, CaseIterable, Identifiable {
    case free
    case pro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free:
            "Free"
        case .pro:
            "Pro"
        }
    }
}

enum ProductFeatureContext {
    case standard
    case newPlacement
    case existingPlacement
}

enum ProductAvailability: Equatable {
    case available
    case lockedExisting
    case unavailableForNewPlacement

    var isUnlocked: Bool {
        self == .available
    }

    var allowsNewPlacement: Bool {
        self == .available
    }
}

enum ProductFeature: Hashable, Identifiable {
    case launchpad
    case windowSwitcher
    case customAppIcons
    case groupedAppFolders
    case scriptedActions
    case smartStack
    case widget(WidgetKind)

    static let productSettingsFeatures: [ProductFeature] = [
        .launchpad,
        .windowSwitcher,
        .customAppIcons,
        .groupedAppFolders,
        .scriptedActions,
        .smartStack,
    ]

    var id: String {
        switch self {
        case .launchpad:
            "launchpad"
        case .windowSwitcher:
            "window-switcher"
        case .customAppIcons:
            "custom-app-icons"
        case .groupedAppFolders:
            "grouped-app-folders"
        case .scriptedActions:
            "scripted-actions"
        case .smartStack:
            "smart-stack"
        case .widget(let kind):
            "widget:\(kind.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .launchpad:
            "Launchpad"
        case .windowSwitcher:
            "Window Switcher"
        case .customAppIcons:
            "Custom App Icons"
        case .groupedAppFolders:
            "Grouped App Folders"
        case .scriptedActions:
            "Scripted Actions"
        case .smartStack:
            "Smart Stack"
        case .widget(let kind):
            "\(kind.title) Widget"
        }
    }

    var summary: String {
        switch self {
        case .launchpad:
            "Docky's fullscreen app launcher, its layout controls, and optional global shortcut."
        case .windowSwitcher:
            "Switcher preview modes and window context actions in Docky's global Cmd-Tab-style switcher."
        case .customAppIcons:
            "Per-app icon overrides for pinned, running, and widget-backed apps."
        case .groupedAppFolders:
            "Show running apps inline beside app folders and reflect their open state."
        case .scriptedActions:
            "Catalog-backed AppleScript and menu-click actions for curated automation."
        case .smartStack:
            "Stacks available widgets into a single tile you can scroll through in the dock."
        case .widget(let kind):
            "Adds the \(kind.title) widget to the dock or shows it in place of a supported app icon."
        }
    }

    var requiredTier: ProductTier {
        switch self {
        case .launchpad, .windowSwitcher, .customAppIcons, .groupedAppFolders, .scriptedActions, .smartStack:
            .pro
        case .widget:
            .free
        }
    }

    var supportsLockedExistingPlacement: Bool {
        switch self {
        case .launchpad, .smartStack, .widget:
            true
        case .windowSwitcher, .customAppIcons, .groupedAppFolders, .scriptedActions:
            false
        }
    }
}

extension WidgetKind {
    nonisolated var productFeature: ProductFeature {
        .widget(self)
    }
}

extension DockEditPaletteItem {
    nonisolated var productFeature: ProductFeature? {
        switch self {
        case .launchpad:
            .launchpad
        case .widget(_, let kind):
            kind.productFeature
        case .smartStack:
            .smartStack
        case .spacer, .divider:
            nil
        }
    }
}

enum ProductRegistrationStatus: Equatable {
    case unregistered
    case stored
    case verifying
    case verified(ProductTier)
    case verificationFailed(String)

    var title: String {
        switch self {
        case .unregistered:
            "Not Registered"
        case .stored:
            "Registration Saved"
        case .verifying:
            "Verifying Registration"
        case .verified(let tier):
            "Registered: \(tier.title)"
        case .verificationFailed:
            "Unable to Verify"
        }
    }

    var message: String {
        switch self {
        case .unregistered:
            "Register Docky Pro to unlock premium features."
        case .stored:
            "Your license key is saved on this Mac."
        case .verifying:
            "Checking your license key with Gumroad."
        case .verified(let tier):
            "This Mac is unlocked for Docky \(tier.title)."
        case .verificationFailed(let message):
            message
        }
    }
}

private struct GumroadPurchase {
    let productID: String
    let refunded: Bool?
    let disputed: Bool?
    let chargebacked: Bool?
    let subscriptionEndedAt: String?
    let subscriptionCancelledAt: String?
    let subscriptionFailedAt: String?
}

private struct GumroadLicenseVerification {
    let purchase: GumroadPurchase
    let uses: Int?
}

private enum LicenseVerificationError: LocalizedError {
    case invalid(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .transport(let message):
            message
        }
    }
}

final class ProductService: ObservableObject {
    nonisolated static let gumroadProductID = "bigF0QL8D0STXWDEWKlNIg=="
    nonisolated static let maximumActivationCount = 3
    nonisolated static let maximumFreeFolderCount = 3
    private nonisolated static let gumroadVerifyURL = URL(string: "https://api.gumroad.com/v2/licenses/verify")!
    static let shared = ProductService()

    @Published private(set) var currentTier: ProductTier {
        didSet {
            guard currentTier != oldValue else { return }
            defaults.set(currentTier.rawValue, forKey: Keys.currentTier)
        }
    }

    @Published private(set) var registrationStatus: ProductRegistrationStatus = .unregistered
    @Published private(set) var hasStoredLicenseKey = false

    private let defaults: UserDefaults
    private var verificationTask: Task<Void, Never>?

    var isVerifyingRegistration: Bool {
        if case .verifying = registrationStatus {
            return true
        }

        return false
    }

    private enum Keys {
        static let currentTier = "docky.product.currentTier"
        static let keychainService = "gt.quintero.Docky.product"
        static let keychainAccount = "gumroad-license-key"
        static let legacyRegisteredEmail = "docky.product.registeredEmail"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.currentTier = defaults.string(forKey: Keys.currentTier)
            .flatMap(ProductTier.init(rawValue:)) ?? .free
        self.hasStoredLicenseKey = Self.readLicenseKey() != nil
        defaults.removeObject(forKey: Keys.legacyRegisteredEmail)
        refreshRegistrationStatus()

        guard hasStoredLicenseKey else {
            return
        }

        verificationTask = Task { [weak self] in
            await self?.revalidateStoredRegistration()
        }
    }

    func availability(
        for feature: ProductFeature,
        context: ProductFeatureContext = .standard
    ) -> ProductAvailability {
        if currentTier == .pro || feature.requiredTier == .free {
            return .available
        }

        if context == .existingPlacement, feature.supportsLockedExistingPlacement {
            return .lockedExisting
        }

        return .unavailableForNewPlacement
    }

    func isUnlocked(_ feature: ProductFeature) -> Bool {
        availability(for: feature).isUnlocked
    }

    func registerProduct(licenseKey: String) {
        let trimmedLicenseKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLicenseKey.isEmpty else {
            registrationStatus = .verificationFailed("Enter a license key to continue.")
            return
        }

        verificationTask?.cancel()
        registrationStatus = .verifying

        let shouldCountActivation = Self.readLicenseKey() != trimmedLicenseKey

        verificationTask = Task { [weak self] in
            await self?.verifyManualRegistration(
                licenseKey: trimmedLicenseKey,
                shouldCountActivation: shouldCountActivation
            )
        }
    }

    func clearRegistration() {
        verificationTask?.cancel()
        currentTier = .free
        Self.deleteLicenseKey()
        hasStoredLicenseKey = false
        defaults.removeObject(forKey: Keys.legacyRegisteredEmail)
        refreshRegistrationStatus()
    }

    func applyVerifiedTier(_ tier: ProductTier) {
        currentTier = tier
        refreshRegistrationStatus()
    }

    #if DEBUG
    func setDebugTier(_ tier: ProductTier) {
        verificationTask?.cancel()
        currentTier = tier
        refreshRegistrationStatus()
    }
    #endif

    private func refreshRegistrationStatus() {
        if currentTier == .pro {
            registrationStatus = .verified(.pro)
            return
        }

        if hasStoredLicenseKey {
            registrationStatus = .stored
            return
        }

        registrationStatus = .unregistered
    }

    private func verifyManualRegistration(
        licenseKey: String,
        shouldCountActivation: Bool
    ) async {
        do {
            let verification = try await Self.verifyLicense(
                licenseKey: licenseKey,
                incrementUsesCount: shouldCountActivation
            )
            try validateVerification(
                verification,
                enforceActivationLimit: shouldCountActivation
            )

            guard Self.writeLicenseKey(licenseKey) else {
                registrationStatus = .verificationFailed("The license is valid, but Docky couldn't store it in Keychain.")
                return
            }

            hasStoredLicenseKey = true
            currentTier = .pro
            refreshRegistrationStatus()
        } catch let error as LicenseVerificationError {
            registrationStatus = .verificationFailed(error.localizedDescription)
        } catch {
            registrationStatus = .verificationFailed("Couldn't verify the license right now.")
        }
    }

    private func revalidateStoredRegistration() async {
        guard let storedLicenseKey = Self.readLicenseKey() else {
            hasStoredLicenseKey = false
            currentTier = .free
            refreshRegistrationStatus()
            return
        }

        let preservedTier = currentTier
        if preservedTier != .pro {
            registrationStatus = .verifying
        }

        do {
            let verification = try await Self.verifyLicense(
                licenseKey: storedLicenseKey,
                incrementUsesCount: false
            )
            try validateVerification(verification, enforceActivationLimit: false)

            hasStoredLicenseKey = true
            currentTier = .pro
            refreshRegistrationStatus()
        } catch let error as LicenseVerificationError {
            switch error {
            case .invalid:
                currentTier = .free
                registrationStatus = .verificationFailed(error.localizedDescription)
            case .transport:
                if preservedTier == .pro {
                    currentTier = preservedTier
                    refreshRegistrationStatus()
                } else {
                    registrationStatus = .verificationFailed(error.localizedDescription)
                }
            }
        } catch {
            if preservedTier == .pro {
                currentTier = preservedTier
                refreshRegistrationStatus()
            } else {
                registrationStatus = .verificationFailed("Couldn't verify the saved license right now.")
            }
        }
    }

    private func validateVerification(
        _ verification: GumroadLicenseVerification,
        enforceActivationLimit: Bool
    ) throws {
        let purchase = verification.purchase

        guard purchase.productID == Self.gumroadProductID else {
            throw LicenseVerificationError.invalid("That license belongs to a different Gumroad product.")
        }

        if purchase.refunded == true || purchase.disputed == true || purchase.chargebacked == true {
            throw LicenseVerificationError.invalid("This Gumroad purchase is no longer active.")
        }

        if purchase.subscriptionEndedAt != nil || purchase.subscriptionCancelledAt != nil || purchase.subscriptionFailedAt != nil {
            throw LicenseVerificationError.invalid("This Gumroad subscription is no longer active.")
        }

        if enforceActivationLimit,
           let uses = verification.uses,
           uses > Self.maximumActivationCount {
            throw LicenseVerificationError.invalid("This license key has already been activated on \(Self.maximumActivationCount) Macs.")
        }
    }

    private nonisolated static func verifyLicense(
        licenseKey: String,
        incrementUsesCount: Bool
    ) async throws -> GumroadLicenseVerification {
        var request = URLRequest(url: gumroadVerifyURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let bodyItems = [
            URLQueryItem(name: "product_id", value: gumroadProductID),
            URLQueryItem(name: "license_key", value: licenseKey),
            URLQueryItem(name: "increment_uses_count", value: incrementUsesCount ? "true" : "false")
        ]
        request.httpBody = formEncodedData(from: bodyItems)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseVerificationError.transport("Couldn't reach Gumroad to verify the license.")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseVerificationError.transport("Gumroad returned an invalid response.")
        }

        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let success = payload?["success"] as? Bool
        let uses = payload?["uses"] as? Int
        let purchase = (payload?["purchase"] as? [String: Any]).flatMap(parsePurchase(from:))

        if httpResponse.statusCode == 200,
           success == true,
           let purchase {
            return GumroadLicenseVerification(purchase: purchase, uses: uses)
        }

        let message = (payload?["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if httpResponse.statusCode == 404 || success == false {
            throw LicenseVerificationError.invalid(message ?? "That license key isn't valid for Docky Pro.")
        }

        throw LicenseVerificationError.transport(message ?? "Couldn't verify the license right now.")
    }

    private nonisolated static func parsePurchase(from payload: [String: Any]) -> GumroadPurchase? {
        guard let productID = payload["product_id"] as? String else {
            return nil
        }

        return GumroadPurchase(
            productID: productID,
            refunded: payload["refunded"] as? Bool,
            disputed: payload["disputed"] as? Bool,
            chargebacked: payload["chargebacked"] as? Bool,
            subscriptionEndedAt: payload["subscription_ended_at"] as? String,
            subscriptionCancelledAt: payload["subscription_cancelled_at"] as? String,
            subscriptionFailedAt: payload["subscription_failed_at"] as? String
        )
    }

    private nonisolated static func formEncodedData(from items: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    @discardableResult
    private static func writeLicenseKey(_ licenseKey: String) -> Bool {
        guard let data = licenseKey.data(using: .utf8) else {
            return false
        }

        let query = keychainQuery()
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func readLicenseKey() -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func deleteLicenseKey() {
        SecItemDelete(keychainQuery() as CFDictionary)
    }

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.keychainAccount
        ]
    }
}
