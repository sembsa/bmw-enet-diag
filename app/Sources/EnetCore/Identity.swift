// Identity - who the car is, from public standards only: the VIN (ISO 3779/3780: maker, model year, plant, type
// code), the engine unit's OBD identification (SAE J1979 service 09: ECU name, calibration ids, CVN) and its OBD
// standard (01 1C). The model behind the BMW type code is not decoded here (no public table); the owner's AI can.
import Foundation

public struct Identity: Codable, Sendable, Hashable {
    public var vin: String?
    public var maker: String?
    public var modelYear: Int?
    public var typeCode: String?          // VIN positions 4–7 (BMW's type key)
    public var plantCode: String?         // VIN position 11
    public var serial: String?            // VIN positions 12–17
    public var ecuName: String?
    public var calibrationIds: [String] = []
    public var cvns: [String] = []
    public var obdStandard: String?
    public var odometerKm: Double?
}

public enum VIN {
    /// World manufacturer identifiers of the BMW group (positions 1–3).
    static let makers: [String: String] = [
        "WBA": "BMW AG", "WBS": "BMW M GmbH", "WBY": "BMW i", "WBX": "BMW (SUV)", "WMW": "MINI",
        "5UX": "BMW (USA, Spartanburg)", "5YM": "BMW M (USA)", "4US": "BMW (USA)", "LBV": "BMW Brilliance (Chiny)",
        "X4X": "BMW (Rosja)", "WB1": "BMW Motorrad", "WB3": "BMW Motorrad",
    ]

    /// Position 10: 1980–2009 / 2010–2039 letters and digits (I, O, Q, U, Z, 0 unused). The latest year not after next year.
    public static func modelYear(_ c: Character, now: Int = Calendar.current.component(.year, from: Date())) -> Int? {
        let codes = Array("ABCDEFGHJKLMNPRSTVWXY123456789")
        guard let i = codes.firstIndex(of: c) else { return nil }
        var y = 1980 + i
        while y + 30 <= now + 1 { y += 30 }
        return y
    }

    public static func decode(_ vin: String, into id: inout Identity) {
        let v = Array(vin.uppercased())
        guard v.count == 17 else { return }
        id.vin = String(v)
        id.maker = makers[String(v[0..<3])] ?? String(v[0..<3])
        id.typeCode = String(v[3..<7])
        id.modelYear = modelYear(v[9])
        id.plantCode = String(v[10])
        id.serial = String(v[11...])
    }
}

/// SAE J1979 PID 1C: the OBD requirements the engine unit was certified to.
func obdStandardName(_ code: UInt8) -> String {
    switch code {
    case 1: "OBD-II (CARB)"
    case 2: "OBD (EPA)"
    case 3: "OBD + OBD-II"
    case 6: "EOBD (Europa)"
    case 7: "EOBD + OBD-II"
    case 9: "EOBD + OBD + OBD-II"
    case 0x0D: "JOBD + EOBD"
    case 0x11: "Engine Manufacturer Diagnostics"
    case 0x13: "HD OBD"
    case 0x1E, 0x1F, 0x20, 0x21: "EURO VI / OBD"
    default: String(format: "kod 0x%02X", code)
    }
}

/// ASCII text from a service 09 reply, without padding.
func text(_ b: ArraySlice<UInt8>) -> String {
    String(decoding: b.filter { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
}
