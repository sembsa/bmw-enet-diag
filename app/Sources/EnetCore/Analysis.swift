// Analysis - a log of engine snapshots -> findings, for any petrol engine. Pure: no I/O.
// Each check is skipped when the log lacks its values. Thresholds are rules of thumb, not BMW data.
//   warmUp     coolant reaches operating temperature (thermostat)
//   mixture    total trim (STFT + LTFT) at idle vs 2200-3200 rpm: false air shows high at idle, falling with load
//   airMass    MAF / speed-density ratio, idle vs mid: a drift points at the meter (engine size cancels out)
//   charging   voltage with the engine running
//   idleVacuum manifold pressure at idle
//   lambda     actual vs commanded lambda
import Foundation

public typealias Sample = [String: Double]

public struct Finding: Sendable, Identifiable, Hashable {
    public enum Level: String, Codable, Sendable { case ok, watch, problem, unknown }
    public let check: String, title: L, level: Level, verdict: L
    public let values: [String: Double]
    public let relatedKinds: [String]          // fault kinds this bears on ("engine", "body")
    public var id: String { check }
}

public struct Report: Sendable {
    public let samples: Int, warmSamples: Int, hasMaf: Bool
    public let findings: [Finding]
    public let notes: [L]
}

public enum Analysis {
    public static let warmC = 70.0
    static let trimHigh = 8.0, leakDrop = 5.0

    static func mean(_ xs: [Double?]) -> Double? {
        let v = xs.compactMap { $0 }
        return v.isEmpty ? nil : (v.reduce(0, +) / Double(v.count) * 100).rounded() / 100
    }

    static func bin(_ s: Sample) -> String? {
        let rpm = s["rpm"] ?? 0
        if rpm > 500, rpm < 1000, (s["speed"] ?? 0) == 0 { return "idle" }
        if (2200...3200).contains(rpm) { return "mid" }
        return nil
    }

    /// What a sample counts as in `analyze`: "idle", "mid" or nil (cold, open loop, moving, other revs). For the recording guide.
    public static func phase(_ s: Sample) -> String? {
        guard (s["coolant"] ?? 0) >= warmC, s["fuel_status"].map({ Int($0) & 0x02 != 0 }) ?? true else { return nil }
        return bin(s)
    }

    /// speed-density air mass per litre of displacement, g/s (the litres cancel in the idle/mid ratio)
    static func sdPerLitre(_ s: Sample) -> Double? {
        guard let map = s["map"], let rpm = s["rpm"], let iat = s["iat"] else { return nil }
        return map * 1000 / (287.05 * (iat + 273.15)) * 0.85 * rpm / 120
    }

    static func finding(_ check: String, _ title: L, _ level: Finding.Level, _ verdict: L, _ values: [String: Double],
                        _ kinds: [String] = ["engine"]) -> Finding {
        Finding(check: check, title: title, level: level, verdict: verdict, values: values, relatedKinds: kinds)
    }

