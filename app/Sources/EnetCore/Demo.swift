// Demo - a simulated car for trying the app without one: a few faults, and an engine whose values move
// (idle and 2500 rpm in turns, warm, with the fuel trims of an intake leak). It answers through the same
// Transport seam, so the app and the allowlist behave exactly as with a car.
import Foundation

enum DemoScenario {
    /// Engine values at `t` seconds since the demo started.
    static func sample(_ t: Double) -> Sample {
        let mid: Bool = t.truncatingRemainder(dividingBy: 45) >= 30     // 30 s idle, 15 s at ~2500 rpm
        func n(_ a: Double) -> Double { sin(t * a) }                    // smooth "noise"
        var s: Sample = [:]
        s["rpm"] = mid ? 2550 + 60 * n(1.7) : 780 + 15 * n(2.3)
        s["speed"] = 0
        s["coolant"] = min(91, 74 + t / 6)
        s["oil"] = min(95, 70 + t / 5)
        s["iat"] = 24 + 2 * n(0.05)
        s["ambient"] = 12
        s["stft"] = (mid ? 1.5 : 4.5) + 2 * n(3.1)
        s["ltft"] = mid ? 1.6 : 9.4
        s["map"] = mid ? 48 + 2 * n(1.1) : 32 + n(1.9)
        s["baro"] = 100
        s["maf"] = mid ? 12.8 + 0.5 * n(1.3) : 3.1 + 0.1 * n(2.1)
        s["load"] = mid ? 34 : 21
        s["throttle"] = mid ? 14 : 3
        s["pedal"] = mid ? 16 : 0
        s["timing"] = mid ? 22 : 8
        s["lambda"] = 1 + 0.01 * n(4.2)
        s["lambda_cmd"] = 1
        s["voltage"] = 14.1 + 0.05 * n(0.7)
        s["fuel_status"] = 2
        s["rail"] = mid ? 120 + 5 * n(0.9) : 52 + n(1.4)
        s["fuel_rate"] = mid ? 3.2 : 0.7
        s["fuel_level"] = 63
        s["cat1"] = min(640, 420 + t * 2)
        s["cat2"] = min(520, 300 + t * 1.5)
        s["mil"] = 0
        s["runtime"] = 600 + t
        s["dist_mil"] = 0
        s["dist_clear"] = 1840
        s["warmups"] = 37
        s["odometer"] = 48213
        return s
    }

    /// A ready-made log for the engine check: about 4 minutes.
    static func log() -> [Sample] {
        stride(from: 0.0, to: 240, by: 0.5).map { var s = sample($0); s["t"] = $0; return s }
    }

    static func encode(_ key: String, _ v: Double) -> [UInt8] {
        func u16(_ x: Double) -> [UInt8] { let i = UInt16(max(0, min(65535, x.rounded()))); return [UInt8(i >> 8), UInt8(i & 0xFF)] }
        func u8(_ x: Double) -> [UInt8] { [UInt8(max(0, min(255, x.rounded())))] }
        switch key {
        case "rpm": return u16(v * 4)
        case "rail", "cat1", "cat2": return key == "rail" ? u16(v * 10) : u16((v + 40) * 10)
        case "fuel_rate": return u16(v * 20)
        case "runtime", "dist_mil", "dist_clear": return u16(v)
        case "fuel_level": return u8(v * 255 / 100)
        case "fuel_status": return u8(v) + [0]
        case "mil": return u8(v * 128)
        case "odometer": let i = UInt32(v * 10); return [UInt8(i >> 24), UInt8(i >> 16 & 0xFF), UInt8(i >> 8 & 0xFF), UInt8(i & 0xFF)]
        case "maf": return u16(v * 100)
        case "voltage": return u16(v * 1000)
        case "lambda": return u16(v * 32768) + [0x80, 0x00]
        case "lambda_cmd": return u16(v * 32768)
        case "coolant", "oil", "iat", "ambient": return u8(v + 40)
        case "stft", "ltft": return u8(v * 128 / 100 + 128)
        case "load", "throttle", "pedal": return u8(v * 255 / 100)
        case "timing": return u8((v + 64) * 2)
        default: return u8(v)                                       // speed, map, baro
        }
    }

