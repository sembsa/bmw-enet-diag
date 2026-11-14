// swift test - no car needed: a loopback fake gateway and replayed answers.
import Darwin
import Foundation
import XCTest
@testable import EnetCore

final class AllowlistTests: XCTestCase {
    func testReadsPass() throws {
        let ok: [(UInt8, [UInt8])] = [(0x12, [0x01, 0x0C]), (0x12, [0x02, 0x02, 0x00]), (0x12, [0x03]), (0x12, [0x07]),
                                      (0x12, [0x09, 0x02]), (0x12, [0x22, 0x58, 0x89]), (0x40, [0x19, 0x02, 0xFF]),
                                      (0xDF, [0x19, 0x02, 0xFF]), (0x63, [0x19, 0x02, 0xFF]), (0x12, [0x19, 0x04, 0x10, 0x1F, 0x01, 0xFF]),
                                      (0x12, [0x06, 0xA2]), (0x12, [0x0A])]
        for (t, r) in ok { try Allowlist.check(t, r) }
    }

    func testEverythingElseRefused() {
        let bad: [(UInt8, [UInt8])] = [
            (0x12, [0x04]), (0x12, [0x14, 0xFF, 0xFF, 0xFF]), (0xDF, [0x14, 0xFF, 0xFF, 0xFF]), (0x12, [0x10, 0x03]),
            (0x12, [0x27, 0x01]), (0x12, [0x2E, 0x01, 0x02]), (0x40, [0x2F, 0x45, 0x01, 0x03]), (0x12, [0x31, 0x01, 0x30, 0x00]),
            (0x12, [0x11, 0x01]), (0x12, [0x3E, 0x00]), (0x12, [0x28, 0x00]), (0x12, [0x85, 0x02]), (0x12, [0x34]),
            (0x12, [0x36]), (0x12, [0x37]), (0x12, [0x19, 0x14]), (0x63, [0x22, 0x17, 0x2A]), (0x40, [0x01, 0x0C]),
            (0x63, [0x22, 0xF1, 0x90]), (0x12, [0x08, 0x01]), (0x40, [0x06, 0xA2]),
            (0xF4, [0x19, 0x02, 0xFF]), (0x00, [0x19, 0x02, 0xFF]), (0xFF, [0x19, 0x02, 0xFF]), (0x12, [])]
        for (t, r) in bad {
            XCTAssertThrowsError(try Allowlist.check(t, r), String(format: "%02x %@", t, hex(r))) { XCTAssertTrue($0 is NotAllowed) }
        }
    }

    /// The car never sees a refused request: the transport is not called.
    func testRefusedBeforeTheTransport() async throws {
        final class Tripwire: Transport, @unchecked Sendable {
            var calls = 0
            func send(_ t: UInt8, _ u: [UInt8]) throws -> [UInt8]? { calls += 1; return nil }
            func sendAll(_ u: [UInt8]) throws -> [UInt8: [UInt8]] { calls += 1; return [:] }
            func close() {}
        }
        let w = Tripwire()
        let car = Car(transport: w, connection: "test")
        _ = try await car.faults()
        XCTAssertEqual(w.calls, 1)   // the allowed functional read only
    }
}

/// A one-connection HSFZ gateway on 127.0.0.1 answering a script of replies.
final class FakeGateway: @unchecked Sendable {
    let port: UInt16
    var got: [[UInt8]] = []
    private let fd: Int32

    init(replies: [[[UInt8]]]) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(fd, 1)
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        port = UInt16(bigEndian: a.sin_port)
        self.fd = fd
        Thread.detachNewThread { [self] in
            let c = accept(fd, nil, nil)
            for rep in replies {
                var h = [UInt8](repeating: 0, count: 6)
                guard recv(c, &h, 6, MSG_WAITALL) == 6 else { break }
                let n = Int(h[0]) << 24 | Int(h[1]) << 16 | Int(h[2]) << 8 | Int(h[3])
                var b = [UInt8](repeating: 0, count: n)
                _ = recv(c, &b, n, MSG_WAITALL)
                got.append(h + b)
                let out = rep.flatMap { $0 }
                _ = out.withUnsafeBytes { Darwin.send(c, $0.baseAddress!, out.count, 0) }
            }
            var x: UInt8 = 0
            _ = recv(c, &x, 1, 0)        // open until the tester leaves, as the real gateway
            close(c); close(fd)
        }
    }

    static func frame(_ src: UInt8, _ tgt: UInt8, _ p: [UInt8], ctrl: UInt8 = 1) -> [UInt8] {
        let n = 2 + p.count
        return [0, 0, UInt8(n >> 8), UInt8(n & 0xFF), 0, ctrl, src, tgt] + p
    }
}