    public static func analyze(_ rows: [Sample]) -> Report {
        // closed loop only (fuel system status bit 0x02) when the log has it: open-loop trims mean nothing
        let warm = rows.filter { ($0["coolant"] ?? 0) >= warmC && $0["fuel_status"].map { Int($0) & 0x02 != 0 } ?? true }
        let hasMaf = rows.contains { ($0["maf"] ?? 0) > 0 }
        var f: [Finding] = [], notes: [L] = []
        let idle = warm.filter { bin($0) == "idle" }, mid = warm.filter { bin($0) == "mid" }
        if idle.count < 20 { notes.append(L("Mało próbek na wolnych obrotach: postój 2–3 min na ciepłym silniku.",
                                            "Few samples at idle: 2–3 min at idle with a warm engine.")) }
        if mid.count < 20 { notes.append(L("Mało próbek przy 2200–3200 obr/min: na postoju ~2500 obr/min przez minutę.",
                                           "Few samples at 2200–3200 rpm: hold ~2500 rpm for a minute at standstill.")) }

        let warmUp = L("Rozgrzewanie", "Warm-up")
        if let maxC = rows.compactMap({ $0["coolant"] }).max() {
            if maxC >= 80 {
                f.append(finding("warmUp", warmUp, .ok, L("Silnik osiąga temperaturę roboczą.", "The engine reaches operating temperature."), ["coolant_max": maxC]))
            } else if rows.count > 300 {
                f.append(finding("warmUp", warmUp, .watch, L("Płyn nie doszedł do 80 °C w długim logu – sprawdź termostat.",
                                                             "Coolant stayed below 80 °C in a long log – check the thermostat."), ["coolant_max": maxC]))
            } else {
                f.append(finding("warmUp", warmUp, .unknown, L("Za krótki log, silnik jeszcze zimny.", "Log too short, engine still cold."), ["coolant_max": maxC]))
            }
        }
        guard !warm.isEmpty else {
            return Report(samples: rows.count, warmSamples: 0, hasMaf: hasMaf, findings: f,
                          notes: notes + [L("Silnik nie był rozgrzany (płyn < 70 °C) – nagraj log po rozgrzaniu.",
                                            "The engine was not warm (coolant < 70 °C) – record the log once warm.")])
        }

        func trim(_ rs: [Sample]) -> Double? {
            guard let s = mean(rs.map { $0["stft"] }), let l = mean(rs.map { $0["ltft"] }) else { return nil }
            return ((s + l) * 100).rounded() / 100
        }
        if let ti = trim(idle) {
            let tm = trim(mid)
            var v: [String: Double] = ["trim_idle": ti]
            if let tm { v["trim_mid"] = tm }
            let level: Finding.Level, verdict: L
            if let tm, ti >= trimHigh, ti - tm >= leakDrop {
                (level, verdict) = (.problem, L("Korekty wysokie na wolnych i spadają z obrotami: typowy obraz nieszczelności dolotu (fałszywe powietrze: odma / pokrywa zaworów, wąż, złączka).",
                                                "Trims high at idle and falling with rpm: the typical picture of an intake leak (unmetered air: crankcase vent / valve cover, hose, coupling)."))
            } else if ti >= trimHigh, let tm, tm >= trimHigh {
                (level, verdict) = (.problem, L("Korekty wysokie w całym zakresie: czujnik powietrza zaniża albo brakuje paliwa (ciśnienie, wtryski).",
                                                "Trims high everywhere: the air sensor reads low or fuel is short (pressure, injectors)."))
            } else if ti >= trimHigh {
                (level, verdict) = (.watch, L("Korekty wysokie na wolnych; brak danych z 2500 obr/min, żeby odróżnić nieszczelność od czujnika.",
                                              "Trims high at idle; no 2500 rpm data to tell a leak from a sensor."))
            } else if ti <= -trimHigh || (tm ?? 0) <= -trimHigh {
                (level, verdict) = (.problem, L("Korekty mocno ujemne: za dużo paliwa albo czujnik zawyża powietrze.",
                                                "Trims strongly negative: too much fuel, or the air sensor reads high."))
            } else {
                (level, verdict) = (.ok, L("Korekty paliwa w normie – nie widać fałszywego powietrza.",
                                           "Fuel trims normal – no sign of unmetered air."))
            }
            f.append(finding("mixture", L("Mieszanka (korekty paliwa)", "Mixture (fuel trims)"), level, verdict, v))
        }

        // Valvetronic engines (most BMW petrols) idle with the throttle open: manifold near baro, VE set by valve lift,
        // so neither the vacuum check nor the speed-density model of the air mass meter applies.
        let idleMap = mean(idle.map { $0["map"] }), throttled = (idleMap ?? 0) <= 75
        if hasMaf && throttled {
            func ratio(_ rs: [Sample]) -> Double? { mean(rs.map { s in s["maf"].flatMap { m in sdPerLitre(s).map { m / $0 } } }) }
            if let ri = ratio(idle), let rm = ratio(mid), ri > 0 {
                let drift = (rm / ri * 100).rounded() / 100, off = abs(drift - 1) > 0.2
                f.append(finding("airMass", L("Przepływomierz", "Air mass meter"), off ? .watch : .ok,
                                 off ? L("Odczyt przepływomierza względem modelu zmienia się z obrotami o > 20 % – podejrzany przepływomierz.",
                                         "The meter against the model shifts by > 20 % with rpm – suspect the air mass meter.")
                                     : L("Przepływomierz zgodny z modelem na wolnych i przy 2500 obr/min.",
                                         "The air mass meter agrees with the model at idle and at 2500 rpm."), ["maf_drift": drift]))
            }
        }

        if let v = mean(warm.filter { ($0["rpm"] ?? 0) > 500 }.map { $0["voltage"] }) {
            let verdict = (13.2...15.0).contains(v) ? L("Napięcie przy pracującym silniku w normie.", "Voltage with the engine running is normal.")
                : v < 13.2 ? L("Niskie napięcie przy pracującym silniku – akumulator / alternator do sprawdzenia.", "Low voltage with the engine running – check the battery / alternator.")
                : L("Wysokie napięcie – regulator alternatora do sprawdzenia.", "High voltage – check the alternator's regulator.")
            f.append(finding("charging", L("Ładowanie", "Charging"), (13.2...15.0).contains(v) ? .ok : .watch, verdict, ["voltage": v], ["body", "engine"]))
        }

        if let m = idleMap, !throttled {
            f.append(finding("idleVacuum", L("Podciśnienie na wolnych", "Idle vacuum"), .unknown,
                             L("Kolektor blisko ciśnienia atmosferycznego – silnik z Valvetronic, ten test go nie dotyczy (nie sprawdzano też przepływomierza modelem).",
                               "Manifold near atmospheric – a Valvetronic engine, this check doesn't apply (the air mass meter model check is skipped too)."),
                             ["map_idle": m]))
        } else if let m = idleMap {
            f.append(finding("idleVacuum", L("Podciśnienie na wolnych", "Idle vacuum"), m <= 45 ? .ok : .watch,
                             m <= 45 ? L("Ciśnienie w kolektorze na wolnych typowe.", "Manifold pressure at idle is typical.")
                                     : L("Wysokie ciśnienie w kolektorze na wolnych – możliwa nieszczelność lub dławienie.", "High manifold pressure at idle – a leak or a restriction is possible."),
                             ["map_idle": m]))
        }

        let both = warm.filter { $0["lambda"] != nil && $0["lambda_cmd"] != nil && bin($0) != nil }
        if let d = mean(both.map { abs($0["lambda"]! - $0["lambda_cmd"]!) }) {
            f.append(finding("lambda", L("Sonda lambda", "Lambda"), d <= 0.03 ? .ok : .watch,
                             d <= 0.03 ? L("Lambda trzyma wartość zadaną.", "Lambda follows its target.")
                                       : L("Lambda odbiega od zadanej – sonda lub mieszanka do sprawdzenia.", "Lambda strays from its target – check the sensor or the mixture."),
                             ["lambda_dev": d]))
        }
        return Report(samples: rows.count, warmSamples: warm.count, hasMaf: hasMaf, findings: f, notes: notes)
    }
}
