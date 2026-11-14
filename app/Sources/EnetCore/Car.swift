// Car - the only public way to the car. Every request passes Allowlist.check before the transport sees it.
//   let car = try await Car.connect(host: nil)       // discovers the gateway when host is nil
//   try await car.faults()   try await car.snapshot()   try await car.probe()   car.close()
import Foundation

public struct Fault: Codable, Identifiable, Sendable, Hashable {
    public let unit: String, address: String, code: String, status: UInt8
    public let active: Bool, pending: Bool, confirmed: Bool
    public var hint: Hint? { Hints.hint(address: UInt8(address, radix: 16) ?? 0, code: code) }
    public var kind: String { Hints.kind(UInt8(address, radix: 16) ?? 0) }
    public var id: String { address + code }
}

public typealias Snapshot = [String: Double]

public struct Misfire: Codable, Sendable, Hashable, Identifiable {
    public let cylinder: Int
    public let current: Double?, average: Double?
    public var id: Int { cylinder }
}

public struct Probe: Codable, Sendable {
    public var at: String
    public var connection: String
    public var vin: String?
    public var supportedPids: [String]
    public var knownValues: [String]
    public var hasMaf: Bool
    public var snapshot: Snapshot
    public var faults: [Fault]
    public var obdStored: [String], obdPending: [String]
    public var faultDetails: [String: [String: String]]     // "12:101F01" -> snapshot / extended, hex
    public var freezeFrame: Snapshot
    public var freezeFrameTrigger: String?
    public var misfires: [Misfire] = []
    public var identity: Identity?
    public var exchanges: [String: String]                  // replay capture (functional ones: JSON text)
}

