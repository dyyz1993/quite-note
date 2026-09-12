import Foundation

/// Resolves the app UI language from macOS's preferred-language list.
/// Storefront territory is deliberately not consulted: a traveller or an
/// expatriate should see the language configured on their Mac, not the
/// language associated with their Apple Account region.
enum AppLocalization {
    static let fallbackLanguage = "en"

    static func resolvedLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        for identifier in preferredLanguages {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized == "zh" || normalized.hasPrefix("zh-hans") || normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg") {
                return "zh-Hans"
            }
            if normalized == "en" || normalized.hasPrefix("en-") {
                return "en"
            }
        }
        return fallbackLanguage
    }

    static func bundle(preferredLanguages: [String] = Locale.preferredLanguages) -> Bundle {
        let language = resolvedLanguage(preferredLanguages: preferredLanguages)
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return Bundle.main
        }
        return localizedBundle
    }

    static func text(_ key: String, fallback: String) -> String {
        bundle().localizedString(forKey: key, value: fallback, table: "Localizable")
    }
}

/// Lightweight call-site helper for user-facing UI copy.
func L(_ key: String, fallback: String) -> String {
    AppLocalization.text(key, fallback: fallback)
}
