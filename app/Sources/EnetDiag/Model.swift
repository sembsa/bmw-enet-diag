// Model - the app's state over EnetCore. Every read goes through Car (and so through the allowlist).
import EnetCore
import Foundation
import SwiftUI

func t(_ pl: String, _ en: String) -> String { Lang.current == .pl ? pl : en }

enum Section: String, CaseIterable, Identifiable {
    case overview, faults, live, engine, captures, ai
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: t("Przegląd", "Overview")
        case .faults: t("Błędy", "Faults")
        case .live: t("Na żywo", "Live data")
        case .engine: t("Kontrola silnika", "Engine check")
        case .captures: t("Zapisy", "Captures")
        case .ai: t("Asystent AI", "AI assistant")
        }
    }
    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .faults: "exclamationmark.triangle"
        case .live: "waveform.path.ecg"
        case .engine: "engine.combustion"
        case .captures: "tray.full"
        case .ai: "sparkles"
        }
    }
}

@MainActor final class Model: ObservableObject {
    @Published var section: Section? = {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--section"), i + 1 < a.count { return Section(rawValue: a[i + 1]) }   // screenshots
        return .overview
    }()
    var host: String { UserDefaults.standard.string(forKey: "host") ?? "" }   // Settings
    @Published private(set) var car: Car?
    @Published private(set) var connection = ""
    @Published var busy: String?
    @Published var error: String?

    @Published private(set) var faults: [Fault] = []
    @Published private(set) var faultsAt: Date?
    @Published private(set) var probe: Probe?

    @Published private(set) var live: [Sample] = []
    @Published private(set) var misfires: [Misfire] = []
    @Published private(set) var identity: Identity?
    @Published private(set) var liveOn = false
    private var liveTask: Task<Void, Never>?

    @Published private(set) var recording: Captures.LogWriter?
    @Published private(set) var recorded: [Sample] = []
    @Published private(set) var report: Report?
    @Published private(set) var reportName: String?
    @Published private(set) var captures: [URL] = Captures.list()

    // engine check: get ready -> idle -> 2500 rpm -> result
    enum CheckStep: Int { case prepare, idle, mid, result }
    static let idleNeeded = 120, midNeeded = 50
    @Published private(set) var idleCount = 0                      // samples the analysis will use, per step
    @Published private(set) var midCount = 0
    @Published var newCheck = false                                // the owner asked for a new check while a result exists
    private var seedStep: CheckStep?                               // screenshots only
    private(set) var frozen = false                                // screenshots only: no polling
    var checkStep: CheckStep {
        if let seedStep { return seedStep }
        if recording != nil { return idleCount < Model.idleNeeded ? .idle : .mid }
        return report != nil && !newCheck ? .result : .prepare
    }

    var connected: Bool { car != nil }
    var isDemo: Bool { connection == "DEMO" }

    /// The simulated car: faults, moving engine values and a ready engine check.
    func connectDemo() async {
        await disconnect()
        car = Car.demo()
        connection = "DEMO"
        report = Analysis.analyze(Car.demoLog())
        reportName = t("demo – log 4 min", "demo – 4 min log")
        newCheck = false
        await readFaults()
        await firstSnapshot()
    }

    // MARK: connection

