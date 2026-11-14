// Views - the window: sidebar, toolbar, and one page per section.
import AppKit
import Charts
import EnetCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject var m: Model
    @AppStorage("lang") var lang = ""

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $m.section) { s in
                Label(s.title, systemImage: s.symbol)
                    .badge(s == .faults ? m.faults.filter(\.active).count : 0)
                    .tag(Optional(s))
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            Group {
                switch m.section ?? .overview {
                case .overview: OverviewPage()
                case .faults: FaultsPage()
                case .live: LivePage()
                case .engine: EnginePage()
                case .captures: CapturesPage()
                case .ai: AIPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar { Toolbar() }
        .navigationTitle("")
        .overlay(alignment: .bottom) { StatusBanner() }
        .id(lang)                      // a language change redraws everything
        .task {
            if CommandLine.arguments.contains("--demo") { await m.connectDemo() }
            else if CommandLine.arguments.contains("--replay"), !m.connected { await m.connect() }
        }
    }
}

struct SidebarFooter: View {
    @EnvironmentObject var m: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stripe(height: 3).frame(width: 48)
            Label(t("Tylko odczyt", "Read-only"), systemImage: "lock.shield").font(.caption.weight(.semibold))
            Text(t("Kasowanie błędów: Fault Scanner w MGU Store lub warsztat.", "Clearing faults: Fault Scanner in the MGU Store, or a workshop."))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

struct Toolbar: ToolbarContent {
    @EnvironmentObject var m: Model
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 6) {
                Circle().fill(m.connected ? .green : .secondary.opacity(0.4)).frame(width: 8, height: 8)
                if m.isDemo { Pill(text: "DEMO", color: .orange) } else {
                    Text(m.connected ? m.connection : t("Niepołączono", "Not connected"))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if m.busy != nil { ProgressView().controlSize(.small) }
            if !m.connected {
                TextField(t("IP bramki (auto)", "Gateway IP (auto)"), text: $m.host).frame(width: 150).textFieldStyle(.roundedBorder)
                Button { Task { await m.connectDemo() } } label: { Label("Demo", systemImage: "play.rectangle") }
                    .help(t("Symulowane auto", "A simulated car"))
                Button { Task { await m.connect() } } label: { Label(t("Połącz", "Connect"), systemImage: "cable.connector") }
                    .help(t("Kabel ENET w gnieździe OBD, zapłon włączony", "ENET cable in the OBD port, ignition on"))
            } else {
                Button { Task { await m.readFaults() } } label: { Label(t("Odczytaj błędy", "Read faults"), systemImage: "arrow.clockwise") }
                Button { Task { await m.disconnect() } } label: { Label(t("Rozłącz", "Disconnect"), systemImage: "eject") }
            }
        }
    }
}

struct StatusBanner: View {
    @EnvironmentObject var m: Model
    var body: some View {
        Group {
            if let e = m.error {
                Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.white)
                    .padding(10).background(Theme.red, in: RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { m.error = nil }
            } else if let b = m.busy {
                Label(b, systemImage: "antenna.radiowaves.left.and.right").padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.bottom, 14)
        .animation(.easeInOut, value: m.busy)
    }
}

struct NotConnected: View {
    @EnvironmentObject var m: Model
    var body: some View {
        ContentUnavailableView {
            Label(t("Podłącz auto", "Connect the car"), systemImage: "cable.connector")
        } description: {
            Text(t("Kabel ENET do gniazda OBD i do Maca, zapłon włączony. Bramka zostanie znaleziona sama, albo wpisz jej IP.",
                   "ENET cable into the OBD port and the Mac, ignition on. The gateway is found by itself, or enter its IP."))
        } actions: {
            HStack {
                Button(t("Połącz", "Connect")) { Task { await m.connect() } }.buttonStyle(.borderedProminent).tint(Theme.blue)
                Button(t("Wypróbuj demo", "Try the demo")) { Task { await m.connectDemo() } }
            }
        }
    }
}

// MARK: overview

struct OverviewPage: View {
    @EnvironmentObject var m: Model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Header(title: "BMW ENET Diag", subtitle: t("Diagnostyka tylko do odczytu przez kabel ENET", "Read-only diagnostics over the ENET cable"))
                if m.connected { Dashboard() } else { Welcome() }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }
}

/// Not connected: what you need, and the two ways in.
struct Welcome: View {
    @EnvironmentObject var m: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 28) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [Theme.navy, Theme.blue.opacity(0.85)], startPoint: .bottomLeading, endPoint: .topTrailing))
                    Image(systemName: "car.side.fill").font(.system(size: 54, weight: .regular)).foregroundStyle(.white)
                }
                .frame(width: 150, height: 110)
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("Podłącz auto, żeby zacząć", "Connect your car to start")).font(.title.weight(.semibold))
                    Text(t("Aplikacja odczyta błędy ze wszystkich sterowników, dane silnika na żywo i zrobi kontrolę silnika. Niczego nie zapisuje ani nie kasuje.",
                           "The app reads every control unit's faults and live engine data, and runs an engine check. It writes and clears nothing."))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                Step(n: 1, symbol: "cable.connector", text: t("Kabel ENET do gniazda OBD (pod kierownicą) i do Maca", "ENET cable into the OBD port (under the wheel) and the Mac"))
                Step(n: 2, symbol: "key.fill", text: t("Zapłon włączony; do danych na żywo – silnik pracuje", "Ignition on; for live data, the engine running"))
                Step(n: 3, symbol: "antenna.radiowaves.left.and.right", text: t("Połącz – bramka zostanie znaleziona sama", "Connect – the gateway is found by itself"))
            }
            HStack(spacing: 12) {
                Button { Task { await m.connect() } } label: { Label(t("Połącz z autem", "Connect to the car"), systemImage: "cable.connector").padding(.horizontal, 6) }
                    .buttonStyle(.borderedProminent).tint(Theme.blue)
                Button { Task { await m.connectDemo() } } label: { Label(t("Wypróbuj demo", "Try the demo"), systemImage: "play.rectangle").padding(.horizontal, 6) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
            Text(t("Demo pokazuje symulowane auto: kilka błędów, zmieniające się wartości silnika i gotową kontrolę silnika.",
                   "The demo shows a simulated car: a few faults, moving engine values and a finished engine check."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct Step: View {
    let n: Int, symbol: String, text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(n)").font(.headline.monospacedDigit()).frame(width: 26, height: 26).background(Theme.blue.opacity(0.18), in: Circle()).foregroundStyle(Theme.blue)
                Spacer()
                Image(systemName: symbol).font(.title3).foregroundStyle(.secondary)
            }
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
    }
}

/// One number with a caption, all the same size.
struct Stat: View {
    let title: String, symbol: String, value: String, caption: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 128, maxHeight: 128, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
    }
}

struct Dashboard: View {
    @EnvironmentObject var m: Model
    var body: some View {
        let active = m.faults.filter(\.active).count
        let workshop = m.faults.filter { $0.hint?.severity == .workshop }.count
        let levels = m.report?.findings.map(\.level) ?? []
        let worst: Finding.Level? = m.report == nil ? nil : levels.contains(.problem) ? .problem : levels.contains(.watch) ? .watch : .ok
        VStack(alignment: .leading, spacing: 20) {
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    Stat(title: t("Połączenie", "Connection"), symbol: "cable.connector", value: m.isDemo ? "DEMO" : t("Połączono", "Connected"),
                         caption: m.isDemo ? t("symulowane auto", "simulated car") : m.connection, color: m.isDemo ? .orange : .green)
                    Stat(title: t("Błędy", "Faults"), symbol: "exclamationmark.triangle", value: "\(m.faults.count)",
                         caption: t("aktywnych: ", "active: ") + "\(active)", color: active > 0 ? Theme.red : .primary)
                    Stat(title: t("Do warsztatu", "For a workshop"), symbol: "wrench.and.screwdriver", value: "\(workshop)",
                         caption: t("wg naszych podpowiedzi", "by our hints"), color: workshop > 0 ? Theme.red : .green)
                    Stat(title: t("Kontrola silnika", "Engine check"), symbol: "engine.combustion",
                         value: worst.map { $0 == .ok ? t("Bez uwag", "All good") : $0 == .watch ? t("Uwagi", "Notes") : t("Problem", "Problem") } ?? "–",
                         caption: m.reportName ?? t("nagraj log na ciepłym silniku", "record a log, engine warm"), color: worst?.color ?? .secondary)
                }
            }
            HStack(spacing: 10) {
                Button { m.section = .faults } label: { Label(t("Zobacz błędy", "View faults"), systemImage: "list.bullet.rectangle") }
                Button { m.section = .live; m.startLive() } label: { Label(t("Dane na żywo", "Live data"), systemImage: "waveform.path.ecg") }
                Button { m.section = .engine } label: { Label(t("Kontrola silnika", "Engine check"), systemImage: "engine.combustion") }
                Button { Task { await m.runProbe() } } label: { Label(t("Pełny odczyt", "Full read"), systemImage: "doc.text.magnifyingglass") }
            }
            .controlSize(.large)
            if let top = m.faults.first(where: { $0.active }) {
                Card(title: t("Najważniejsze teraz", "Most important now"), symbol: "flag.fill") {
                    HStack(alignment: .top, spacing: 12) {
                        Pill(text: top.statusText, color: top.statusColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(top.code) · \(top.unit)").font(.headline.monospaced())
                            Text(top.hint?.title.text ?? t("Brak naszego opisu – zapytaj asystenta AI", "No note of ours – ask your AI assistant"))
                            if let h = top.hint { Text(h.check.text).font(.callout).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if let p = m.probe {
                Card(title: t("Ostatni pełny odczyt", "Last full read"), symbol: "doc.text.magnifyingglass") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow { Text("VIN").foregroundStyle(.secondary); Text(p.vin ?? "–").textSelection(.enabled) }
                        GridRow { Text(t("Przepływomierz", "Air mass meter")).foregroundStyle(.secondary); Text(p.hasMaf ? t("jest", "fitted") : t("brak (model w sterowniku)", "none (the unit's model)")) }
                        GridRow { Text(t("Kody OBD", "OBD codes")).foregroundStyle(.secondary); Text((p.obdStored + p.obdPending).joined(separator: ", ").ifEmpty("–")) }
                        GridRow { Text(t("Wartości", "Values")).foregroundStyle(.secondary); Text(p.knownValues.joined(separator: ", ")).lineLimit(2) }
                    }
                }
            }
        }
    }
}

extension String { func ifEmpty(_ s: String) -> String { isEmpty ? s : self } }

// MARK: faults

struct FaultsPage: View {
    @EnvironmentObject var m: Model
    @State var selection: Fault.ID?
    @State var search = ""
    @State var onlyActive = false

    var shown: [Fault] {
        m.faults.filter { (!onlyActive || $0.active) &&
            (search.isEmpty || "\($0.code) \($0.unit) \($0.hint?.title.text ?? "")".localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        if !m.connected && m.faults.isEmpty { NotConnected() } else {
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Header(title: t("Błędy", "Faults"), subtitle: t("Pamięć błędów wszystkich sterowników", "Every control unit's fault memory"))
                        Spacer()
                        Toggle(t("Tylko aktywne", "Active only"), isOn: $onlyActive).toggleStyle(.switch).controlSize(.small)
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.faultsText(), forType: .string) } label: {
                            Label(t("Kopiuj dla AI", "Copy for AI"), systemImage: "doc.on.doc")
                        }.disabled(m.faults.isEmpty)
                    }
                    .padding([.horizontal, .top], 24).padding(.bottom, 12)
                    if m.faults.isEmpty {
                        ContentUnavailableView(t("Brak błędów", "No faults"), systemImage: "checkmark.seal",
                                               description: Text(t("Żaden sterownik nie zgłasza błędów.", "No control unit reports a fault.")))
                    } else {
                        Table(shown, selection: $selection) {
                            TableColumn(t("Status", "Status")) { f in Pill(text: f.statusText, color: f.statusColor) }.width(78)
                            TableColumn(t("Kod", "Code")) { f in Text(f.code).font(.body.monospaced().weight(.semibold)) }.width(72)
                            TableColumn(t("Sterownik", "Control unit")) { f in Label(f.unit, systemImage: f.kindSymbol).lineLimit(1) }.width(min: 110, ideal: 140, max: 170)
                            TableColumn(t("Opis", "Description")) { f in
                                if let h = f.hint {
                                    HStack { Image(systemName: h.severity.symbol).foregroundStyle(h.severity.color); Text(h.title.text) }
                                } else {
                                    Text(t("Brak opisu – zapytaj asystenta AI", "No note – ask your AI assistant")).foregroundStyle(.secondary)
                                }
                            }.width(min: 160, ideal: 320)
                        }
                    }
                }
                .frame(minWidth: 480, maxWidth: .infinity)
                FaultInspector(fault: m.faults.first { $0.id == selection })
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
            }
            .searchable(text: $search, prompt: t("Szukaj kodu lub sterownika", "Search code or unit"))
        }
    }
}

