import Foundation

enum L10n {
    enum Language: String, CaseIterable {
        case system
        case english = "en"
        case simplifiedChinese = "zh-Hans"
    }

    static let languagePreferenceKey = "batchprinter.language"

    static var selectedLanguage: Language {
        guard let raw = UserDefaults.standard.string(forKey: languagePreferenceKey),
              let language = Language(rawValue: raw) else {
            return .system
        }
        return language
    }

    static var locale: Locale {
        switch selectedLanguage {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: Language.english.rawValue)
        case .simplifiedChinese:
            return Locale(identifier: Language.simplifiedChinese.rawValue)
        }
    }

    static func locale(for rawValue: String) -> Locale {
        guard let language = Language(rawValue: rawValue) else {
            return .autoupdatingCurrent
        }
        switch language {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: Language.english.rawValue)
        case .simplifiedChinese:
            return Locale(identifier: Language.simplifiedChinese.rawValue)
        }
    }

    static func tr(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .main, locale: locale)
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: locale, arguments: args)
    }
}
