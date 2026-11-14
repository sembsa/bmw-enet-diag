// MCP - the app as an MCP server over stdio (`EnetDiag --mcp`), for the owner's own AI client.
// Read-only like the rest: tools name operations, Car checks every request; no listener, captures folder only.
import Foundation

public enum MCP {
    static let protocolVersion = "2025-06-18"
    static let instructions = """
    Read-only BMW diagnostics over the owner's ENET cable: every control unit's fault memory and the engine \
    unit's live values. Nothing can be written, coded or cleared from here; clearing faults is done by the owner \
    in the MGU Store app "Fault Scanner" or at a workshop. Fault codes are BMW 6-digit hex codes per control unit \
    (address + code). Explain each in plain language in the owner's language, rank by what needs a workshop, say \
    when a code is only informational, and use the hint when one is attached. Live reads need the ignition on and \
    the ENET cable plugged in; never suggest operating the computer while driving.
    """

    static let host: [String: Any] = ["type": "string", "description": "ENET gateway IP; omit to discover it"]
    static let file: [String: Any] = ["type": "object", "properties": ["file": ["type": "string"]], "required": ["file"]]
    static let tools: [[String: Any]] = [
        ["name": "read_faults", "description": "Read every control unit's fault memory now (read-only): unit, code, status, our hint where we have one.",
         "inputSchema": ["type": "object", "properties": ["host": host]]],
        ["name": "engine_snapshot", "description": "One reading of the engine unit's OBD values now (rpm, temperatures, fuel trims, MAP, MAF if fitted, lambda, voltage).",
         "inputSchema": ["type": "object", "properties": ["host": host]]],
        ["name": "list_captures", "description": "Saved probes (JSON) and logs (CSV).", "inputSchema": ["type": "object", "properties": [String: Any]()]],
        ["name": "read_capture", "description": "A saved probe: faults, supported values, snapshot, freeze frame.", "inputSchema": file],
        ["name": "analyze_log", "description": "Engine check of a saved log: warm-up, mixture / fuel trims, air mass meter, charging, idle vacuum, lambda.", "inputSchema": file],
    ]

    static func faultJSON(_ f: Fault) -> [String: Any] {
        var o: [String: Any] = ["unit": f.unit, "address": f.address, "code": f.code, "kind": f.kind,
                                "status": f.active ? "active" : f.pending ? "pending" : "stored"]
        if let h = f.hint {
            o["hint"] = ["severity": h.severity.rawValue, "title": h.title.en, "what": h.what.en, "check": h.check.en,
                         "title_pl": h.title.pl, "check_pl": h.check.pl, "sources": h.sources]
        }
        return o
    }

    /// WBA… (maker) and the model-year/plant part stay; the serial number goes.
    static func redactVIN(_ v: String) -> String { v.count == 17 ? String(v.prefix(11)) + "******" : "******" }

    static func car(_ args: [String: Any]) async throws -> Car {
        if let r = ProcessInfo.processInfo.environment["ENETDIAG_REPLAY"] { return try Car(replay: URL(fileURLWithPath: r)) }
        return try await Car.connect(host: args["host"] as? String)
    }

    static func call(_ name: String, _ args: [String: Any]) async throws -> Any {
        switch name {
        case "read_faults":
            let c = try await car(args); defer { Task { await c.close() } }
            return try await c.faults().map(faultJSON)
        case "engine_snapshot":
            let c = try await car(args); defer { Task { await c.close() } }
            return try await c.snapshot()
        case "list_captures":
            return Captures.list().map(\.lastPathComponent)
        case "read_capture":
            let u = try Captures.url(args["file"] as? String ?? "")
            var d = try JSONSerialization.jsonObject(with: Data(contentsOf: u)) as? [String: Any] ?? [:]
            d["exchanges"] = nil                                     // raw answers hold the VIN
            if let v = d["vin"] as? String { d["vin"] = redactVIN(v) }
            return d
        case "analyze_log":
            let r = Analysis.analyze(try Captures.readLog(try Captures.url(args["file"] as? String ?? "")))
            return ["samples": r.samples, "warm_samples": r.warmSamples, "has_maf": r.hasMaf, "notes": r.notes.map(\.en),
                    "findings": r.findings.map { ["check": $0.check, "level": $0.level.rawValue, "title": $0.title.en,
                                                  "verdict": $0.verdict.en, "values": $0.values] }]
        default:
            throw LinkError(description: "unknown tool \(name)")
        }
    }

    /// One JSON-RPC message -> its reply (nil for notifications).
    public static func handle(_ msg: [String: Any]) async -> [String: Any]? {
        guard let id = msg["id"] else { return nil }
        let method = msg["method"] as? String ?? ""
        let result: [String: Any]
        switch method {
        case "initialize":
            result = ["protocolVersion": protocolVersion, "capabilities": ["tools": [String: Any]()],
                      "serverInfo": ["name": "bmw-enet-diag", "version": "0.2.0"], "instructions": instructions]
        case "tools/list":
            result = ["tools": tools]
        case "tools/call":
            let p = msg["params"] as? [String: Any] ?? [:]
            do {
                let out = try await call(p["name"] as? String ?? "", p["arguments"] as? [String: Any] ?? [:])
                let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
                result = ["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]]]
            } catch {
                result = ["content": [["type": "text", "text": "\(error)"]], "isError": true]
            }
        case "ping":
            result = [:]
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "method not found"]]
        }
        return ["jsonrpc": "2.0", "id": id, "result": result]
    }

    /// stdin/stdout loop, newline-delimited JSON.
    public static func serve() async {
        while let line = readLine() {
            guard !line.isEmpty else { continue }
            let reply: [String: Any]?
            if let m = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] { reply = await handle(m) }
            else { reply = ["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]] }
            if let reply, let d = try? JSONSerialization.data(withJSONObject: reply) {
                FileHandle.standardOutput.write(d + Data("\n".utf8))
            }
        }
    }
}
