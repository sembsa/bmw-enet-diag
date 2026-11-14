// Transport - bytes to and from control units, below the allowlist. Internal: only Car reaches it, and Car
// checks every request first. Two adapters: TcpTransport (HSFZ to the car's ENET gateway) and ReplayTransport.
import Darwin
import Foundation

protocol Transport: AnyObject, Sendable {
    /// One unit's final response; nil when it does not answer.
    func send(_ target: UInt8, _ uds: [UInt8]) throws -> [UInt8]?
    /// Every unit's response to a functional request.
    func sendAll(_ uds: [UInt8]) throws -> [UInt8: [UInt8]]
    func close()
}

public struct LinkError: Error, CustomStringConvertible {
    public let description: String
}

/// HSFZ over TCP 6801: [length u32][control u16][source][target][UDS]. Blocking; Car calls it off the main thread.
final class TcpTransport: Transport, @unchecked Sendable {
    static let port: UInt16 = 6801
    let fd: Int32
    let timeout: Double
    var last = Date.distantPast
    var quiet = 1.5, functionalLimit = 15.0

    init(host: String, port: UInt16 = TcpTransport.port, timeout: Double = 3) throws {
        self.timeout = timeout
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { throw LinkError(description: "bad address \(host)") }
        fd = socket(AF_INET, SOCK_STREAM, 0)
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if ok != 0 {
            let e = String(cString: strerror(errno))
            Darwin.close(fd)
            throw LinkError(description: "no connection to \(host): \(e)")
        }
    }

    private func setTimeout(_ s: Double) {
        var tv = timeval(tv_sec: Int(s), tv_usec: Int32((s - floor(s)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// n bytes, or nil on timeout
    private func read(_ n: Int) throws -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: n), got = 0
        while got < n {
            let r = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + got, n - got, 0) }
            if r == 0 { throw LinkError(description: "the gateway closed the connection") }
            if r < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { if got == 0 { return nil }; continue }
                throw LinkError(description: String(cString: strerror(errno)))
            }
            got += r
        }
        return buf
    }

    /// (source, payload) of the next diagnostic frame; nil on timeout. Acks and empty frames skipped.
    private func frame(within s: Double) throws -> (UInt8, [UInt8])? {
        let end = Date().addingTimeInterval(s)
        while Date() < end {
            setTimeout(max(0.05, end.timeIntervalSinceNow))
            guard let h = try read(6) else { return nil }
            let len = Int(h[0]) << 24 | Int(h[1]) << 16 | Int(h[2]) << 8 | Int(h[3])
            let ctrl = Int(h[4]) << 8 | Int(h[5])
            setTimeout(timeout)
            guard len >= 2, let body = try read(len) else { throw LinkError(description: "short frame") }
            if ctrl != 1 || body.count <= 2 { continue }
            return (body[0], Array(body[2...]))
        }
        return nil
    }

    private func write(_ target: UInt8, _ uds: [UInt8]) throws {
        let gap = 0.04 - Date().timeIntervalSince(last)
        if gap > 0 { Thread.sleep(forTimeInterval: gap) }
        let n = UInt32(2 + uds.count)
        let msg = [UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF), 0, 1, Address.tester, target] + uds
        let w = msg.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!, msg.count, 0) }
        if w != msg.count { throw LinkError(description: "send failed") }
    }

    static func pending(_ p: [UInt8]) -> Bool { p.count >= 3 && p[0] == 0x7F && p[2] == 0x78 }

    func send(_ target: UInt8, _ uds: [UInt8]) throws -> [UInt8]? {
        try write(target, uds)
        defer { last = Date() }
        var end = Date().addingTimeInterval(timeout)
        while Date() < end {
            guard let (src, p) = try frame(within: end.timeIntervalSinceNow) else { return nil }
            if src != target { continue }
            if Self.pending(p) { end = Date().addingTimeInterval(5); continue }
            return p
        }
        return nil
    }

    func sendAll(_ uds: [UInt8]) throws -> [UInt8: [UInt8]] {
        try write(Address.all, uds)
        defer { last = Date() }
        var out: [UInt8: [UInt8]] = [:]
        let end = Date().addingTimeInterval(functionalLimit)
        while Date() < end, let (src, p) = try frame(within: min(quiet, end.timeIntervalSinceNow)) {
            if !Self.pending(p) { out[src] = p }
        }
        return out
    }

    func close() { Darwin.close(fd) }
}

/// Answers from a saved probe's exchanges: {"12:0100": "4100…", "df:1902ff": {"12": "5902…"}}.
final class ReplayTransport: Transport, @unchecked Sendable {
    let exchanges: [String: Any]
    init(exchanges: [String: Any]) { self.exchanges = exchanges }

    func send(_ target: UInt8, _ uds: [UInt8]) throws -> [UInt8]? {
        (exchanges[String(format: "%02x:", target) + hex(uds)] as? String).map(unhex)
    }

    func sendAll(_ uds: [UInt8]) throws -> [UInt8: [UInt8]] {
        let m = exchanges[String(format: "%02x:", Address.all) + hex(uds)] as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: m.compactMap { k, v in UInt8(k, radix: 16).map { ($0, unhex(v)) } })
    }

    func close() {}
}

/// The ENET gateway: HSFZ identification broadcast to UDP 6811; (ip, ident text) of the first answer.
public func discoverGateway(timeout: Double = 4) -> (ip: String, ident: String)? {
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    defer { Darwin.close(fd) }
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
    var tv = timeval(tv_sec: 0, tv_usec: 500_000)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    let ident: [UInt8] = [0, 0, 0, 0, 0, 0x11]
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        for dst in ["169.254.255.255", "255.255.255.255"] {
            var a = sockaddr_in()
            a.sin_family = sa_family_t(AF_INET); a.sin_port = UInt16(6811).bigEndian
            inet_pton(AF_INET, dst, &a.sin_addr)
            _ = withUnsafePointer(to: &a) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, ident, ident.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
        var buf = [UInt8](repeating: 0, count: 2048)
        var from = sockaddr_in(), len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = withUnsafeMutablePointer(to: &from) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
        }
        if n > 6 {
            var ip = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &from.sin_addr, &ip, socklen_t(INET_ADDRSTRLEN))
            return (String(cString: ip), String(decoding: buf[6..<n], as: UTF8.self))
        }
    }
    return nil
}
