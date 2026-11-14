// Hints - control unit names, a coarse kind per unit, and our own notes for codes people have looked into
// (not BMW's texts), in Polish and English. The notes live in data/known_codes.json (add one by pull request);
// tools/embed-codes.sh turns it into KnownCodes.swift. Codes without a note go to the owner's AI.
import Foundation

public struct Hint: Sendable, Hashable {
    public enum Severity: String, Codable, Sendable { case workshop, watch, info }
    public let severity: Severity, title: L, what: L, check: L
    public let sources: [String]
    /// high / medium / low: how well the sources tie the code to this meaning
    public var confidence: String = "high"
}

struct CodeEntry: Decodable {
    struct T: Decodable { let title: String, what: String, check: String }
    let address: String, code: String, severity: Hint.Severity, pl: T, en: T
    let sources: [String]?
    let confidence: String?
}

public enum Hints {
    // names by diagnostic address: cauliflowermossgrape/idrive7-apps kit/runtime/ecus.js (MIT)
    static let units: [UInt8: (String, String)] = [
        0x01: ("ACSM airbag", "safety"), 0x06: ("ICAM cameras", "assist"), 0x07: ("SME HV battery", "drive"),
        0x08: ("SRR corner radar", "assist"), 0x0D: ("HKFM tailgate", "body"), 0x10: ("BDC gateway", "body"),
        0x12: ("DME engine", "engine"), 0x13: ("DME 2", "engine"), 0x14: ("OBC charger", "drive"),
        0x18: ("EGS gearbox", "drive"), 0x1D: ("TFM fuel tank", "engine"), 0x20: ("SRR corner radar", "assist"),
        0x21: ("FRR front radar", "assist"), 0x23: ("SAS assist sensors", "assist"), 0x28: ("SRR corner radar", "assist"),
        0x29: ("DSC brakes", "chassis"), 0x2A: ("SRR corner radar", "assist"), 0x2C: ("USS park sensors", "assist"),
        0x30: ("EPS steering", "chassis"), 0x37: ("RAM audio", "infotainment"), 0x38: ("VTG xDrive", "drive"),
        0x39: ("DSC brake booster", "chassis"), 0x3A: ("EME e-motor", "drive"), 0x40: ("BDC body", "body"),
        0x43: ("FLM headlight", "lights"), 0x44: ("FLM headlight", "lights"), 0x45: ("DCS driver camera", "assist"),
        0x56: ("FZD roof", "body"), 0x5D: ("KAFAS camera", "assist"), 0x5E: ("GWS gear selector", "drive"),
        0x60: ("KOMBI cluster", "infotainment"), 0x61: ("ATM telematics", "infotainment"), 0x63: ("Head unit", "infotainment"),
        0x64: ("PDC parking", "assist"), 0x67: ("ZBE controller", "infotainment"), 0x6D: ("SM seat module", "body"),
        0x76: ("VDP dampers", "chassis"), 0x78: ("IHKA climate", "body"),
    ]

    public static func unitName(_ a: UInt8) -> String { units[a]?.0 ?? String(format: "ECU 0x%02X", a) }
    /// engine, drive, chassis, safety, assist, body, lights, infotainment, other
    public static func kind(_ a: UInt8) -> String { units[a]?.1 ?? "other" }

    static let notes: [String: Hint] = {
        struct File: Decodable { let entries: [CodeEntry] }
        let list = (try? JSONDecoder().decode(File.self, from: Data(KnownCodes.json.utf8)))?.entries ?? []
        return Dictionary(list.map { e in
            (e.address.uppercased() + ":" + e.code.uppercased(),
             Hint(severity: e.severity, title: L(e.pl.title, e.en.title), what: L(e.pl.what, e.en.what),
                  check: L(e.pl.check, e.en.check), sources: e.sources ?? [], confidence: e.confidence ?? "high"))
        }, uniquingKeysWith: { a, _ in a })
    }()

    public static func hint(address: UInt8, code: String) -> Hint? { notes[String(format: "%02X:", address) + code] }
}
