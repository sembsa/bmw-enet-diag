// Norms - typical ranges of public OBD values that hold for any modern petrol engine, judged in context
// (running, warm, closed loop). BMWs run hot (coolant to ~110 °C, oil to ~130 °C). Values that depend on the
// engine (idle air mass, rail pressure, manifold pressure on Valvetronic) get no norm on purpose.
public struct Norm: Sendable, Equatable {
    public let range: L
    public let ok: Bool?            // nil: not judged now (cold engine, open loop)
    public let note: L?
}

public enum Norms {
    public static func check(_ key: String, _ v: Double, in s: Sample) -> Norm? {
        let running = (s["rpm"] ?? 0) > 400
        let warm = (s["coolant"] ?? 0) >= 70
        let closedLoop = s["fuel_status"].map { Int($0) & 0x02 != 0 } ?? true
        func norm(_ r: ClosedRange<Double>, _ pl: String, _ en: String) -> Norm { Norm(range: L(pl, en), ok: r.contains(v), note: nil) }
        func later(_ pl: String, _ en: String, _ why: L) -> Norm { Norm(range: L(pl, en), ok: nil, note: why) }
        let cold = L("silnik zimny", "engine cold"), open = L("pętla otwarta", "open loop"), off = L("silnik wyłączony", "engine off")
        switch key {
        case "coolant": return warm ? norm(80...112, "80–110 °C", "80–110 °C") : later("80–110 °C", "80–110 °C", L("rozgrzewa się", "warming up"))
        case "oil": return v >= 70 ? norm(70...135, "70–130 °C", "70–130 °C") : later("70–130 °C", "70–130 °C", L("rozgrzewa się", "warming up"))
        case "stft", "ltft":
            return running && closedLoop ? norm(-10...10, "±10 %", "±10 %") : later("±10 %", "±10 %", running ? open : off)
        case "lambda":
            return running && closedLoop ? norm(0.97...1.03, "0,97–1,03", "0.97–1.03") : later("0,97–1,03", "0.97–1.03", running ? open : off)
        case "voltage":
            return running ? norm(13.2...15.0, "13,2–15 V", "13.2–15 V") : norm(12.2...12.9, "12,2–12,8 V (bez silnika)", "12.2–12.8 V (engine off)")
        case "rpm":
            guard running, (s["speed"] ?? 0) == 0 else { return nil }
            return warm ? norm(600...950, "wolne 600–950", "idle 600–950") : later("wolne 600–950", "idle 600–950", cold)
        case "cat1":
            guard running else { return nil }
            return warm ? norm(300...900, "300–900 °C", "300–900 °C") : later("300–900 °C", "300–900 °C", cold)
        case "fuel_status":
            guard running else { return nil }
            return warm ? norm(2...2, "2 (zamknięta)", "2 (closed)") : later("2 (zamknięta)", "2 (closed)", cold)
        case "mil", "dist_mil": return norm(0...0, "0", "0")
        default: return nil
        }
    }
}