final class TransportTests: XCTestCase {
    func testFramingAndFunctionalScan() async throws {
        let F = FakeGateway.frame
        let gw = FakeGateway(replies: [
            [F(0xF4, 0x12, [0x01, 0x00], 2), F(0x40, 0xF4, [0x7F, 0x19, 0x11], 1), F(0x12, 0xF4, [0x7F, 0x01, 0x78], 1),
             F(0x12, 0xF4, [0x41, 0x00, 0x08, 0x10, 0x00, 0x00], 1)],                   // supports 0x05, 0x0C
            [F(0x12, 0xF4, [0x41, 0x0C, 0x0C, 0x80], 1)],                                // asked in Pids.all order
            [F(0x12, 0xF4, [0x41, 0x05, 0x7D], 1)],
            [F(0x12, 0xF4, [0x59, 0x02, 0xFF, 0x10, 0x1F, 0x01, 0x09], 1), F(0x5D, 0xF4, [0x59, 0x02, 0xFF, 0x80, 0x0A, 0xBF, 0x08, 0xCD, 0x04, 0x0A, 0x43], 1),
             F(0x29, 0xF4, [0x59, 0x02, 0xFF], 1)],
        ])
        let t = try TcpTransport(host: "127.0.0.1", port: gw.port, timeout: 2)
        t.quiet = 0.3
        let car = Car(transport: t, connection: "test")
        let s = try await car.snapshot()
        XCTAssertEqual(s["coolant"], 85)
        XCTAssertEqual(s["rpm"], 800)
        let f = try await car.faults()
        await car.close()
        XCTAssertEqual(f.map { "\($0.address) \($0.code) \($0.active)" }, ["12 101F01 true", "5D 800ABF false"])
        XCTAssertEqual(f[0].hint?.severity, .workshop)
        XCTAssertEqual(gw.got[0], [0, 0, 0, 4, 0, 1, 0xF4, 0x12, 0x01, 0x00])
        XCTAssertEqual(gw.got[3][7], 0xDF)
    }
}

func replayCar() -> Car {
    let ex: [String: Any] = [
        "12:0100": "4100be1fa813", "12:0120": "41208005b011", "12:0140": "4140fed08c01",
        "12:010c": "410c0c80", "12:0105": "41057d", "12:0106": "410690", "12:0107": "41078a", "12:010b": "410b20",
        "12:0110": "41100190", "12:010f": "410f3c", "12:010d": "410d00", "12:0111": "41110c",
        "12:03": "43010171", "12:07": "4700", "12:22f190": "62f190" + hex(Array("WBA00000000000000".utf8)),
        "12:020200": "420200000000",
        "df:1902ff": ["12": "5902ff101f0109", "37": "5902ffb7f50009"],
    ]
    return Car(transport: ReplayTransport(exchanges: ex), connection: "replay")
}

final class CarTests: XCTestCase {
    func testProbe() async throws {
        let p = try await replayCar().probe()
        XCTAssertEqual(p.vin, "WBA00000000000000")
        XCTAssertTrue(p.hasMaf)
        XCTAssertEqual(p.snapshot["rpm"], 800)
        XCTAssertEqual(p.snapshot["stft"], 12.5)
        XCTAssertEqual(p.faults.map(\.unit), ["DME engine", "RAM audio"])
        XCTAssertEqual(p.obdStored, ["P0171"])
        XCTAssertNil(p.freezeFrameTrigger)
        XCTAssertNotNil(p.exchanges["df:1902ff"])
    }

    func testDecode() {
        XCTAssertEqual(pcode(0x01, 0x71), "P0171")
        XCTAssertEqual(pcode(0xC1, 0x00), "U0100")
        XCTAssertEqual(Hints.unitName(0x5D), "KAFAS camera")
        XCTAssertEqual(Hints.unitName(0x99), "ECU 0x99")
        XCTAssertEqual(Hints.hint(address: 0x12, code: "101F01")?.title.en, "Intake air mass not plausible")
    }
}

