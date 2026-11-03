import Foundation

/// The UI languages. `zh` is Simplified Chinese.
enum Lang: String, CaseIterable {
    case en, ko, ja, zh

    /// The localization name macOS uses (`CFBundleLocalizations` in scripts/bundle.sh).
    var localization: String { self == .zh ? "zh-Hans" : rawValue }
    var locale: Locale { Locale(identifier: ["en": "en_US", "ko": "ko_KR", "ja": "ja_JP", "zh": "zh_CN"][rawValue]!) }
}

/// Every UI string is one `L.t(en, ko, ja, zh)` call, computed when it is drawn, so a language change
/// shows at once without a restart. A missing language is a compile error; Tests/TokenPetTests/L10nTests
/// checks that each translation is there and in the right script.
enum L {
    static var lang = resolve(Prefs.store.string(forKey: "language") ?? "auto")
    /// Development only (`--lang pseudo`): every string about 40% longer and accented, to find truncation.
    static var pseudo = false

    /// The language setting ("auto", "en", "ko", "ja", "zh") -> a language. "auto" asks macOS to match the
    /// preferred languages (all of them, in order; Traditional Chinese is not given Simplified), else English.
    static func resolve(_ pref: String, system: [String] = Locale.preferredLanguages) -> Lang {
        if let l = Lang(rawValue: pref) { return l }
        let match = Bundle.preferredLocalizations(from: Lang.allCases.map(\.localization), forPreferences: system).first
        return Lang.allCases.first { $0.localization == match } ?? .en
    }

    static func t(_ en: String, _ ko: String, _ ja: String, _ zh: String) -> String {
        if pseudo { return stretch(en) }
        switch lang {
        case .en: return en
        case .ko: return ko
        case .ja: return ja
        case .zh: return zh
        }
    }

    /// "Settings" -> "[Šéttîñgš ~~~~]": accented, about 40% longer, bracketed so a cut-off end shows.
    static func stretch(_ s: String) -> String {
        let accents: [Character: Character] = ["a": "á", "e": "é", "i": "î", "o": "ö", "u": "ü", "n": "ñ", "s": "š", "c": "ç",
                                               "A": "Å", "E": "É", "I": "Î", "O": "Ö", "U": "Ü", "S": "Š", "C": "Ç"]
        return "[" + String(s.map { accents[$0] ?? $0 }) + " " + String(repeating: "~", count: max(2, s.count * 2 / 5)) + "]"
    }
}
