// Lang - the app speaks Polish and English: the system language when it is Polish, else English;
// the owner can pick one in Settings (UserDefaults "lang").
import Foundation

public enum Lang: String, CaseIterable, Sendable { case pl, en
    public static var current: Lang {
        if let s = UserDefaults.standard.string(forKey: "lang"), let l = Lang(rawValue: s) { return l }
        return Locale.preferredLanguages.first?.hasPrefix("pl") == true ? .pl : .en
    }
}

/// A text in both languages.
public struct L: Codable, Hashable, Sendable {
    public let pl: String, en: String
    public init(_ pl: String, _ en: String) { self.pl = pl; self.en = en }
    public var text: String { Lang.current == .pl ? pl : en }
}