func rows(_ idle: Double, _ mid: Double, coolant: Double = 85, maf: Bool = true, n: Int = 30) -> [Sample] {
    (0..<n).flatMap { _ -> [Sample] in
        var a: Sample = ["rpm": 780, "speed": 0, "coolant": coolant, "stft": idle / 2, "ltft": idle / 2, "map": 32, "iat": 25, "voltage": 14.1]
        var b: Sample = ["rpm": 2600, "speed": 0, "coolant": coolant, "stft": mid / 2, "ltft": mid / 2, "map": 45, "iat": 25, "voltage": 14.2]
        if maf { a["maf"] = 3.0; b["maf"] = 13.5 }
        return [a, b]
    }
}

final class AnalysisTests: XCTestCase {
    func level(_ r: Report, _ c: String) -> Finding.Level? { r.findings.first { $0.check == c }?.level }

    func testVerdicts() {
        XCTAssertEqual(level(Analysis.analyze(rows(16, 3)), "mixture"), .problem)
        XCTAssertTrue(Analysis.analyze(rows(16, 3)).findings.first { $0.check == "mixture" }!.verdict.en.contains("intake leak"))
        XCTAssertTrue(Analysis.analyze(rows(14, 13)).findings.first { $0.check == "mixture" }!.verdict.en.contains("everywhere"))
        XCTAssertEqual(level(Analysis.analyze(rows(2, -1)), "mixture"), .ok)
        XCTAssertEqual(level(Analysis.analyze(rows(-12, -10)), "mixture"), .problem)
        XCTAssertNil(level(Analysis.analyze(rows(16, 3, coolant: 40)), "mixture"))
        XCTAssertEqual(level(Analysis.analyze(rows(2, 1)), "charging"), .ok)
        XCTAssertEqual(level(Analysis.analyze(rows(2, 1)), "airMass"), .ok)
        let valvetronic = Analysis.analyze(rows(2, 1).map { var r = $0; r["map"] = 90; return r })
        XCTAssertNil(level(valvetronic, "airMass"))
        XCTAssertEqual(level(valvetronic, "idleVacuum"), .unknown)
        let noMaf = Analysis.analyze(rows(16, 3, maf: false))
        XCTAssertFalse(noMaf.hasMaf)
        XCTAssertNil(level(noMaf, "airMass"))
    }
}

final class MCPTests: XCTestCase {
    func testProtocolAndPaths() async throws {
        let i = await MCP.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:]])!
        XCTAssertTrue(((i["result"] as! [String: Any])["instructions"] as! String).contains("Read-only"))
        let l = await MCP.handle(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])!
        let names = ((l["result"] as! [String: Any])["tools"] as! [[String: Any]]).map { $0["name"] as! String }
        XCTAssertFalse(names.contains { $0.contains("clear") || $0.contains("write") })
        let n = await MCP.handle(["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertNil(n)
        let bad = await MCP.handle(["jsonrpc": "2.0", "id": 3, "method": "tools/call",
                                    "params": ["name": "read_capture", "arguments": ["file": "../../etc/passwd"]]])!
        XCTAssertEqual((bad["result"] as! [String: Any])["isError"] as? Bool, true)
    }

    func testCaptureRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        setenv("ENETDIAG_CAPTURES", dir.path, 1)
        defer { unsetenv("ENETDIAG_CAPTURES") }
        let p = try await replayCar().probe()
        let u = try Captures.save(p)
        let again = try await Car(replay: u).faults()
        XCTAssertEqual(again.map(\.code), ["101F01", "B7F500"])
        let w = try Captures.LogWriter()
        for r in rows(16, 3) { w.write(r) }
        w.close()
        let r = await MCP.handle(["jsonrpc": "2.0", "id": 4, "method": "tools/call",
                                  "params": ["name": "analyze_log", "arguments": ["file": w.url.lastPathComponent]]])!
        let text = (((r["result"] as! [String: Any])["content"] as! [[String: Any]])[0]["text"] as! String)
        XCTAssertTrue(text.contains("intake leak"), text)
    }
}

final class DemoTests: XCTestCase {
    func testDemoCarDecodesAndShowsALeak() async throws {
        let car = Car.demo()
        let s = try await car.snapshot()
        XCTAssertNotNil(s["rpm"]); XCTAssertNotNil(s["ltft"]); XCTAssertNotNil(s["voltage"])
        XCTAssertEqual(s["coolant"]!, 74, accuracy: 2)
        let f = try await car.faults()
        XCTAssertEqual(f.first?.code, "101F01")
        let p = try await car.probe()
        XCTAssertEqual(p.vin, "WBA7L1100N7123456")
        XCTAssertEqual(p.obdStored, ["P0171"])
        let mis = try await car.misfires()
        XCTAssertEqual(mis.map(\.cylinder), [1, 2, 3, 4])
        XCTAssertEqual(mis[1].current, 7); XCTAssertEqual(mis[1].average, 3); XCTAssertEqual(mis[0].current, 0)
        let s2 = try await car.snapshot()
        XCTAssertEqual(s2["odometer"], 48213); XCTAssertEqual(s2["fuel_status"], 2); XCTAssertNotNil(s2["cat1"])
        let r = Analysis.analyze(Car.demoLog())
        XCTAssertEqual(r.findings.first { $0.check == "mixture" }?.level, .problem)
        XCTAssertEqual(r.findings.first { $0.check == "charging" }?.level, .ok)
    }
}

