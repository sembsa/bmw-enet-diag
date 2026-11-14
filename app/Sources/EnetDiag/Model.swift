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
    @Published private(set) var liveOn = false
    private var liveTask: Task<Void, Never>?

    @Published private(set) var recording: Captures.LogWriter?
    @Published private(set) var recorded: [Sample] = []
    @Published private(set) var report: Report?
    @Published private(set) var reportName: String?
    @Published private(set) var captures: [URL] = Captures.list()

    var connected: Bool { car != nil }
    var isDemo: Bool { connection == "DEMO" }

    /// The simulated car: faults, moving engine values and a ready engine check.
    func connectDemo() async {
        await disconnect()
        car = Car.demo()
        connection = "DEMO"
        report = Analysis.analyze(Car.demoLog())
        reportName = t("demo – log 4 min", "demo – 4 min log")
        await readFaults()
        await firstSnapshot()
    }

    // MARK: connection

    func connect() async {
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
        if let car, let s = try? await car.snapshot() { live = [s] }
    }

    func disconnect() async {
        stopLive()
        stopRecording()
        await car?.close()
        car = nil
        connection = ""
        misfires = []
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
        guard let car, !liveOn else { return }
        liveOn = true
        liveTask = Task {
            while !Task.isCancelled {
                do {
                    let s = try await car.snapshot()
                    if live.count % 20 == 0 { misfires = (try? await car.misfires()) ?? misfires }
                    live.append(s)
                    if live.count > 600 { live.removeFirst(live.count - 600) }
                    if let w = recording { w.write(s); recorded.append(s) }
                } catch {
                    self.error = "\(error)"
                    await disconnect()                       // the link is gone: say so, don't pretend
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            liveOn = false
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
            report = nil
            startLive()
        } catch { self.error = "\(error)" }
    }

    func stopRecording() {
        guard let w = recording else { return }
        w.close()
        recording = nil
        report = Analysis.analyze(recorded)
        reportName = w.url.lastPathComponent
        captures = Captures.list()
    }

    func analyze(_ url: URL) {
        do {
            report = Analysis.analyze(try Captures.readLog(url))
            reportName = url.lastPathComponent
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
            self.section = .faults
        }
    }

    func refreshCaptures() { captures = Captures.list() }

    /// Faults as plain text for the owner's AI.
    func faultsText() -> String {
        var s = t("Błędy z mojego BMW (adres sterownika, kod, status):\n", "Faults from my BMW (unit address, code, status):\n")
        for f in faults {
            s += "\(f.address) \(f.unit) \(f.code) \(f.active ? "ACTIVE" : f.pending ? "PENDING" : "STORED")"
            if let h = f.hint { s += " – \(h.title.text)" }
            s += "\n"
        }
        return s + t("Wyjaśnij je, uszereguj od najważniejszego i powiedz, co sprawdzić najpierw.",
                     "Explain them, rank them by importance and tell me what to check first.")
    }

    private func run(_ what: String, _ body: @escaping () async throws -> Void) async {
        guard busy == nil else { return }                  // one operation at a time (no double Connect)
        busy = what
        error = nil
        do { try await body() } catch {
            self.error = "\(error)"
            if error is LinkError, car != nil, !isDemo { busy = nil; await disconnect() }
        }
        busy = nil
    }
}