struct FaultInspector: View {
    @EnvironmentObject var m: Model
    let fault: Fault?
    var body: some View {
        ScrollView {
            if let f = fault {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Pill(text: f.statusText, color: f.statusColor); Spacer(); Text("0x" + f.address).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    Text(f.code).font(.system(size: 30, weight: .bold, design: .monospaced))
                    Label(f.unit, systemImage: f.kindSymbol).foregroundStyle(.secondary)
                    Divider()
                    if let h = f.hint {
                        Label(h.severity.label, systemImage: h.severity.symbol).font(.headline).foregroundStyle(h.severity.color)
                        Text(h.title.text).font(.title3.weight(.semibold))
                        Text(h.what.text)
                        Text(t("Co sprawdzić", "What to check")).font(.headline).padding(.top, 4)
                        Text(h.check.text)
                        if !h.sources.isEmpty {
                            Text(t("Źródła", "Sources")).font(.headline).padding(.top, 4)
                            ForEach(h.sources, id: \.self) { s in
                                if let u = URL(string: s) { Link(u.host ?? s, destination: u).font(.caption) }
                            }
                        }
                    } else {
                        Text(t("Nie mamy jeszcze opisu tego kodu. Zapytaj swojego asystenta AI (sekcja Asystent AI) albo skopiuj listę przyciskiem „Kopiuj dla AI”.",
                               "We have no note for this code yet. Ask your AI assistant (AI assistant section) or copy the list with “Copy for AI”."))
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    Label(t("Kasowanie: Fault Scanner w MGU Store albo warsztat. Ta aplikacja niczego nie kasuje.",
                            "Clearing: Fault Scanner in the MGU Store, or a workshop. This app clears nothing."), systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            } else {
                ContentUnavailableView(t("Wybierz błąd", "Select a fault"), systemImage: "sidebar.right")
                    .padding(.top, 80)
            }
        }
        .background(.background.secondary)
    }
}

// MARK: live

struct Tile: View {
    let label: String, value: Double?, unit: String, digits: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map { String(format: "%.\(digits)f", $0) } ?? "–").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct LivePage: View {
    @EnvironmentObject var m: Model
    let keys = ["rpm", "coolant", "iat", "map", "maf", "stft", "ltft", "lambda", "lambda_cmd", "throttle", "load", "voltage"]

    var body: some View {
        if !m.connected { NotConnected() } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Header(title: t("Na żywo", "Live data"), subtitle: t("Wartości ze sterownika silnika (OBD), co pół sekundy", "Engine unit values (OBD), every half second"))
                        Spacer()
                        Button { m.liveOn ? m.stopLive() : m.startLive() } label: {
                            Label(m.liveOn ? t("Zatrzymaj", "Stop") : t("Start", "Start"), systemImage: m.liveOn ? "pause.fill" : "play.fill")
                        }.buttonStyle(.borderedProminent).tint(m.liveOn ? .secondary : Theme.blue).controlSize(.large)
                    }
                    let last = m.live.last ?? [:]
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(keys, id: \.self) { k in
                            if let p = Pids.byKey[k] {
                                Tile(label: Lang.current == .pl ? p.label : k.uppercased(), value: last[k], unit: p.unit,
                                     digits: ["lambda", "lambda_cmd", "voltage"].contains(k) ? 2 : k == "stft" || k == "ltft" ? 1 : 0)
                            }
                        }
                    }
                    Card(title: t("Korekty paliwa", "Fuel trims"), symbol: "chart.xyaxis.line") {
                        let start = m.live.first?["t"] ?? 0
                        Chart {
                            ForEach(Array(m.live.enumerated()), id: \.offset) { _, s in
                                if let x = s["t"], let v = s["stft"] { LineMark(x: .value("s", x - start), y: .value("%", v), series: .value("", "STFT")).foregroundStyle(Theme.lightBlue) }
                                if let x = s["t"], let v = s["ltft"] { LineMark(x: .value("s", x - start), y: .value("%", v), series: .value("", "LTFT")).foregroundStyle(Theme.red) }
                            }
                            RuleMark(y: .value("0", 0)).foregroundStyle(.secondary.opacity(0.4))
                        }
                        .chartYScale(domain: -25...25)
                        .frame(height: 200)
                        HStack(spacing: 16) {
                            Label("STFT", systemImage: "circle.fill").foregroundStyle(Theme.lightBlue)
                            Label("LTFT", systemImage: "circle.fill").foregroundStyle(Theme.red)
                        }.font(.caption)
                    }
                    Label(t("Nie obsługuj komputera w czasie jazdy.", "Don't operate the computer while driving."), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(24)
            }
        }
    }
}

