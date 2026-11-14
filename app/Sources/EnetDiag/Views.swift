// Views - a macOS 26/27 window: floating glass sidebar, a stable glass toolbar, an inspector for faults,
// system containers for content, Liquid Glass only on things that float (actions, status).
import AppKit
import Charts
import EnetCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject var m: Model

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $m.section) { s in
                Label(s.title, systemImage: s.symbol)
                    .badge(s == .faults ? m.faults.filter(\.active).count : 0)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)          // empty states sit in the middle; tables and scroll views fill
            .navigationTitle((m.section ?? .overview).title)
            .navigationSubtitle(m.isDemo ? t("Demo – symulowane auto", "Demo – simulated car") : m.connected ? m.connection : t("Niepołączono", "Not connected"))
        }
        .toolbar { MainToolbar() }
        .overlay(alignment: .bottom) { StatusBanner() }
        .task {
            if CommandLine.arguments.contains("--demo") { await m.connectDemo() }
            else if CommandLine.arguments.contains("--replay"), !m.connected { await m.connect() }
        }
    }
}

struct SidebarFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stripe(height: 3).frame(width: 44)
            Label(t("Tylko odczyt", "Read-only"), systemImage: "lock.shield.fill")
                .font(.callout.weight(.semibold))
            Text(t("Kasowanie błędów: Fault Scanner w MGU Store lub warsztat.", "Clearing faults: Fault Scanner in the MGU Store, or a workshop."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        .padding(10)
    }
}

struct MainToolbar: ToolbarContent {
    @EnvironmentObject var m: Model
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if m.connected {
                Button { Task { await m.readFaults() } } label: { Label(t("Odczytaj błędy", "Read Faults"), systemImage: "arrow.clockwise") }
                    .help(t("Odczytaj pamięć błędów wszystkich sterowników (⌘R)", "Read every control unit's fault memory (⌘R)"))
                Button { Task { await m.runProbe() } } label: { Label(t("Pełny odczyt", "Full Read"), systemImage: "doc.text.magnifyingglass") }
                    .help(t("Wszystko z silnika do pliku", "Everything from the engine to a file"))
            } else {
                Button { Task { await m.connectDemo() } } label: { Label("Demo", systemImage: "play.rectangle") }
                    .help(t("Symulowane auto", "A simulated car"))
            }
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            if m.busy != nil {
                ProgressView().controlSize(.small)
            } else if m.connected {
                Button { Task { await m.disconnect() } } label: { Label(t("Rozłącz", "Disconnect"), systemImage: "eject") }
            } else {
                Button { Task { await m.connect() } } label: { Label(t("Połącz", "Connect"), systemImage: "cable.connector") }
                    .buttonStyle(.glassProminent)
                    .help(t("Kabel ENET w gnieździe OBD, zapłon włączony (⌘K)", "ENET cable in the OBD port, ignition on (⌘K)"))
            }
        }
    }
}

struct StatusBanner: View {
    @EnvironmentObject var m: Model
    var body: some View {
        Group {
            if let e = m.error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular.tint(.red.opacity(0.15)).interactive(), in: Capsule())
                    .onTapGesture { m.error = nil }
                    .help(t("Kliknij, aby zamknąć", "Click to dismiss"))
            } else if let b = m.busy {
                Label(b, systemImage: "antenna.radiowaves.left.and.right")
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
            }
        }
        .padding(.bottom, 18)
        .animation(.smooth, value: m.busy)
        .animation(.smooth, value: m.error)
    }
}

/// A floating row of glass actions (they merge and morph as one group).
struct GlassActions<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) { content }
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}

struct NotConnected: View {
    @EnvironmentObject var m: Model
    var body: some View {
        ContentUnavailableView {
            Label(t("Podłącz auto", "Connect the Car"), systemImage: "cable.connector")
        } description: {
            Text(t("Kabel ENET do gniazda OBD i do Maca, zapłon włączony. Albo obejrzyj demo.",
                   "ENET cable into the OBD port and the Mac, ignition on. Or watch the demo."))
        } actions: {
            GlassActions {
                Button(t("Połącz", "Connect")) { Task { await m.connect() } }.buttonStyle(.glassProminent)
                Button(t("Wypróbuj demo", "Try the Demo")) { Task { await m.connectDemo() } }
            }
        }
    }
}

