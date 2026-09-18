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

    var displayName: String {
        L10nLookup(displayNameKey, "Localizable", displayNameKey)
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

/// SwiftGen `lookupFunction` — picks en/vi bundle from Settings (or system).
func L10nLookup(_ key: String, _ table: String, _ value: String) -> String {
    let raw = UserDefaults.standard.string(forKey: LanguageStore.defaultsKey) ?? AppLanguage.system.rawValue
    let language = AppLanguage(rawValue: raw) ?? .system
    let bundle: Bundle
    if let code = language.bundleCode,
       let path = Bundle.main.path(forResource: code, ofType: "lproj"),
       let b = Bundle(path: path) {
        bundle = b
    } else {
        bundle = .main
    }
    let format = NSLocalizedString(key, tableName: table, bundle: bundle, value: value, comment: "")
    return format
}
