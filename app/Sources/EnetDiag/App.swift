// EnetDiag - a window over the read-only Python core (enetdiag): faults of every control unit with hints,
// and the 101F01 analysis of a log. It runs `python3 -m enetdiag ... --json`, so the allowlist stays in one place;
// nothing here sends anything to the car by itself. Clearing faults: the Store's Fault Scanner.
import SwiftUI
import UniformTypeIdentifiers

struct Hint: Decodable { let severity: String; let title: String; let what: String; let check: String }
struct Fault: Decodable, Identifiable {
    let unit: String; let address: String; let code: String
    let active: Bool; let pending: Bool; let hint: Hint?
    var id: String { address + code }
}

enum Core {
    /// The enetdiag folder: ENETDIAG_HOME, else the repo this app was built in.
    static var home: URL {
        if let h = ProcessInfo.processInfo.environment["ENETDIAG_HOME"] { return URL(fileURLWithPath: h) }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func run(_ args: [String]) async throws -> Data {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["python3", "-m", "enetdiag"] + args
            p.currentDirectoryURL = home
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                throw NSError(domain: "enetdiag", code: Int(p.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: msg.split(separator: "\n").last.map(String.init) ?? "błąd"])
            }
            return data
        }.value
    }
}

@MainActor final class Model: ObservableObject {
    @Published var host = ""
    @Published var faults: [Fault] = []
    @Published var analysis = ""
    @Published var status = "Podłącz kabel ENET, włącz zapłon."
    @Published var busy = false

    private var hostArgs: [String] { host.isEmpty ? [] : ["--host", host] }

    func readFaults() async {
        busy = true; defer { busy = false }
        status = "Czytam pamięć błędów wszystkich sterowników…"
        do {
            faults = try JSONDecoder().decode([Fault].self, from: try await Core.run(["faults", "--json"] + hostArgs))
            status = faults.isEmpty ? "Brak błędów." : "Błędów: \(faults.count) (aktywnych: \(faults.filter(\.active).count))."
        } catch { status = error.localizedDescription }
    }

    func probe() async {
        busy = true; defer { busy = false }
        status = "Probe: wszystko z silnika do pliku…"
        do {
            let d = try await Core.run(["probe", "--json"] + hostArgs)
            let o = try JSONSerialization.jsonObject(with: d) as? [String: Any]
            status = "Zapisano \(o?["file"] as? String ?? "?") · przepływomierz: \((o?["has_maf"] as? Bool) == true ? "jest" : "BRAK")"
        } catch { status = error.localizedDescription }
    }

    func analyze(_ url: URL) async {
        busy = true; defer { busy = false }
        do { analysis = String(data: try await Core.run(["analyze", url.path]), encoding: .utf8) ?? "" }
        catch { analysis = error.localizedDescription }
    }
}

struct FaultRow: View {
    let f: Fault
    var color: Color {
        switch f.hint?.severity { case "service": .red; case "watch": .orange; case "info": .secondary; default: .blue }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(f.active ? "ACTIVE" : f.pending ? "PENDING" : "STORED")
                    .font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(f.active ? Color.red : f.pending ? .orange : .gray).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(f.code).font(.system(.body, design: .monospaced).bold())
                Text(f.unit).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(color).frame(width: 10, height: 10)
            }
            if let h = f.hint {
                Text(h.title).bold()
                Text(h.what).font(.callout)
                Text("Sprawdź: " + h.check).font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Brak naszego opisu – zapytaj swoje AI (MCP: read_faults).").font(.callout).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

struct ContentView: View {
    @StateObject var m = Model()
    @State var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("IP bramki (puste = szukaj)", text: $m.host).frame(width: 200)
                Button("Odczytaj błędy") { Task { await m.readFaults() } }.keyboardShortcut("r")
                Button("Probe silnika") { Task { await m.probe() } }
                Button("Analizuj log…") { picking = true }
                if m.busy { ProgressView().controlSize(.small) }
                Spacer()
                Text("Tylko odczyt · kasowanie: Fault Scanner w Store").font(.caption).foregroundStyle(.secondary)
            }
            Text(m.status).foregroundStyle(.secondary)
            List(m.faults) { FaultRow(f: $0) }
            if !m.analysis.isEmpty {
                GroupBox("Analiza 101F01") {
                    ScrollView { Text(m.analysis).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160)
                }
            }
        }
        .padding()
        .frame(minWidth: 820, minHeight: 520)
        .disabled(m.busy)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText]) { r in
            if case .success(let url) = r { Task { await m.analyze(url) } }
        }
    }
}

@main struct EnetDiagApp: App {
    var body: some Scene { WindowGroup("BMW ENET Diag") { ContentView() } }
}
