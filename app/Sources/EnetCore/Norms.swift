// Norms - typical ranges of public OBD values that hold for any modern petrol engine, judged in context
// (running, warm, closed loop). BMWs run hot (coolant to ~110 °C, oil to ~130 °C). Values that depend on the
// engine (idle air mass, rail pressure, manifold pressure on Valvetronic) are judged only for an engine picked in Settings.
public struct Norm: Sendable, Equatable {
    public let range: L
    public let ok: Bool?            // nil: not judged now (cold engine, open loop)
    public let note: L?
}

/// A BMW petrol engine the owner picked in Settings (the car doesn't say which engine it has over public OBD).
/// Values and their sources: research/engine_norms.json. Only well-sourced numbers are judged; rules of thumb are shown
/// as a guide without a ✓/✗.
public struct Engine: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let valvetronic: Bool
    public let railMax: Double?             // design maximum, bar
    public let mafIdle: ClosedRange<Double>? // rule of thumb, low confidence
    public let note: L?

    static let rich = L("Biuletyn BMW SI B11 07 17: zimą przy krótkich trasach paliwo w oleju daje błąd „mieszanka za bogata” (118002) – dłuższa jazda zwykle pomaga.",
                        "BMW SI B11 07 17: in winter on short trips, fuel in the oil gives 'mixture too rich' (118002) – a longer drive usually helps.")
    static let tu = L("Silniki po modernizacji (ok. 2018+) mają do 350 bar, starsze do 200 bar.", "Updated engines (c. 2018+) run up to 350 bar, earlier ones up to 200 bar.")

    public static let all: [Engine] = [
        Engine(id: "B38", name: "B38 – 1.5 R3 (116i/118i, 216i/218i, X1/X2 sDrive18i)", valvetronic: true, railMax: 350, mafIdle: 1.5...3, note: rich),
        Engine(id: "B46", name: "B46 – 2.0 R4", valvetronic: true, railMax: 350, mafIdle: 2...4, note: rich),
        Engine(id: "B48", name: "B48 – 2.0 R4 (120i/220i/320i/330i, X1/X3 20i)", valvetronic: true, railMax: 350, mafIdle: 2...4, note: tu),
        Engine(id: "B58", name: "B58 – 3.0 R6 (M140i/M240i/340i/540i, X3/X5 40i)", valvetronic: true, railMax: 350, mafIdle: 3...6,
               note: L("Znana usterka: pęknięta membrana odmy w pokrywie zaworów – ubogo na wolnych, gwizd.", "Known issue: a torn PCV diaphragm in the valve cover – lean idle, whistle.")),
        Engine(id: "S58", name: "S58 – 3.0 R6 (M3/M4, X3 M/X4 M)", valvetronic: true, railMax: 350, mafIdle: 3...6, note: nil),
        Engine(id: "N13", name: "N13 – 1.6 R4 (114i–120i F20)", valvetronic: true, railMax: nil, mafIdle: 1.6...3.2, note: nil),
        Engine(id: "N20", name: "N20 – 2.0 R4 (120i–328i, X1/X3 20i/28i)", valvetronic: true, railMax: 200, mafIdle: 2...7, note: nil),
        Engine(id: "N55", name: "N55 – 3.0 R6 (M135i/335i/535i, X3/X5 35i)", valvetronic: true, railMax: 200, mafIdle: 3.9...6, note: nil),
    ]
    public static func named(_ id: String) -> Engine? { all.first { $0.id == id } }
}

public enum Norms {
    public static func check(_ key: String, _ v: Double, in s: Sample, engine: Engine? = nil) -> Norm? {
        let running = (s["rpm"] ?? 0) > 400
        let warm = (s["coolant"] ?? 0) >= 70
        let warmIdle = running && warm && (s["speed"] ?? 0) == 0 && (s["rpm"] ?? 0) < 1100
        if let e = engine {
            switch key {
            case "rail" where e.railMax != nil:
                let max = e.railMax!
                return Norm(range: L("maks. \(Int(max)) bar (\(e.id))", "max \(Int(max)) bar (\(e.id))"), ok: v <= max + 5, note: nil)
            case "map" where e.valvetronic && warmIdle:
                guard let baro = s["baro"] else { return nil }
                return Norm(range: L("blisko ciśnienia otoczenia (Valvetronic)", "near ambient pressure (Valvetronic)"),
                            ok: v >= baro - 25 ? true : nil,
                            note: v >= baro - 25 ? nil : L("przepustnica przymknięta – bywa normalne", "throttle partly closed – can be normal"))
            case "maf" where e.mafIdle != nil && warmIdle:
                let r = e.mafIdle!
                return Norm(range: L("orientacyjnie \(r.lowerBound.formatted())–\(r.upperBound.formatted()) g/s", "roughly \(r.lowerBound.formatted())–\(r.upperBound.formatted()) g/s"),
                            ok: nil, note: L("szacunek, nie dane BMW", "an estimate, not BMW data"))
            default: break
            }
        }
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