    static let faults: [UInt8: [UInt8]] = [
        0x12: [0x59, 0x02, 0xFF, 0x10, 0x1F, 0x01, 0x09, 0x12, 0x03, 0x08, 0x08],
        0x29: [0x59, 0x02, 0xFF, 0x48, 0x06, 0x31, 0x08],
        0x37: [0x59, 0x02, 0xFF, 0xB7, 0xF5, 0x00, 0x09],
        0x40: [0x59, 0x02, 0xFF, 0x80, 0x40, 0x70, 0x04],
        0x5D: [0x59, 0x02, 0xFF, 0x80, 0x0A, 0xBF, 0x08],
    ]
}

final class DemoTransport: Transport, @unchecked Sendable {
    let start = Date()

    func send(_ target: UInt8, _ uds: [UInt8]) throws -> [UInt8]? {
        Thread.sleep(forTimeInterval: 0.01)
        guard target == Address.engine, let sid = uds.first else {
            return uds.first == 0x19 ? DemoScenario.faults[target] : nil
        }
        switch sid {
        case 0x01:
            guard uds.count >= 2 else { return nil }
            let pid = uds[1]
            if pid % 0x20 == 0 {                                    // supported-PID bitmaps
                var bits: UInt32 = 0
                for p in Pids.all where p.pid > pid && p.pid <= pid + 0x20 { bits |= 1 << (31 - UInt32(p.pid - pid - 1)) }
                if Pids.all.contains(where: { $0.pid > pid + 0x20 }) { bits |= 1 }   // the next bitmap follows
                return [0x41, pid, UInt8(bits >> 24), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits & 0xFF)]
            }
            guard let p = Pids.all.first(where: { $0.pid == pid }), let v = DemoScenario.sample(Date().timeIntervalSince(start))[p.key] else { return nil }
            return [0x41, pid] + DemoScenario.encode(p.key, v)
        case 0x06:                                                  // misfire monitor: 4 cylinders, cylinder 2 a little
            guard uds.count >= 2 else { return nil }
            let mid = uds[1]
            if mid % 0x20 == 0 { return [0x46, mid] + (mid == 0xA0 ? [0x78, 0x00, 0x00, 0x00] : [0x00, 0x00, 0x00, mid < 0xA0 ? 0x01 : 0x00]) }
            guard (0xA2...0xA5).contains(mid) else { return nil }
            let c: UInt8 = mid == 0xA3 ? 7 : 0, a: UInt8 = mid == 0xA3 ? 3 : 0
            return [0x46, mid, 0x0B, 0x24, 0x00, a, 0x00, 0x00, 0xFF, 0xFF, 0x0C, 0x24, 0x00, c, 0x00, 0x00, 0xFF, 0xFF]
        case 0x03: return [0x43, 0x01, 0x01, 0x71]                  // P0171
        case 0x07: return [0x47, 0x00]
        case 0x02: return [0x42, 0x02, 0x00, 0x00, 0x00]
        case 0x22 where uds.count >= 3 && uds[1] == 0xF1 && uds[2] == 0x90:
            return [0x62, 0xF1, 0x90] + Array("WBADEMO0000000000".utf8)
        case 0x19: return DemoScenario.faults[target]
        default: return nil
        }
    }

    func sendAll(_ uds: [UInt8]) throws -> [UInt8: [UInt8]] { DemoScenario.faults }
    func close() {}
}

extension Car {
    /// The simulated car (see DemoScenario).
    public static func demo() -> Car { Car(transport: DemoTransport(), connection: "DEMO") }
    /// A ready-made engine log from the simulated car.
    public static func demoLog() -> [Sample] { DemoScenario.log() }
}
