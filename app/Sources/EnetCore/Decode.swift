// Decode - public standards only: SAE J1979 PIDs (OBD-II current data), SAE J2012 P-codes, UDS 19 02 records.
import Foundation

public struct Pid: Sendable {
    public let key: String, pid: UInt8, bytes: Int, unit: String, label: String
    let decode: @Sendable ([UInt8]) -> Double
}

private func u8(_ d: [UInt8]) -> Double { Double(d[0]) }
private func u16(_ d: [UInt8]) -> Double { Double(Int(d[0]) * 256 + Int(d[1])) }

public enum Pids {
    public static let all: [Pid] = [
        Pid(key: "rpm", pid: 0x0C, bytes: 2, unit: "rpm", label: "Obroty") { u16($0) / 4 },
        Pid(key: "speed", pid: 0x0D, bytes: 1, unit: "km/h", label: "Prędkość") { u8($0) },
        Pid(key: "coolant", pid: 0x05, bytes: 1, unit: "°C", label: "Płyn chłodniczy") { u8($0) - 40 },
        Pid(key: "oil", pid: 0x5C, bytes: 1, unit: "°C", label: "Olej") { u8($0) - 40 },
        Pid(key: "iat", pid: 0x0F, bytes: 1, unit: "°C", label: "Powietrze dolotowe") { u8($0) - 40 },
        Pid(key: "ambient", pid: 0x46, bytes: 1, unit: "°C", label: "Na zewnątrz") { u8($0) - 40 },
        Pid(key: "stft", pid: 0x06, bytes: 1, unit: "%", label: "Korekta krótka (STFT)") { (u8($0) - 128) * 100 / 128 },
        Pid(key: "ltft", pid: 0x07, bytes: 1, unit: "%", label: "Korekta długa (LTFT)") { (u8($0) - 128) * 100 / 128 },
        Pid(key: "map", pid: 0x0B, bytes: 1, unit: "kPa", label: "Ciśnienie w kolektorze") { u8($0) },
        Pid(key: "baro", pid: 0x33, bytes: 1, unit: "kPa", label: "Ciśnienie otoczenia") { u8($0) },
        Pid(key: "maf", pid: 0x10, bytes: 2, unit: "g/s", label: "Przepływomierz (MAF)") { u16($0) / 100 },
        Pid(key: "load", pid: 0x04, bytes: 1, unit: "%", label: "Obciążenie") { u8($0) * 100 / 255 },
        Pid(key: "throttle", pid: 0x11, bytes: 1, unit: "%", label: "Przepustnica") { u8($0) * 100 / 255 },
        Pid(key: "pedal", pid: 0x49, bytes: 1, unit: "%", label: "Pedał gazu") { u8($0) * 100 / 255 },
        Pid(key: "timing", pid: 0x0E, bytes: 1, unit: "°", label: "Kąt zapłonu") { u8($0) / 2 - 64 },
        Pid(key: "lambda", pid: 0x34, bytes: 4, unit: "", label: "Lambda") { u16($0) * 2 / 65536 },
        Pid(key: "lambda_cmd", pid: 0x44, bytes: 2, unit: "", label: "Lambda zadana") { u16($0) * 2 / 65536 },
        Pid(key: "voltage", pid: 0x42, bytes: 2, unit: "V", label: "Napięcie") { u16($0) / 1000 },
    ]
    public static let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
}

/// Two DTC bytes -> "P0171"
public func pcode(_ a: UInt8, _ b: UInt8) -> String {
    let letter = Array("PCBU")[Int(a >> 6)]
    let rest = String(format: "%X%X%02X", Int((a >> 4) & 3), Int(a & 0xF), Int(b))
    return String(letter) + rest
}

/// 59 02 <mask> (<code 3 bytes> <status>)* -> [(code, status)]
func parseDtcs(_ r: [UInt8]?) -> [(String, UInt8)] {
    guard let r, r.count >= 3, r[0] == 0x59, r[1] == 0x02 else { return [] }
    var out: [(String, UInt8)] = []
    var i = 3
    while i + 3 < r.count {
        let code = r[i..<i + 3].map { String(format: "%02X", $0) }.joined()
        out.append((code, r[i + 3]))
        i += 4
    }
    return out
}

/// OBD 03 / 07 response -> P-codes (CAN: a count byte after the service id)
func parseObdCodes(_ r: [UInt8]?, sid: UInt8) -> [String] {
    guard let r, r.first == sid + 0x40 else { return [] }
    let d = Array(r.count % 2 == 0 ? r.dropFirst(2) : r.dropFirst(1))
    return stride(from: 0, to: d.count - 1, by: 2).compactMap { i in d[i] == 0 && d[i + 1] == 0 ? nil : pcode(d[i], d[i + 1]) }
}