    func connect() async {
        guard busy == nil else { return }
        await disconnect()                                   // never two links to the gateway
        await run(t("Łączenie z bramką ENET…", "Connecting to the ENET gateway…")) {
            let c: Car
            if let i = CommandLine.arguments.firstIndex(of: "--replay"), i + 1 < CommandLine.arguments.count {
                c = try Car(replay: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            } else {
                c = try await Car.connect(host: self.host.isEmpty ? nil : self.host)
            }
            self.car = c
            self.connection = c.connection
        }
        if connected { await readFaults(); await firstSnapshot() }
    }

    /// One reading at connect: the overview shows the odometer, the live page has values at once.
    private func firstSnapshot() async {
        guard let car else { return }
        identity = try? await car.identity()
        if let s = try? await car.snapshot() { live = [s] }
    }

    /// A question for the owner's AI: the type code and year (no serial number).
    func modelQuestion() -> String {
        guard let id = identity, let vin = id.vin else { return "" }
        let partial = String(vin.prefix(11)) + "******"
        return t("Moje BMW: VIN \(partial), kod typu \(id.typeCode ?? "?"), rok modelowy \(id.modelYear.map(String.init) ?? "?"), sterownik silnika \(id.ecuName ?? "?"). Jaki to model, nadwozie i silnik?",
                 "My BMW: VIN \(partial), type code \(id.typeCode ?? "?"), model year \(id.modelYear.map(String.init) ?? "?"), engine unit \(id.ecuName ?? "?"). Which model, body and engine is it?")
    }

    /// Disconnect pressed: the Overview's start screen makes "not connected" plain (faults already read stay in Faults).
    func disconnectByOwner() async {
        await disconnect()
        section = .overview
    }

    /// The window shows "not connected" first; the socket is closed after, so a stuck link cannot hold the UI.
    func disconnect() async {
        stopLive()
        stopRecording()
        let old = car
        car = nil
        identity = nil
        connection = ""
        misfires = []
        await old?.close()
    }

    // MARK: reads

    func readFaults() async {
        guard let car else { return }
        await run(t("Czytam pamięć błędów wszystkich sterowników…", "Reading every control unit's fault memory…")) {
            self.faults = try await car.faults()
            self.faultsAt = Date()
        }
    }

    func runProbe() async {
        guard let car else { return }
        await run(t("Pełny odczyt silnika…", "Reading everything from the engine…")) {
            let p = try await car.probe()
            try Captures.save(p)
            self.probe = p
            self.faults = p.faults
            self.faultsAt = Date()
            self.captures = Captures.list()
        }
    }

    func startLive() {
        guard let car, !liveOn, !frozen else { return }
        liveOn = true
        liveTask = Task {
            while !Task.isCancelled {
                do {
                    let s = try await car.snapshot()
                    let mis = live.count % 20 == 0 ? try? await car.misfires() : nil
                    if Task.isCancelled { break }            // stopped or disconnected meanwhile: these readings are stale
                    if let mis { misfires = mis }
                    live.append(s)
                    if live.count > 600 { live.removeFirst(live.count - 600) }
                    if let w = recording { w.write(s); recorded.append(s); tally(s) }
                } catch {
                    if Task.isCancelled || self.car !== car { break }   // the owner disconnected: not an error, and not ours to close
                    self.error = "\(error)"
                    await disconnect()                       // the link is gone: say so, don't pretend
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if !Task.isCancelled { liveOn = false }          // a cancelled loop must not switch off its successor
        }
    }

    func stopLive() {
        liveTask?.cancel()
        liveTask = nil
        liveOn = false
    }

    // MARK: engine check

    func startRecording() {
        do {
            recording = try Captures.LogWriter()
            recorded = []
            idleCount = 0; midCount = 0
            startLive()                                  // the last result stays until this one is finished (Cancel returns to it)
        } catch { self.error = "\(error)" }
    }

    /// Step 2 counts idle samples; step 3 starts once step 2 is full and counts 2200-3200 rpm samples; then the check ends itself.
    private func tally(_ s: Sample) {
        let p = Analysis.phase(s)
        if idleCount < Model.idleNeeded { if p == "idle" { idleCount += 1 } }
        else if p == "mid" { midCount += 1 }
        if midCount >= Model.midNeeded { stopRecording() }
    }

    /// Drops the recording and its file; the previous result (if any) stays.
    func cancelRecording() {
        guard let w = recording else { return }
        w.close()
        try? FileManager.default.removeItem(at: w.url)
        recording = nil
        recorded = []
    }

    /// Screenshots (`--engine-step prepare|cold|idle|low|mid`): one step with demo values, no polling, no log file.
    func seed(_ step: String) {
        stopLive()
        let log = Car.demoLog()
        var s = log[step == "mid" ? 70 : 0]
        if step == "cold" { s["coolant"] = 48 }
        live = [s]; frozen = true; newCheck = true
        if step == "idle" { seedStep = .idle; idleCount = 45 }
        if step == "low" || step == "mid" { seedStep = .mid; idleCount = Model.idleNeeded; midCount = 18 }
    }

    func stopRecording() {
        guard let w = recording else { return }
        w.close()
        recording = nil
        newCheck = false
        report = Analysis.analyze(recorded)
        reportName = w.url.lastPathComponent
        captures = Captures.list()
    }

    func analyze(_ url: URL) {
        do {
            report = Analysis.analyze(try Captures.readLog(url))
            reportName = url.lastPathComponent
            newCheck = false
            section = .engine
        } catch { self.error = "\(error)" }
    }

    func openProbe(_ url: URL) async {
        await disconnect()
        await run(t("Otwieram zapis…", "Opening the capture…")) {
            let c = try Car(replay: url)
            self.car = c
            self.connection = c.connection
            self.faults = try await c.faults()
            self.faultsAt = Date()
            self.identity = try? await c.identity()
            self.section = .faults
        }
    }

    func refreshCaptures() { captures = Captures.list() }

    /// Faults as plain text for the owner's AI.
    func faultsText() -> String {
        var s = t("Błędy z mojego BMW (adres sterownika, kod, status):\n", "Faults from my BMW (unit address, code, status):\n")
        for f in faults {
            s += "\(f.address) \(f.unit) \(f.code) \(f.active ? "active" : f.pending ? "pending" : "stored")"
            if let h = f.hint { s += " – \(h.title.text)" }
            s += "\n"
        }
        return s + t("Wyjaśnij je, uszereguj od najważniejszego i powiedz, co sprawdzić najpierw.",
                     "Explain them, rank them by importance and tell me what to check first.")
    }

    /// The engine-check result as plain text for the owner's AI (or a mechanic).
    func reportText() -> String {
        guard let r = report else { return "" }
        var s = t("Kontrola silnika mojego BMW (próbek \(r.samples), na ciepłym silniku \(r.warmSamples)):\n",
                  "Engine check of my BMW (\(r.samples) samples, \(r.warmSamples) with the engine warm):\n")
        for f in r.findings {
            s += "[\(f.level.rawValue)] \(f.title.text): \(f.verdict.text)"
            s += " (" + f.values.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + ")\n"
        }
        for n in r.notes { s += "! \(n.text)\n" }
        let codes = faults.filter { $0.kind == "engine" }.map(\.code)
        if !codes.isEmpty { s += t("Błędy silnika w pamięci: ", "Engine faults in memory: ") + codes.joined(separator: ", ") + "\n" }
        return s + t("Wyjaśnij wynik prostym językiem i powiedz, co sprawdzić najpierw.", "Explain the result in plain language and tell me what to check first.")
    }

    private func run(_ what: String, _ body: @escaping () async throws -> Void) async {
        guard busy == nil else { return }                  // one operation at a time (no double Connect)
        busy = what
        error = nil
        let had = car
        do { try await body() } catch {
            if had != nil, car !== had { busy = nil; return }  // the owner disconnected during the read: not an error
            self.error = "\(error)"
            if error is LinkError, car != nil, !isDemo { busy = nil; await disconnect() }
        }
        busy = nil
    }
}
