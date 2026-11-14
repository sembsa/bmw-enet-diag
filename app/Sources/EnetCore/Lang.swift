// Lang - Polish and English. The app bundle declares both (CFBundleLocalizations, en.lproj / pl.lproj), so macOS
// picks one, per app in System Settings › Language & Region; without a bundle (MCP, tests) the system language.
import Foundation

public enum Lang: String, CaseIterable, Sendable { case pl, en
    public static var current: Lang {
        let langs = Bundle.main.localizations.count > 1 ? Bundle.main.preferredLocalizations : Locale.preferredLanguages
        return langs.first?.hasPrefix("pl") == true ? .pl : .en
    }
}

/// A text in both languages.
public struct L: Codable, Hashable, Sendable {
    public let pl: String, en: String
    public init(_ pl: String, _ en: String) { self.pl = pl; self.en = en }
    public var text: String { Lang.current == .pl ? pl : en }
}
