// Allowlist - the one check every request to the car passes before a byte goes out. Read-only by construction:
// every unit (and all at once): read fault memory (19 01/02/04/06) only;
// the engine unit (0x12) also OBD-II read services (01 02 03 06 07 09 0A) and 22 (read by identifier). Nothing else:
// no clearing (14, OBD 04), sessions (10), security access (27), writes or routines (2E 2F 31), resets, downloads.

import Foundation

public enum Address {
    public static let tester: UInt8 = 0xF4
    public static let engine: UInt8 = 0x12
    public static let all: UInt8 = 0xDF          // functional: every control unit at once
}

public struct NotAllowed: Error, CustomStringConvertible {
    public let description: String
}

public enum Allowlist {
    static let obdRead: Set<UInt8> = [0x01, 0x02, 0x03, 0x06, 0x07, 0x09, 0x0A]   // current data, freeze frame, codes, monitor results, info, permanent codes
    static let dtcSubs: Set<UInt8> = [0x01, 0x02, 0x04, 0x06]

    public static func check(_ target: UInt8, _ uds: [UInt8]) throws {
        guard (0x01...0xFE).contains(target), target != Address.tester else {
            throw NotAllowed(description: String(format: "target 0x%02X refused", target))
        }
        guard let sid = uds.first else { throw NotAllowed(description: "empty request") }
        if sid == 0x19, uds.count >= 2, dtcSubs.contains(uds[1]) { return }
        if sid == 0x22, uds.count >= 3, target == Address.engine { return }
        if target == Address.engine, obdRead.contains(sid) { return }
        throw NotAllowed(description: String(format: "service %@ to 0x%02X refused (read-only)", hex(Array(uds.prefix(2))), target))
    }
}

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

func unhex(_ s: String) -> [UInt8] {
    var out: [UInt8] = [], i = s.startIndex
    while let j = s.index(i, offsetBy: 2, limitedBy: s.endIndex), i != s.endIndex {
        if let v = UInt8(s[i..<j], radix: 16) { out.append(v) }
        i = j
    }
    return out
}
