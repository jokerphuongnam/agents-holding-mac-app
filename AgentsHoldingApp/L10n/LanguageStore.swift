import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case vietnamese

    var id: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .system: return "language_system"
        case .english: return "language_english"
        case .vietnamese: return "language_vietnamese"
        }
    }

    /// Bundle language code used for Localizable.strings (`nil` = follow system).
    var bundleCode: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .vietnamese: return "vi"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .english: return Locale(identifier: "en")
        case .vietnamese: return Locale(identifier: "vi")
        }
    }
}

@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    static let defaultsKey = "appLanguage"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            revision += 1
        }
    }

    @Published private(set) var revision: Int = 0

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
    }

    var locale: Locale { language.locale }
}

enum L10n {
    /// Thread-safe: reads language from UserDefaults + lproj bundle.
    static func tr(_ key: String) -> String {
        let bundle = localizationBundle()
        return NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let lang = currentLanguage()
        return String(format: tr(key), locale: lang.locale, arguments: args)
    }

    private static func currentLanguage() -> AppLanguage {
        let raw = UserDefaults.standard.string(forKey: LanguageStore.defaultsKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: raw) ?? .system
    }

    private static func localizationBundle() -> Bundle {
        guard let code = currentLanguage().bundleCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return .main
        }
        return bundle
    }
}