// MARK: engine check

struct EnginePage: View {
    @EnvironmentObject var m: Model

    var steps: [(String, Bool)] {
        let warm = m.recorded.contains { ($0["coolant"] ?? 0) >= 70 }
        let idle = m.recorded.filter { ($0["coolant"] ?? 0) >= 70 && (500..<1000).contains($0["rpm"] ?? 0) }.count
        let mid = m.recorded.filter { ($0["coolant"] ?? 0) >= 70 && (2200...3200).contains($0["rpm"] ?? 0) }.count
        return [(t("Silnik rozgrzany (płyn ≥ 70 °C)", "Engine warm (coolant ≥ 70 °C)"), warm),
                (t("2–3 min na wolnych obrotach", "2–3 min at idle") + " (\(idle)/240)", idle >= 240),
                (t("1 min przy ~2500 obr/min, na postoju", "1 min at ~2500 rpm, at standstill") + " (\(mid)/100)", mid >= 100)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: t("Kontrola silnika", "Engine check"),
                       subtitle: t("Prowadzony log i analiza: mieszanka, nieszczelności, przepływomierz, ładowanie, lambda",
                                   "A guided log and its analysis: mixture, leaks, air mass meter, charging, lambda"))
                if m.connected {
                    Card(title: t("Nagranie", "Recording"), symbol: "record.circle") {
                        ForEach(steps, id: \.0) { s in
                            Label(s.0, systemImage: s.1 ? "checkmark.circle.fill" : "circle").foregroundStyle(s.1 ? .green : .primary)
                        }
                        HStack {
                            if m.recording == nil {
                                Button { m.startRecording() } label: { Label(t("Nagrywaj", "Record"), systemImage: "record.circle") }
                                    .buttonStyle(.borderedProminent).tint(Theme.red)
                            } else {
                                Button { m.stopRecording() } label: { Label(t("Zakończ i analizuj", "Stop and analyse"), systemImage: "stop.fill") }
                                    .buttonStyle(.borderedProminent).tint(Theme.blue)
                                Text(t("Próbek: ", "Samples: ") + "\(m.recorded.count)").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        Text(t("Na postoju. Nie obsługuj komputera w czasie jazdy.", "At standstill. Don't operate the computer while driving."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let r = m.report {
                    Text((m.reportName ?? "") + " · " + t("próbek ", "samples ") + "\(r.samples), " + t("na ciepło ", "warm ") + "\(r.warmSamples)")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(r.findings) { f in
                        Card {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: f.level.symbol).font(.title2).foregroundStyle(f.level.color)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(f.title.text).font(.headline)
                                    Text(f.verdict.text)
                                    Text(f.values.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.2f", $0.value))" }.joined(separator: " · "))
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    ForEach(r.notes, id: \.self) { n in Label(n.text, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                    let related = m.faults.filter { f in r.findings.contains { $0.level != .ok && $0.relatedKinds.contains(f.kind) } }
                    if !related.isEmpty {
                        Card(title: t("Powiązane błędy", "Related faults"), symbol: "link") {
                            ForEach(related) { f in
                                HStack { Pill(text: f.statusText, color: f.statusColor); Text(f.code).monospaced(); Text(f.hint?.title.text ?? f.unit).foregroundStyle(.secondary) }
                            }
                        }
                    }
                } else if !m.connected {
                    ContentUnavailableView(t("Brak analizy", "No analysis"), systemImage: "engine.combustion",
                                           description: Text(t("Połącz się i nagraj log albo otwórz zapisany log w Zapisach.", "Connect and record a log, or open a saved log in Captures.")))
                }
            }
            .padding(24)
        }
    }
}

// MARK: captures

struct CapturesPage: View {
    @EnvironmentObject var m: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Header(title: t("Zapisy", "Captures"), subtitle: t("Pełne odczyty (JSON) i logi (CSV). Zawierają VIN – nie publikuj ich.", "Full reads (JSON) and logs (CSV). They hold the VIN – don't publish them."))
                Spacer()
                Button { NSWorkspace.shared.open(Captures.folder) } label: { Label(t("Pokaż w Finderze", "Show in Finder"), systemImage: "folder") }
                Button { m.refreshCaptures() } label: { Image(systemName: "arrow.clockwise") }
            }
            if m.captures.isEmpty {
                ContentUnavailableView(t("Brak zapisów", "No captures"), systemImage: "tray")
            } else {
                List(m.captures, id: \.self) { u in
                    HStack {
                        Image(systemName: u.pathExtension == "csv" ? "chart.xyaxis.line" : "doc.text").foregroundStyle(Theme.blue)
                        Text(u.lastPathComponent).font(.body.monospaced())
                        Spacer()
                        if u.pathExtension == "csv" {
                            Button(t("Analizuj", "Analyse")) { m.analyze(u) }
                        } else {
                            Button(t("Otwórz", "Open")) { Task { await m.openProbe(u) } }
                        }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([u]) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .padding(24)
    }
}

// MARK: AI

struct AIPage: View {
    var exe: String { Bundle.main.executableURL?.path ?? "EnetDiag" }
    var claudeCode: String { "claude mcp add bmw-enet -- \"\(exe)\" --mcp" }
    var desktop: String { "{\n  \"mcpServers\": {\n    \"bmw-enet\": { \"command\": \"\(exe)\", \"args\": [\"--mcp\"] }\n  }\n}" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: t("Asystent AI", "AI assistant"),
                       subtitle: t("Podłącz własnego Claude (MCP): wyjaśni każdy kod i podpowie, co sprawdzić", "Connect your own Claude (MCP): it explains any code and suggests what to check"))
                Card(title: "Claude Code", symbol: "terminal") {
                    Copyable(text: claudeCode)
                }
                Card(title: "Claude Desktop", symbol: "macwindow") {
                    Text(t("Wklej do claude_desktop_config.json i uruchom Claude ponownie.", "Paste into claude_desktop_config.json and restart Claude.")).font(.callout).foregroundStyle(.secondary)
                    Copyable(text: desktop)
                }
                Card(title: t("Co może asystent", "What the assistant can do"), symbol: "checklist") {
                    ForEach([("list.bullet.rectangle", t("Odczytać błędy wszystkich sterowników", "Read every control unit's faults")),
                             ("gauge.with.dots.needle.50percent", t("Odczytać wartości silnika", "Read engine values")),
                             ("chart.xyaxis.line", t("Przeanalizować zapisane logi", "Analyse saved logs")),
                             ("lock.shield", t("Niczego nie zapisze ani nie skasuje – tylko odczyt", "Write or clear nothing – read-only"))], id: \.1) { s, l in
                        Label(l, systemImage: s)
                    }
                    Text(t("Przykład: „Odczytaj błędy z mojego BMW, wyjaśnij je i powiedz, co sprawdzić najpierw.”",
                           "Example: “Read the faults from my BMW, explain them and tell me what to check first.”"))
                        .font(.callout).italic().foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }
}

struct Copyable: View {
    let text: String
    @State var copied = false
    var body: some View {
        HStack(alignment: .top) {
            Text(text).font(.callout.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); copied = true } label: {
                Label(copied ? t("Skopiowano", "Copied") : t("Kopiuj", "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
            }
        }
        .padding(10).background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: settings

struct SettingsView: View {
    @AppStorage("lang") var lang = ""
    @AppStorage("host") var host = ""
    var body: some View {
        Form {
            Picker(t("Język", "Language"), selection: $lang) {
                Text(t("Systemowy", "System")).tag("")
                Text("Polski").tag("pl")
                Text("English").tag("en")
            }
            TextField(t("Domyślne IP bramki", "Default gateway IP"), text: $host, prompt: Text(t("auto", "auto")))
            LabeledContent(t("Zapisy", "Captures")) { Text(Captures.folder.path).font(.caption).textSelection(.enabled) }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .id(lang)
    }
}