// MARK: overview

struct OverviewPage: View {
    @EnvironmentObject var m: Model
    var body: some View {
        if m.connected {
            ScrollView { Dashboard().padding(24) }
        } else {
            Welcome()
        }
    }
}

struct Welcome: View {
    @EnvironmentObject var m: Model
    var body: some View {
        VStack(spacing: 26) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            VStack(spacing: 8) {
                Text("BMW ENET Diag").font(.largeTitle.weight(.semibold))
                Text(t("Błędy wszystkich sterowników, dane silnika na żywo i kontrola silnika – tylko odczyt.",
                       "Every control unit's faults, live engine data and an engine check – read-only."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
            }
            VStack(alignment: .leading, spacing: 12) {
                StepRow(n: 1, symbol: "cable.connector", text: t("Kabel ENET do gniazda OBD (pod kierownicą) i do Maca", "ENET cable into the OBD port (under the wheel) and the Mac"))
                StepRow(n: 2, symbol: "key.fill", text: t("Zapłon włączony; do danych na żywo silnik pracuje", "Ignition on; for live data the engine running"))
                StepRow(n: 3, symbol: "antenna.radiowaves.left.and.right", text: t("Połącz – bramka zostanie znaleziona sama", "Connect – the gateway is found by itself"))
            }
            .frame(maxWidth: 520, alignment: .leading)
            GlassActions {
                Button { Task { await m.connect() } } label: { Label(t("Połącz z autem", "Connect to the Car"), systemImage: "cable.connector") }
                    .buttonStyle(.glassProminent)
                Button { Task { await m.connectDemo() } } label: { Label(t("Wypróbuj demo", "Try the Demo"), systemImage: "play.rectangle") }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StepRow: View {
    let n: Int, symbol: String, text: String
    var body: some View {
        HStack(spacing: 14) {
            Text("\(n)").font(.headline.monospacedDigit()).frame(width: 28, height: 28)
                .glassEffect(.regular.tint(.accentColor.opacity(0.35)), in: Circle())
            Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary)
            Text(text)
        }
    }
}

/// One number with its caption, in a system group box.
struct Stat: View {
    let title: String, symbol: String, value: String, caption: String
    var color: Color = .primary
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

struct Dashboard: View {
    @EnvironmentObject var m: Model
    var body: some View {
        let active = m.faults.filter(\.active).count
        let workshop = m.faults.filter { $0.hint?.severity == .workshop }.count
        let levels = m.report?.findings.map(\.level) ?? []
        let worst: Finding.Level? = m.report == nil ? nil : levels.contains(.problem) ? .problem : levels.contains(.watch) ? .watch : .ok
        VStack(alignment: .leading, spacing: 18) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Stat(title: t("Błędy", "Faults"), symbol: "exclamationmark.triangle", value: "\(m.faults.count)",
                         caption: t("aktywnych: ", "active: ") + "\(active)", color: active > 0 ? .red : .primary)
                    Stat(title: t("Do warsztatu", "For a Workshop"), symbol: "wrench.and.screwdriver", value: "\(workshop)",
                         caption: t("wg naszych podpowiedzi", "by our hints"), color: workshop > 0 ? .red : .green)
                    Stat(title: t("Kontrola silnika", "Engine Check"), symbol: "engine.combustion",
                         value: worst.map { $0 == .ok ? t("Bez uwag", "All Good") : $0 == .watch ? t("Uwagi", "Notes") : t("Problem", "Problem") } ?? "–",
                         caption: m.reportName ?? t("nagraj log na ciepłym silniku", "record a log, engine warm"), color: worst?.color ?? .secondary)
                    Stat(title: t("Przebieg", "Odometer"), symbol: "road.lanes", value: m.live.last?["odometer"].map { "\(Int($0)) km" } ?? "–",
                         caption: m.isDemo ? t("symulowane auto", "simulated car") : m.connection)
                }
            }
            GlassActions {
                Button { m.section = .faults } label: { Label(t("Zobacz błędy", "View Faults"), systemImage: "list.bullet.rectangle") }
                Button { m.section = .live; m.startLive() } label: { Label(t("Dane na żywo", "Live Data"), systemImage: "waveform.path.ecg") }
                Button { m.section = .engine } label: { Label(t("Kontrola silnika", "Engine Check"), systemImage: "engine.combustion") }
            }
            if let top = m.faults.first(where: { $0.active }) {
                GroupBox {
                    HStack(alignment: .top, spacing: 12) {
                        Pill(text: top.statusText, color: top.statusColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(top.code) · \(top.unit)").font(.headline.monospaced())
                            Text(top.hint?.title.text ?? t("Brak naszego opisu – zapytaj asystenta AI", "No note of ours – ask your AI assistant"))
                            if let h = top.hint { Text(h.check.text).font(.callout).foregroundStyle(.secondary) }
                        }
                        Spacer()
                    }
                } label: { Label(t("Najważniejsze teraz", "Most Important Now"), systemImage: "flag.fill") }
            }
            if let p = m.probe {
                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow { Text("VIN").foregroundStyle(.secondary); Text(p.vin ?? "–").textSelection(.enabled) }
                        GridRow { Text(t("Przepływomierz", "Air mass meter")).foregroundStyle(.secondary); Text(p.hasMaf ? t("jest", "fitted") : t("brak (model w sterowniku)", "none (the unit's model)")) }
                        GridRow { Text(t("Kody OBD", "OBD codes")).foregroundStyle(.secondary); Text((p.obdStored + p.obdPending).joined(separator: ", ").ifEmpty("–")) }
                        GridRow { Text(t("Wypadanie zapłonów", "Misfires")).foregroundStyle(.secondary)
                            Text(p.misfires.isEmpty ? "–" : p.misfires.map { "\($0.cylinder): \(Int($0.current ?? 0))" }.joined(separator: "  ")) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: { Label(t("Ostatni pełny odczyt", "Last Full Read"), systemImage: "doc.text.magnifyingglass") }
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
    @State var inspector = true
    @State var sort: [KeyPathComparator<Fault>] = []          // empty: the car's order (active first, engine first)

    var shown: [Fault] {
        m.faults.filter { (!onlyActive || $0.active) &&
            (search.isEmpty || "\($0.code) \($0.unit) \($0.hint?.title.text ?? "")".localizedCaseInsensitiveContains(search)) }
            .sorted(using: sort.isEmpty ? [] : sort)
    }

    var body: some View {
        if !m.connected && m.faults.isEmpty { NotConnected() } else {
            Group {
                if m.faults.isEmpty {
                    ContentUnavailableView(t("Brak błędów", "No Faults"), systemImage: "checkmark.seal",
                                           description: Text(t("Żaden sterownik nie zgłasza błędów.", "No control unit reports a fault.")))
                } else {
                    Table(shown, selection: $selection, sortOrder: $sort) {
                        TableColumn(t("Status", "Status"), value: \.statusText) { f in Pill(text: f.statusText, color: f.statusColor) }.width(78)
                        TableColumn(t("Kod", "Code"), value: \.code) { f in Text(f.code).font(.body.monospaced().weight(.semibold)) }.width(72)
                        TableColumn(t("Sterownik", "Control Unit"), value: \.unit) { f in Label(f.unit, systemImage: f.kindSymbol).lineLimit(1) }
                            .width(min: 110, ideal: 140, max: 180)
                        TableColumn(t("Opis", "Description")) { f in
                            if let h = f.hint {
                                Label { Text(h.title.text) } icon: { Image(systemName: h.severity.symbol).foregroundStyle(h.severity.color) }
                            } else {
                                Text(t("Brak opisu – zapytaj asystenta AI", "No note – ask your AI assistant")).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu(forSelectionType: Fault.ID.self) { ids in
                        Button(t("Kopiuj kod", "Copy Code")) { copy(m.faults.filter { ids.contains($0.id) }.map(\.code).joined(separator: "\n")) }
                        Button(t("Kopiuj dla AI", "Copy for AI")) { copy(m.faultsText()) }
                    } primaryAction: { _ in inspector = true }
                }
            }
            .searchable(text: $search, prompt: t("Szukaj kodu lub sterownika", "Search code or unit"))
            .inspector(isPresented: $inspector) {
                FaultInspector(fault: m.faults.first { $0.id == selection })
                    .inspectorColumnWidth(min: 240, ideal: 290, max: 360)
            }
            .toolbar {
                ToolbarItemGroup {
                    Toggle(isOn: $onlyActive) { Label(t("Tylko aktywne", "Active Only"), systemImage: "line.3.horizontal.decrease") }
                        .help(t("Pokaż tylko aktywne błędy", "Show active faults only"))
                    Button { copy(m.faultsText()) } label: { Label(t("Kopiuj dla AI", "Copy for AI"), systemImage: "sparkles") }
                        .disabled(m.faults.isEmpty)
                        .help(t("Lista błędów do wklejenia asystentowi AI", "The fault list, to paste into your AI assistant"))
                    Button { inspector.toggle() } label: { Label(t("Szczegóły", "Details"), systemImage: "sidebar.trailing") }
                }
            }
        }
    }
}

func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }

struct FaultInspector: View {
    let fault: Fault?
    var body: some View {
        if let f = fault {
            Form {
                SwiftUI.Section {
                    LabeledContent(t("Kod", "Code")) { Text(f.code).font(.title2.monospaced().weight(.bold)).textSelection(.enabled) }
                    LabeledContent(t("Status", "Status")) { Pill(text: f.statusText, color: f.statusColor) }
                    LabeledContent(t("Sterownik", "Control unit")) { Label(f.unit, systemImage: f.kindSymbol) }
                    LabeledContent(t("Adres", "Address")) { Text("0x" + f.address).monospaced() }
                }
                if let h = f.hint {
                    SwiftUI.Section(h.title.text) {
                        Label(h.severity.label, systemImage: h.severity.symbol).foregroundStyle(h.severity.color)
                        if h.confidence != "high" {
                            Label(t("Opis mniej pewny – źródło dotyczy pokrewnego modelu", "Less certain – the source covers a related model"),
                                  systemImage: "questionmark.circle").foregroundStyle(.secondary).font(.caption)
                        }
                        Text(h.what.text)
                    }
                    SwiftUI.Section(t("Co sprawdzić", "What to Check")) { Text(h.check.text) }
                    if !h.sources.isEmpty {
                        SwiftUI.Section(t("Źródła", "Sources")) {
                            ForEach(h.sources, id: \.self) { s in if let u = URL(string: s) { Link(u.host ?? s, destination: u) } }
                        }
                    }
                } else {
                    SwiftUI.Section {
                        Text(t("Nie mamy jeszcze opisu tego kodu. Zapytaj swojego asystenta AI albo skopiuj listę („Kopiuj dla AI”).",
                               "We have no note for this code yet. Ask your AI assistant, or copy the list (“Copy for AI”)."))
                            .foregroundStyle(.secondary)
                    }
                }
                SwiftUI.Section {
                    Label(t("Kasowanie: Fault Scanner w MGU Store albo warsztat.", "Clearing: Fault Scanner in the MGU Store, or a workshop."),
                          systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(t("Wybierz błąd", "Select a Fault"), systemImage: "sidebar.trailing")
        }
    }
}

// MARK: live

struct Tile: View {
    let label: String, value: Double?, unit: String, digits: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map { String(format: "%.\(digits)f", $0) } ?? "–")
                    .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LivePage: View {
    @EnvironmentObject var m: Model
    static let digits: [String: Int] = ["lambda": 3, "lambda_cmd": 3, "voltage": 2, "stft": 1, "ltft": 1, "maf": 1, "rail": 1, "fuel_rate": 1]
    static let groupTitle: [Pid.Group: L] = [.engine: L("Silnik", "Engine"), .air: L("Powietrze", "Air"), .fuel: L("Paliwo i mieszanka", "Fuel and Mixture"),
                                             .temps: L("Temperatury", "Temperatures"), .status: L("Stan i elektryka", "Status and Electrical")]

    var body: some View {
        if !m.connected { NotConnected() } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let last = m.live.last ?? [:]
                    if last.isEmpty {
                        ContentUnavailableView(t("Dane na żywo zatrzymane", "Live Data Stopped"), systemImage: "waveform.path.ecg",
                                               description: Text(t("Kliknij Start na pasku narzędzi.", "Click Start in the toolbar.")))
                    }
                    GroupBox {
                        Chart {
                            ForEach(Array(m.live.suffix(240).enumerated()), id: \.offset) { i, s in
                                if let v = s["stft"] { LineMark(x: .value("t", i), y: .value("%", v)).foregroundStyle(by: .value("", "STFT")) }
                                if let v = s["ltft"] { LineMark(x: .value("t", i), y: .value("%", v)).foregroundStyle(by: .value("", "LTFT")) }
                            }
                            RuleMark(y: .value("0", 0)).foregroundStyle(.secondary.opacity(0.4))
                        }
                        .chartForegroundStyleScale(["STFT": Color.cyan, "LTFT": Color.red])
                        .chartXAxis(.hidden)
                        .chartYScale(domain: -25...25)
                        .frame(height: 170)
                    } label: { Label(t("Korekty paliwa (%)", "Fuel Trims (%)"), systemImage: "chart.xyaxis.line") }
                    ForEach(Pid.Group.allCases, id: \.self) { g in
                        let pids = Pids.all.filter { $0.group == g && last[$0.key] != nil }
                        if !pids.isEmpty {
                            GroupBox {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], alignment: .leading, spacing: 14) {
                                    ForEach(pids, id: \.key) { p in Tile(label: Pids.label(p), value: last[p.key], unit: p.unit, digits: Self.digits[p.key] ?? 0) }
                                }
                                .padding(4)
                            } label: { Text(Self.groupTitle[g]?.text ?? "") }
                        }
                    }
                    if !m.misfires.isEmpty {
                        GroupBox {
                            Chart(m.misfires) { c in
                                BarMark(x: .value(t("Cylinder", "Cylinder"), "\(c.cylinder)"), y: .value(t("Teraz", "Now"), c.current ?? 0))
                                    .foregroundStyle((c.current ?? 0) > 0 ? Color.orange : Color.green)
                            }
                            .frame(height: 120)
                            Text(t("Liczniki z monitora OBD (tryb 06), ten cykl jazdy. 0 = brak wypadania zapłonów.",
                                   "OBD monitor counters (mode 06), this driving cycle. 0 = no misfires."))
                                .font(.caption).foregroundStyle(.secondary)
                        } label: { Label(t("Wypadanie zapłonów na cylinder", "Misfires per Cylinder"), systemImage: "flame") }
                    }
                    Label(t("Nie obsługuj komputera w czasie jazdy.", "Don't operate the computer while driving."), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem {
                    Button { m.liveOn ? m.stopLive() : m.startLive() } label: {
                        Label(m.liveOn ? t("Zatrzymaj", "Stop") : t("Start", "Start"), systemImage: m.liveOn ? "pause.fill" : "play.fill")
                    }
                }
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
                (t("2–3 min na wolnych obrotach", "2–3 min at idle") + " (\(idle)/120)", idle >= 120),
                (t("1 min przy ~2500 obr/min, na postoju", "1 min at ~2500 rpm, at standstill") + " (\(mid)/50)", mid >= 50)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if m.connected {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(steps, id: \.0) { s in
                                Label(s.0, systemImage: s.1 ? "checkmark.circle.fill" : "circle").foregroundStyle(s.1 ? .green : .primary)
                            }
                            Text(t("Na postoju. Nie obsługuj komputera w czasie jazdy.", "At standstill. Don't operate the computer while driving."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: { Label(m.recording == nil ? t("Nagranie", "Recording") : t("Nagrywanie… próbek: ", "Recording… samples: ") + "\(m.recorded.count)", systemImage: "record.circle") }
                }
                if let r = m.report {
                    Text((m.reportName ?? "") + " · " + t("próbek ", "samples ") + "\(r.samples), " + t("na ciepło ", "warm ") + "\(r.warmSamples)")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(r.findings) { f in
                        GroupBox {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: f.level.symbol).font(.title2).foregroundStyle(f.level.color)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(f.title.text).font(.headline)
                                    Text(f.verdict.text)
                                    Text(f.values.sorted { $0.key < $1.key }.map { "\(Self.valueName($0.key)) \(String(format: "%.2f", $0.value))" }.joined(separator: " · "))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                    ForEach(r.notes, id: \.self) { n in Label(n.text, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                    let related = m.faults.filter { f in r.findings.contains { $0.level != .ok && $0.relatedKinds.contains(f.kind) } }
                    if !related.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(related) { f in
                                    HStack { Pill(text: f.statusText, color: f.statusColor); Text(f.code).monospaced(); Text(f.hint?.title.text ?? f.unit).foregroundStyle(.secondary) }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: { Label(t("Powiązane błędy", "Related Faults"), systemImage: "link") }
                    }
                } else if !m.connected {
                    ContentUnavailableView(t("Brak analizy", "No Analysis"), systemImage: "engine.combustion",
                                           description: Text(t("Połącz się i nagraj log albo otwórz zapisany log w Zapisach.", "Connect and record a log, or open a saved log in Captures.")))
                }
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItem {
                if m.recording == nil {
                    Button { m.startRecording() } label: { Label(t("Nagrywaj", "Record"), systemImage: "record.circle") }.disabled(!m.connected)
                } else {
                    Button { m.stopRecording() } label: { Label(t("Zakończ i analizuj", "Stop and Analyse"), systemImage: "stop.fill") }
                }
            }
        }
    }

    static func valueName(_ k: String) -> String {
        let pl = ["coolant_max": "płyn max °C", "trim_idle": "korekta wolne %", "trim_mid": "korekta 2500 %", "maf_drift": "dryf MAF",
                  "voltage": "napięcie V", "map_idle": "kolektor wolne kPa", "lambda_dev": "odchyłka λ"]
        let en = ["coolant_max": "coolant max °C", "trim_idle": "trim idle %", "trim_mid": "trim 2500 %", "maf_drift": "MAF drift",
                  "voltage": "voltage V", "map_idle": "manifold idle kPa", "lambda_dev": "λ deviation"]
        return (Lang.current == .pl ? pl : en)[k] ?? k
    }
}

// MARK: captures

struct CaptureRow: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var isLog: Bool { url.pathExtension == "csv" }
    var kind: String { isLog ? t("Log silnika", "Engine log") : t("Pełny odczyt", "Full read") }
    var date: Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
    var size: Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
}

struct CapturesPage: View {
    @EnvironmentObject var m: Model
    @State var selection: URL?
    var rows: [CaptureRow] { m.captures.map { CaptureRow(url: $0) } }

    func open(_ r: CaptureRow) { if r.isLog { m.analyze(r.url) } else { Task { await m.openProbe(r.url) } } }

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView(t("Brak zapisów", "No Captures"), systemImage: "tray",
                                       description: Text(t("Pełne odczyty i logi pojawią się tutaj. Zawierają VIN – nie publikuj ich.",
                                                           "Full reads and logs appear here. They hold the VIN – don't publish them.")))
            } else {
                Table(rows, selection: $selection) {
                    TableColumn(t("Rodzaj", "Kind")) { r in Label(r.kind, systemImage: r.isLog ? "chart.xyaxis.line" : "doc.text.magnifyingglass") }.width(min: 120, ideal: 150)
                    TableColumn(t("Data", "Date")) { r in Text(r.date.formatted(date: .abbreviated, time: .shortened)) }.width(min: 140, ideal: 170)
                    TableColumn(t("Rozmiar", "Size")) { r in Text(ByteCountFormatter.string(fromByteCount: Int64(r.size), countStyle: .file)).monospacedDigit() }.width(80)
                    TableColumn(t("Plik", "File")) { r in Text(r.url.lastPathComponent).foregroundStyle(.secondary) }
                }
                .contextMenu(forSelectionType: URL.self) { ids in
                    if let u = ids.first {
                        let r = CaptureRow(url: u)
                        Button(r.isLog ? t("Analizuj", "Analyse") : t("Otwórz", "Open")) { open(r) }
                        Button(t("Pokaż w Finderze", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                    }
                } primaryAction: { ids in if let u = ids.first { open(CaptureRow(url: u)) } }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { m.refreshCaptures() } label: { Label(t("Odśwież", "Refresh"), systemImage: "arrow.clockwise") }
                Button { NSWorkspace.shared.open(Captures.folder) } label: { Label(t("Pokaż w Finderze", "Show in Finder"), systemImage: "folder") }
            }
        }
    }
}

// MARK: AI

struct AIPage: View {
    var exe: String { Bundle.main.executableURL?.path ?? "EnetDiag" }
    var claudeCode: String { "claude mcp add bmw-enet -- \"\(exe)\" --mcp" }
    var desktop: String { "{\n  \"mcpServers\": {\n    \"bmw-enet\": { \"command\": \"\(exe)\", \"args\": [\"--mcp\"] }\n  }\n}" }

    var body: some View {
        Form {
            SwiftUI.Section {
                Text(t("Podłącz własnego Claude przez MCP: odczyta błędy, wyjaśni każdy kod i podpowie, co sprawdzić. Bez kluczy w tej aplikacji.",
                       "Connect your own Claude over MCP: it reads the faults, explains any code and suggests what to check. No keys in this app."))
            }
            SwiftUI.Section("Claude Code") { Copyable(text: claudeCode) }
            SwiftUI.Section {
                Copyable(text: desktop)
            } header: { Text("Claude Desktop") } footer: {
                Text(t("Wklej do claude_desktop_config.json i uruchom Claude ponownie.", "Paste into claude_desktop_config.json and restart Claude."))
            }
            SwiftUI.Section(t("Co może asystent", "What the Assistant Can Do")) {
                Label(t("Odczytać błędy wszystkich sterowników", "Read every control unit's faults"), systemImage: "list.bullet.rectangle")
                Label(t("Odczytać wartości silnika", "Read engine values"), systemImage: "gauge.with.dots.needle.50percent")
                Label(t("Przeanalizować zapisane logi", "Analyse saved logs"), systemImage: "chart.xyaxis.line")
                Label(t("Niczego nie zapisze ani nie skasuje – tylko odczyt", "Write or clear nothing – read-only"), systemImage: "lock.shield")
            }
            SwiftUI.Section(t("Przykład", "Example")) {
                Text(t("„Odczytaj błędy z mojego BMW, wyjaśnij je i powiedz, co sprawdzić najpierw.”",
                       "“Read the faults from my BMW, explain them and tell me what to check first.”")).italic()
            }
        }
        .formStyle(.grouped)
    }
}

struct Copyable: View {
    let text: String
    @State var copied = false
    var body: some View {
        HStack(alignment: .top) {
            Text(text).font(.callout.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button { copy(text); copied = true } label: {
                Label(copied ? t("Skopiowano", "Copied") : t("Kopiuj", "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.glass)
        }
    }
}

// MARK: settings

struct SettingsView: View {
    @AppStorage("host") var host = ""
    var body: some View {
        Form {
            TextField(t("IP bramki ENET", "ENET gateway IP"), text: $host, prompt: Text(t("automatycznie", "automatic")))
            LabeledContent(t("Język", "Language")) {
                Text(t("Ustawienia systemowe › Ogólne › Język i region › Aplikacje", "System Settings › General › Language & Region › Applications"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent(t("Zapisy", "Captures")) {
                Button(t("Pokaż w Finderze", "Show in Finder")) { NSWorkspace.shared.open(Captures.folder) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}