public actor Car {
    private let transport: Transport
    public nonisolated let connection: String
    private var supported: Set<UInt8>?
    private var log: [String: String] = [:]
    private let queue = DispatchQueue(label: "enetdiag.link")

    init(transport: Transport, connection: String) {
        self.transport = transport
        self.connection = connection
    }

    public static func connect(host: String?) async throws -> Car {
        try await withCheckedThrowingContinuation { c in
            DispatchQueue.global().async {
                do {
                    var h = host?.trimmingCharacters(in: .whitespaces) ?? ""
                    var ident = ""
                    if h.isEmpty {
                        guard let g = discoverGateway() else {
                            throw LinkError(description: "Nie znaleziono bramki ENET: kabel, zapłon? Albo wpisz IP. macOS: zezwól na „Sieć lokalna”.")
                        }
                        (h, ident) = g
                    }
                    let t = try TcpTransport(host: h)
                    _ = ident                               // the ident text carries the VIN: not shown
                    c.resume(returning: Car(transport: t, connection: h))
                } catch { c.resume(throwing: error) }
            }
        }
    }

    /// A saved probe answers instead of the car (offline analysis, tests, screenshots).
    public init(replay url: URL) throws {
        let d = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var ex = d["exchanges"] as? [String: Any] ?? [:]
        for (k, v) in ex { if let s = v as? String, s.hasPrefix("{"), let o = try? JSONSerialization.jsonObject(with: Data(s.utf8)) { ex[k] = o } }
        self.init(transport: ReplayTransport(exchanges: ex), connection: "replay: " + url.lastPathComponent)
    }

    public func close() { transport.close() }

    // MARK: the choke point

    private func ask(_ target: UInt8, _ uds: [UInt8]) async throws -> [UInt8]? {
        try Allowlist.check(target, uds)
        let t = transport
        let r: [UInt8]? = try await withCheckedThrowingContinuation { c in
            queue.async { do { c.resume(returning: try t.send(target, uds)) } catch { c.resume(throwing: error) } }
        }
        log[String(format: "%02x:", target) + hex(uds)] = r.map(hex)
        return r
    }

    private func askAll(_ uds: [UInt8]) async throws -> [UInt8: [UInt8]] {
        try Allowlist.check(Address.all, uds)
        let t = transport
        let r: [UInt8: [UInt8]] = try await withCheckedThrowingContinuation { c in
            queue.async { do { c.resume(returning: try t.sendAll(uds)) } catch { c.resume(throwing: error) } }
        }
        let m = Dictionary(uniqueKeysWithValues: r.map { (String(format: "%02x", $0.key), hex($0.value)) })
        log[String(format: "%02x:", Address.all) + hex(uds)] = String(data: try JSONSerialization.data(withJSONObject: m, options: .sortedKeys), encoding: .utf8)
        return r
    }

    // MARK: reads

    /// Every control unit's fault memory, active first, engine first.
    public func faults() async throws -> [Fault] {
        var out: [Fault] = []
        for (addr, resp) in try await askAll([0x19, 0x02, 0xFF]) {
            for (code, st) in parseDtcs(resp) where st & 0x0D != 0 {   // failed now, pending or confirmed
                out.append(Fault(unit: Hints.unitName(addr), address: String(format: "%02X", addr), code: code, status: st,
                                 active: st & 0x01 != 0, pending: st & 0x04 != 0, confirmed: st & 0x08 != 0))
            }
        }
        return out.sorted { ($0.active ? 0 : 1, $0.address == "12" ? 0 : 1, $0.address, $0.code) < ($1.active ? 0 : 1, $1.address == "12" ? 0 : 1, $1.address, $1.code) }
    }

    public func supportedPids() async throws -> Set<UInt8> {
        if let s = supported { return s }
        var sup = Set<UInt8>(), base: UInt8 = 0
        while true {
            guard let r = try await ask(Address.engine, [0x01, base]), r.count >= 6, r[0] == 0x41 else { break }
            let bits = UInt32(r[2]) << 24 | UInt32(r[3]) << 16 | UInt32(r[4]) << 8 | UInt32(r[5])
            for i in 0..<32 where bits & (1 << (31 - UInt32(i))) != 0 { sup.insert(base &+ UInt8(i + 1)) }
            if base >= 0xC0 || !sup.contains(base &+ 0x20) { break }
            base &+= 0x20
        }
        supported = sup
        return sup
    }

    private func value(_ p: Pid, sid: UInt8 = 0x01, frame: UInt8? = nil) async throws -> Double? {
        let off = frame == nil ? 2 : 3
        guard let r = try await ask(Address.engine, [sid, p.pid] + (frame.map { [$0] } ?? [])),
              r.count >= off + p.bytes, r[0] == sid + 0x40, r[1] == p.pid else { return nil }
        return (p.decode(Array(r[off..<off + p.bytes])) * 1000).rounded() / 1000
    }

    /// The engine unit's current values (only those it supports); "t" = seconds since 1970.
    public func snapshot(_ keys: [String]? = nil) async throws -> Snapshot {
        let sup = try await supportedPids()
        var out: Snapshot = ["t": (Date().timeIntervalSince1970 * 100).rounded() / 100]
        for p in Pids.all where (keys?.contains(p.key) ?? true) && sup.contains(p.pid) {
            out[p.key] = try await value(p)
        }
        return out
    }

    /// The car's identity: VIN and what it encodes, the engine unit's OBD identification, odometer.
    public func identity() async throws -> Identity {
        var id = Identity()
        var vin: String?
        if let r = try await ask(Address.engine, [0x22, 0xF1, 0x90]), r.count >= 20, r[0] == 0x62 { vin = text(r[3...]) }
        if vin?.count != 17, let r = try await ask(Address.engine, [0x09, 0x02]), r.count >= 20, r[0] == 0x49 { vin = text(r.suffix(17)) }
        if let vin, vin.count == 17 { VIN.decode(vin, into: &id) }
        if let r = try await ask(Address.engine, [0x09, 0x0A]), r.count > 3, r[0] == 0x49 { id.ecuName = text(r[3...]) }
        if let r = try await ask(Address.engine, [0x09, 0x04]), r.count > 3, r[0] == 0x49 {
            let d = Array(r[3...])
            id.calibrationIds = stride(from: 0, to: d.count - 15, by: 16).map { text(d[$0..<$0 + 16]) }.filter { !$0.isEmpty }
        }
        if let r = try await ask(Address.engine, [0x09, 0x06]), r.count > 3, r[0] == 0x49 {
            let d = Array(r[3...])
            id.cvns = stride(from: 0, to: d.count - 3, by: 4).map { d[$0..<$0 + 4].map { String(format: "%02X", $0) }.joined() }
        }
        let sup = try await supportedPids()
        if sup.contains(0x1C), let r = try await ask(Address.engine, [0x01, 0x1C]), r.count >= 3, r[0] == 0x41 { id.obdStandard = obdStandardName(r[2]) }
        if sup.contains(0xA6), let p = Pids.byKey["odometer"] { id.odometerKm = try await value(p) }
        return id
    }

    /// Misfire counters per cylinder (OBD mode 06), for the cylinders the engine unit reports.
    public func misfires() async throws -> [Misfire] {
        var sup = Set<UInt8>()
        for base: UInt8 in [0x00, 0x20, 0x40, 0x60, 0x80, 0xA0] {
            guard let r = try await ask(Address.engine, [0x06, base]), r.count >= 6, r[0] == 0x46 else { continue }
            let bits = UInt32(r[2]) << 24 | UInt32(r[3]) << 16 | UInt32(r[4]) << 8 | UInt32(r[5])
            for i in 0..<32 where bits & (1 << (31 - UInt32(i))) != 0 { sup.insert(base &+ UInt8(i + 1)) }
        }
        var out: [Misfire] = []
        for (n, mid) in (0xA2...0xAD).enumerated() where sup.contains(UInt8(mid)) {
            let m = parseMisfire(try await ask(Address.engine, [0x06, UInt8(mid)]), mid: UInt8(mid))
            out.append(Misfire(cylinder: n + 1, current: m.current, average: m.average))
        }
        return out
    }

    /// Everything worth keeping from one visit: a first look, and a replay capture.
    public func probe() async throws -> Probe {
        let faults = try await faults()
        var details: [String: [String: String]] = [:]
        for f in faults where f.address == "12" || f.active {
            let a = UInt8(f.address, radix: 16)!, dtc = unhex(f.code)
            var d: [String: String] = [:]
            for (sub, name) in [(UInt8(0x04), "snapshot"), (0x06, "extended")] {
                if let r = try await ask(a, [0x19, sub] + dtc + [0xFF]) { d[name] = hex(r) }
            }
            details[f.address + ":" + f.code] = d
        }
        let sup = try await supportedPids()
        var vin: String?
        if let r = try await ask(Address.engine, [0x22, 0xF1, 0x90]), r.count > 3, r[0] == 0x62 {
            vin = String(decoding: r[3...], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        }
        let stored = parseObdCodes(try await ask(Address.engine, [0x03]), sid: 0x03)
        let pending = parseObdCodes(try await ask(Address.engine, [0x07]), sid: 0x07)
        var ff: Snapshot = [:], trigger: String?
        if let r = try await ask(Address.engine, [0x02, 0x02, 0x00]), r.count >= 5, r[0] == 0x42, r[3] != 0 || r[4] != 0 {
            trigger = pcode(r[3], r[4])
            for p in Pids.all where sup.contains(p.pid) { ff[p.key] = try await value(p, sid: 0x02, frame: 0) }
        }
        let snap = try await snapshot()
        let mis = (try? await misfires()) ?? []
        var p = Probe(at: ISO8601DateFormatter().string(from: Date()), connection: connection, vin: vin,
                     supportedPids: sup.sorted().map { String(format: "%02X", $0) },
                     knownValues: Pids.all.filter { sup.contains($0.pid) }.map(\.key),
                     hasMaf: sup.contains(0x10), snapshot: snap, faults: faults,
                     obdStored: stored, obdPending: pending, faultDetails: details,
                     freezeFrame: ff, freezeFrameTrigger: trigger, exchanges: log)
        p.misfires = mis
        p.identity = try? await identity()
        p.exchanges = log
        return p
    }
}
