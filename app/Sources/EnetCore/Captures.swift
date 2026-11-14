// Captures - probes and logs in ~/Library/Application Support/EnetDiag/captures (hold the VIN: never in git).
// Every name from outside (MCP, UI) is confined to that folder.
import Foundation

public enum Captures {
    public static var folder: URL {
        if let d = ProcessInfo.processInfo.environment["ENETDIAG_CAPTURES"] { return URL(fileURLWithPath: d) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnetDiag/captures")
    }

    static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    public static func list() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["json", "csv"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// A capture by name, only inside the captures folder.
    public static func url(_ name: String) throws -> URL {
        let u = folder.appendingPathComponent((name as NSString).lastPathComponent).resolvingSymlinksInPath()
        let regular = (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        guard u.deletingLastPathComponent().path == folder.resolvingSymlinksInPath().path, regular else {
            throw LinkError(description: "no such capture: \(name)")
        }
        return u
    }

    @discardableResult
    public static func save(_ p: Probe) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        let u = folder.appendingPathComponent("probe-\(stamp()).json")
        try e.encode(p).write(to: u)
        return u
    }

    public static let logKeys = ["rpm", "speed", "coolant", "oil", "iat", "stft", "ltft", "fuel_status", "map", "maf", "throttle",
                                 "load", "lambda", "lambda_cmd", "rail", "cat1", "baro", "voltage"]

    /// CSV log: t + logKeys, one row per snapshot.
    public final class LogWriter {
        public let url: URL
        let h: FileHandle
        public init() throws {
            try FileManager.default.createDirectory(at: Captures.folder, withIntermediateDirectories: true)
            url = Captures.folder.appendingPathComponent("log-\(Captures.stamp()).csv")
            FileManager.default.createFile(atPath: url.path, contents: Data((["t"] + logKeys).joined(separator: ",").appending("\n").utf8))
            h = try FileHandle(forWritingTo: url)
            h.seekToEndOfFile()
        }
        public func write(_ s: Snapshot) {
            let row = (["t"] + logKeys).map { s[$0].map { String($0) } ?? "" }.joined(separator: ",") + "\n"
            h.write(Data(row.utf8))
        }
        public func close() { try? h.close() }
    }

    public static func readLog(_ url: URL) throws -> [Sample] {
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        guard let head = lines.first?.split(separator: ",", omittingEmptySubsequences: false).map(String.init) else { return [] }
        return lines.dropFirst().map { line in
            var s: Sample = [:]
            for (k, v) in zip(head, line.split(separator: ",", omittingEmptySubsequences: false)) { if let d = Double(v), d.isFinite { s[k] = d } }
            return s
        }
    }
}