final class HardeningTests: XCTestCase {
    /// The gateway hangs up: the next request is an error, the process lives (no SIGPIPE).
    func testClosedGatewayIsAnErrorNotACrash() throws {
        let gw = FakeGateway(replies: [])
        let t = try TcpTransport(host: "127.0.0.1", port: gw.port, timeout: 1)
        _ = try? t.send(0x12, [0x01, 0x0C])
        Thread.sleep(forTimeInterval: 0.2)
        var failed = false
        for _ in 0..<5 { do { _ = try t.send(0x12, [0x01, 0x0C]) } catch { failed = true; break } }
        XCTAssertTrue(failed)
        t.close()
    }

    func testOnlyLocalGateways() {
        XCTAssertThrowsError(try TcpTransport(host: "8.8.8.8", port: 6801, timeout: 1))
        XCTAssertTrue(TcpTransport.isLocal(0xA9FE0001)); XCTAssertTrue(TcpTransport.isLocal(0xC0A80101))
        XCTAssertFalse(TcpTransport.isLocal(0x08080808))
    }

    func testCapturesConfinedAndFinite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("ENETDIAG_CAPTURES", dir.path, 1)
        defer { unsetenv("ENETDIAG_CAPTURES") }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("{}".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link.json"), withDestinationURL: outside)
        XCTAssertThrowsError(try Captures.url("link.json"))
        try Data("rpm,coolant\nnan,90\ninf,91\n800,92\n".utf8).write(to: dir.appendingPathComponent("log-x.csv"))
        let rows = try Captures.readLog(try Captures.url("log-x.csv"))
        XCTAssertTrue(rows.allSatisfy { $0.values.allSatisfy(\.isFinite) })
        XCTAssertEqual(rows.compactMap { $0["rpm"] }, [800])
    }

    func testVinRedactedAndNonFaultsHidden() async throws {
        XCTAssertEqual(MCP.redactVIN("WBA12345678901234"), "WBA12345678******")
        final class T: Transport, @unchecked Sendable {
            func send(_ t: UInt8, _ u: [UInt8]) throws -> [UInt8]? { nil }
            func sendAll(_ u: [UInt8]) throws -> [UInt8: [UInt8]] { [0x12: [0x59, 0x02, 0xFF, 0x10, 0x1F, 0x01, 0x09, 0x11, 0x11, 0x11, 0x40]] }
            func close() {}
        }
        let f = try await Car(transport: T(), connection: "t").faults()
        XCTAssertEqual(f.map(\.code), ["101F01"])      // 0x40 alone (not completed since clear) is not a fault
    }
}

final class IdentityTests: XCTestCase {
    func testVinDecoding() {
        XCTAssertEqual(VIN.modelYear("N", now: 2026), 2022)
        XCTAssertEqual(VIN.modelYear("L", now: 2026), 2020)
        XCTAssertEqual(VIN.modelYear("A", now: 2026), 2010)
        XCTAssertEqual(VIN.modelYear("9", now: 2026), 2009)
        var id = Identity()
        VIN.decode("WBA7L1100N7123456", into: &id)
        XCTAssertEqual([id.maker, id.typeCode, id.plantCode, id.serial], ["BMW AG", "7L11", "7", "123456"])
        XCTAssertEqual(id.modelYear, 2022)
    }

    func testDemoIdentity() async throws {
        let id = try await Car.demo().identity()
        XCTAssertEqual(id.vin, "WBA7L1100N7123456")
        XCTAssertEqual(id.ecuName, "ECM-EngineControl")
        XCTAssertEqual(id.calibrationIds, ["DEMO8FF0R7.2.1"])
        XCTAssertEqual(id.cvns, ["1A2B3C4D"])
        XCTAssertEqual(id.obdStandard, "EOBD (Europa)")
        XCTAssertEqual(id.odometerKm, 48213)
    }
}
