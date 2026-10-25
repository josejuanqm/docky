//
//  AppFolderNamingService.swift
//  Docky
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
private struct AppFolderNameSuggestion {
    @Guide(description: "A concise app folder title using 1 to 3 words.")
    var title: String
}
#endif

/// Deterministic folder seed name. Available on every macOS Docky supports
/// — `AppFolderNamingService` (which wraps the FoundationModels-powered
/// suggester) is macOS 26+ only, but the seed is needed even on older
/// systems when a folder is first created.
func appFolderSeedName(for apps: [AppTile]) -> String {
    let names = apps.map(\.displayName).map(_appFolderNormalizeName(_:)).filter { !$0.isEmpty }
    guard let firstName = names.first else {
        return String(localized: "Folder")
    }

    if names.count == 1 {
        return firstName
    }

    if names.count == 2 {
        return _appFolderSanitize("\(firstName) + \(names[1])", fallback: "Folder")
    }

    return _appFolderSanitize("\(firstName) + \(names.count - 1)", fallback: "Folder")
}

private func _appFolderNormalizeName(_ value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private func _appFolderSanitize(_ value: String, fallback: String) -> String {
    let collapsed = value
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'`“”‘’.:,;!?-"))
    let normalized = _appFolderNormalizeName(collapsed)
    guard !normalized.isEmpty else {
        return fallback
    }

    let limited = String(normalized.prefix(28)).trimmingCharacters(in: .whitespacesAndNewlines)
    return limited.isEmpty ? fallback : limited
}

@available(macOS 26.0, *)
final class AppFolderNamingService {
    static let shared = AppFolderNamingService()

    private init() {}

    func seedName(for apps: [AppTile]) -> String {
        appFolderSeedName(for: apps)
    }

    func suggestInitialName(for apps: [AppTile]) async -> String? {
        let fallback = appFolderSeedName(for: apps)
        let appNames = apps.map(\.displayName).map(_appFolderNormalizeName(_:)).filter { !$0.isEmpty }
        guard appNames.count >= 2 else {
            return fallback
        }

#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            return fallback
        }

        let session = LanguageModelSession(
            model: model,
            instructions: "You name macOS app folders. Respond with a short, natural title only. Avoid quotes, punctuation, and filler words like folder or apps unless they are essential."
        )

        let prompt = "Suggest a concise name for a macOS app folder containing these apps: \(appNames.joined(separator: ", "))."

        do {
            let response = try await session.respond(to: prompt, generating: AppFolderNameSuggestion.self)
            return _appFolderSanitize(response.content.title, fallback: fallback)
        } catch {
            return fallback
        }
#else
        return fallback
#endif
    }
}
