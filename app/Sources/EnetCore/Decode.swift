// Decode - public standards only: SAE J1979 PIDs (OBD-II current data), SAE J2012 P-codes, UDS 19 02 records.
import Foundation

public struct Pid: Sendable {
    public enum Group: String, CaseIterable, Sendable { case engine, air, fuel, temps, status }
    public let key: String, pid: UInt8, bytes: Int, unit: String, label: String
    public var group: Group = .engine
    let decode: @Sendable ([UInt8]) -> Double

    init(key: String, pid: UInt8, bytes: Int, unit: String, label: String, _ group: Group = .engine, decode: @escaping @Sendable ([UInt8]) -> Double) {
        self.key = key; self.pid = pid; self.bytes = bytes; self.unit = unit; self.label = label; self.group = group; self.decode = decode
    }
}

private func u8(_ d: [UInt8]) -> Double { Double(d[0]) }
private func u16(_ d: [UInt8]) -> Double { Double(Int(d[0]) * 256 + Int(d[1])) }

public enum Pids {
    public static let all: [Pid] = [
        Pid(key: "rpm", pid: 0x0C, bytes: 2, unit: "rpm", label: "Obroty") { u16($0) / 4 },
        Pid(key: "speed", pid: 0x0D, bytes: 1, unit: "km/h", label: "Prędkość") { u8($0) },
        Pid(key: "load", pid: 0x04, bytes: 1, unit: "%", label: "Obciążenie") { u8($0) * 100 / 255 },
        Pid(key: "throttle", pid: 0x11, bytes: 1, unit: "%", label: "Przepustnica") { u8($0) * 100 / 255 },
        Pid(key: "pedal", pid: 0x49, bytes: 1, unit: "%", label: "Pedał gazu") { u8($0) * 100 / 255 },
        Pid(key: "timing", pid: 0x0E, bytes: 1, unit: "°", label: "Kąt zapłonu") { u8($0) / 2 - 64 },
        Pid(key: "map", pid: 0x0B, bytes: 1, unit: "kPa", label: "Ciśnienie w kolektorze", .air) { u8($0) },
        Pid(key: "baro", pid: 0x33, bytes: 1, unit: "kPa", label: "Ciśnienie otoczenia", .air) { u8($0) },
        Pid(key: "maf", pid: 0x10, bytes: 2, unit: "g/s", label: "Przepływomierz (MAF)", .air) { u16($0) / 100 },
        Pid(key: "iat", pid: 0x0F, bytes: 1, unit: "°C", label: "Powietrze dolotowe", .air) { u8($0) - 40 },
        Pid(key: "stft", pid: 0x06, bytes: 1, unit: "%", label: "Korekta krótka (STFT)", .fuel) { (u8($0) - 128) * 100 / 128 },
        Pid(key: "ltft", pid: 0x07, bytes: 1, unit: "%", label: "Korekta długa (LTFT)", .fuel) { (u8($0) - 128) * 100 / 128 },
        Pid(key: "lambda", pid: 0x34, bytes: 4, unit: "λ", label: "Lambda", .fuel) { u16($0) * 2 / 65536 },
        Pid(key: "lambda_cmd", pid: 0x44, bytes: 2, unit: "λ", label: "Lambda zadana", .fuel) { u16($0) * 2 / 65536 },
        Pid(key: "fuel_status", pid: 0x03, bytes: 2, unit: "", label: "Pętla regulacji (2 = zamknięta)", .fuel) { u8($0) },
        Pid(key: "rail", pid: 0x23, bytes: 2, unit: "bar", label: "Ciśnienie paliwa (szyna)", .fuel) { u16($0) / 10 },
        Pid(key: "fuel_rate", pid: 0x5E, bytes: 2, unit: "l/h", label: "Zużycie paliwa", .fuel) { u16($0) / 20 },
        Pid(key: "fuel_level", pid: 0x2F, bytes: 1, unit: "%", label: "Poziom paliwa", .fuel) { u8($0) * 100 / 255 },
        Pid(key: "coolant", pid: 0x05, bytes: 1, unit: "°C", label: "Płyn chłodniczy", .temps) { u8($0) - 40 },
        Pid(key: "oil", pid: 0x5C, bytes: 1, unit: "°C", label: "Olej", .temps) { u8($0) - 40 },
        Pid(key: "ambient", pid: 0x46, bytes: 1, unit: "°C", label: "Na zewnątrz", .temps) { u8($0) - 40 },
        Pid(key: "cat1", pid: 0x3C, bytes: 2, unit: "°C", label: "Katalizator (przed)", .temps) { u16($0) / 10 - 40 },
        Pid(key: "cat2", pid: 0x3E, bytes: 2, unit: "°C", label: "Katalizator (za)", .temps) { u16($0) / 10 - 40 },
        Pid(key: "voltage", pid: 0x42, bytes: 2, unit: "V", label: "Napięcie", .status) { u16($0) / 1000 },
        Pid(key: "mil", pid: 0x01, bytes: 1, unit: "", label: "Kontrolka silnika (1 = świeci)", .status) { Double(Int($0[0]) >> 7) },
        Pid(key: "runtime", pid: 0x1F, bytes: 2, unit: "s", label: "Czas od uruchomienia", .status) { u16($0) },
        Pid(key: "dist_mil", pid: 0x21, bytes: 2, unit: "km", label: "Dystans z kontrolką", .status) { u16($0) },
        Pid(key: "dist_clear", pid: 0x31, bytes: 2, unit: "km", label: "Dystans od skasowania błędów", .status) { u16($0) },
        Pid(key: "warmups", pid: 0x30, bytes: 1, unit: "", label: "Rozgrzania od skasowania błędów", .status) { u8($0) },
        Pid(key: "odometer", pid: 0xA6, bytes: 4, unit: "km", label: "Przebieg", .status) { Double(UInt32($0[0]) << 24 | UInt32($0[1]) << 16 | UInt32($0[2]) << 8 | UInt32($0[3])) / 10 },
    ]
    /// English labels by key (Polish ones live in Pid.label).
    public static let english: [String: String] = [
        "rpm": "Engine speed", "speed": "Vehicle speed", "load": "Engine load", "throttle": "Throttle", "pedal": "Accelerator pedal",
        "timing": "Ignition timing", "map": "Manifold pressure", "baro": "Ambient pressure", "maf": "Air mass meter (MAF)",
        "iat": "Intake air", "stft": "Short-term fuel trim", "ltft": "Long-term fuel trim", "lambda": "Lambda", "lambda_cmd": "Lambda target",
        "fuel_status": "Fuel loop (2 = closed)", "rail": "Fuel rail pressure", "fuel_rate": "Fuel consumption",
        "fuel_level": "Fuel level", "coolant": "Coolant", "oil": "Oil", "ambient": "Outside", "cat1": "Catalyst (upstream)",
        "cat2": "Catalyst (downstream)", "voltage": "Voltage", "mil": "Check engine lamp (1 = on)", "runtime": "Time since start",
        "dist_mil": "Distance with the lamp on", "dist_clear": "Distance since faults were cleared",
        "warmups": "Warm-ups since faults were cleared", "odometer": "Odometer",
    ]
    public static func label(_ p: Pid) -> String { Lang.current == .pl ? p.label : english[p.key] ?? p.key }

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

/// Mode 06 misfire monitor (MIDs A2.. = cylinder 1..): 46 MID (TID UASID value min max)*; TID 0B = average of the
/// last 10 driving cycles, 0C = this driving cycle.
func parseMisfire(_ r: [UInt8]?, mid: UInt8) -> (current: Double?, average: Double?) {
    guard let r, r.count >= 2, r[0] == 0x46, r[1] == mid else { return (nil, nil) }
    var cur: Double?, avg: Double?
    var i = 2
    while i + 8 < r.count + 1 && i + 7 < r.count {
        let tid = r[i], v = Double(Int(r[i + 2]) << 8 | Int(r[i + 3]))
        if tid == 0x0B { avg = v }
        if tid == 0x0C { cur = v }
        i += 8
    }
    return (cur, avg)
}
