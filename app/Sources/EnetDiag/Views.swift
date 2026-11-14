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
        if m.connected {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { Task { await m.readFaults() } } label: { Label(t("Odczytaj błędy ponownie", "Read Faults Again"), systemImage: "arrow.clockwise") }
                    Button { Task { await m.runProbe() } } label: { Label(t("Pełny odczyt silnika", "Full Engine Read"), systemImage: "doc.text.magnifyingglass") }
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                } label: {
                    Label(m.isDemo ? "Demo" : t("Połączono", "Connected"), systemImage: m.isDemo ? "play.rectangle.fill" : "cable.connector")
                        .labelStyle(.titleAndIcon)
                }
                .help(t("Odczytaj ponownie (⌘R), pełny odczyt (⇧⌘P)", "Read again (⌘R), full read (⇧⌘P)"))
                .disabled(m.busy != nil)
            }
            ToolbarItem(placement: .primaryAction) {                 // always available, also during a read
                Button { Task { await m.disconnect() } } label: { Label(t("Rozłącz", "Disconnect"), systemImage: "eject").labelStyle(.titleAndIcon) }
                    .help(t("Zakończ połączenie z autem (⌘K)", "End the connection to the car (⌘K)"))
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { Task { await m.connectDemo() } } label: { Label(t("Wypróbuj demo", "Try the Demo"), systemImage: "play.rectangle") }
                } label: {
                    Label(t("Połącz", "Connect"), systemImage: "cable.connector").labelStyle(.titleAndIcon)
                } primaryAction: {
                    Task { await m.connect() }
                }
                .help(t("Kabel ENET w gnieździe OBD, zapłon włączony (⌘K). Strzałka: demo.", "ENET cable in the OBD port, ignition on (⌘K). Arrow: demo."))
                .disabled(m.busy != nil)
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
            ScrollView { Dashboard().padding(28) }
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
            .disabled(m.busy != nil)
            Label(m.busy ?? t("Niepołączono", "Not connected"), systemImage: m.busy == nil ? "bolt.horizontal.circle" : "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
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
                Text(value).font(.system(size: 38, weight: .semibold, design: .rounded)).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
                Text(caption).font(.callout).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        } label: {
            Label(title, systemImage: symbol).font(.headline).padding(.bottom, 2)
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
        VStack(alignment: .leading, spacing: 24) {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: m.isDemo ? "play.rectangle.fill" : "cable.connector").font(.title).foregroundStyle(.green).frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.isDemo ? t("Demo – symulowane auto", "Demo – a simulated car") : t("Połączono z autem", "Connected to the car")).font(.title2.weight(.semibold))
                        Text(m.busy ?? (m.isDemo ? t("Nic nie jest wysyłane do prawdziwego auta.", "Nothing is sent to a real car.")
                                                 : t("Bramka ", "Gateway ") + m.connection + t(" · tylko odczyt", " · read-only")))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await m.disconnect() } } label: { Label(t("Rozłącz", "Disconnect"), systemImage: "eject") }
                        .buttonStyle(.glass).controlSize(.large)
                }
                Divider()
                Text(t("Co chcesz zrobić?", "What would you like to do?")).font(.headline).foregroundStyle(.secondary)
                GlassActions {
                    let faults = Button { m.section = .faults } label: {
                        Label(m.faults.isEmpty ? t("Zobacz błędy", "View Faults") : t("Zobacz błędy (\(m.faults.count))", "View Faults (\(m.faults.count))"), systemImage: "list.bullet.rectangle") }
                    if m.faults.isEmpty { faults } else { faults.buttonStyle(.glassProminent) }
                    Button { m.section = .live; m.startLive() } label: { Label(t("Dane na żywo", "Live Data"), systemImage: "waveform.path.ecg") }
                    Button { m.section = .engine } label: { Label(t("Kontrola silnika", "Engine Check"), systemImage: "engine.combustion") }
                }
            }
            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
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
            if let id = m.identity { VehicleCard(id: id) }
            let top = Array(m.faults.sorted { ($0.active ? 0 : 1, $0.hint?.severity == .workshop ? 0 : 1) < ($1.active ? 0 : 1, $1.hint?.severity == .workshop ? 0 : 1) }.prefix(3))
            HStack(alignment: .top, spacing: 12) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        if top.isEmpty { Label(t("Brak błędów", "No faults"), systemImage: "checkmark.seal").foregroundStyle(.green) }
                        ForEach(top) { f in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: f.hint?.severity.symbol ?? "questionmark.circle")
                                    .font(.title3).foregroundStyle(f.hint?.severity.color ?? .secondary).frame(width: 26)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(f.hint?.title.text ?? t("Kod bez naszego opisu", "Code without a note of ours")).font(.title3.weight(.semibold))
                                    Text("\(f.code) · \(f.unitText) · \(f.statusText)").font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { m.section = .faults }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                } label: { Label(t("Najważniejsze teraz", "Most Important Now"), systemImage: "flag.fill").font(.headline).padding(.bottom, 2) }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        if let r = m.report {
                            ForEach(r.findings) { f in
                                Label { Text(f.title.text).font(.title3) } icon: { Image(systemName: f.level.symbol).font(.title3).foregroundStyle(f.level.color) }
                            }
                        } else {
                            Text(t("Nagraj log w Kontroli silnika, a tu pojawi się wynik.", "Record a log in Engine Check and the result shows here."))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .contentShape(Rectangle())
                    .onTapGesture { m.section = .engine }
                } label: { Label(t("Kontrola silnika", "Engine Check"), systemImage: "engine.combustion").font(.headline).padding(.bottom, 2) }
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

struct VehicleCard: View {
    @EnvironmentObject var m: Model
    let id: Identity
    @State var copied = false

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 28) {
                Image(systemName: "car.side.fill").font(.system(size: 40)).foregroundStyle(.tint).frame(width: 56).padding(.top, 4)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("VIN").foregroundStyle(.secondary)
                        Text(id.vin ?? "–").font(.title3.monospaced().weight(.semibold)).textSelection(.enabled)
                    }
                    GridRow { Text(t("Producent", "Maker")).foregroundStyle(.secondary); Text(id.maker ?? "–") }
                    GridRow { Text(t("Rok modelowy", "Model year")).foregroundStyle(.secondary); Text(id.modelYear.map(String.init) ?? "–") }
                    GridRow { Text(t("Kod typu", "Type code")).foregroundStyle(.secondary); Text(id.typeCode ?? "–").monospaced() }
                }
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow { Text(t("Sterownik silnika", "Engine unit")).foregroundStyle(.secondary); Text(id.ecuName ?? "–") }
                    GridRow { Text(t("Oprogramowanie", "Software")).foregroundStyle(.secondary); Text(id.calibrationIds.joined(separator: ", ").ifEmpty("–")).monospaced().textSelection(.enabled) }
                    GridRow { Text(t("Norma OBD", "OBD standard")).foregroundStyle(.secondary); Text(id.obdStandard ?? "–") }
                    GridRow { Text(t("Przebieg", "Odometer")).foregroundStyle(.secondary); Text(id.odometerKm.map { "\(Int($0)) km" } ?? "–") }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    Button { copy(id.vin ?? ""); copied = true } label: { Label(copied ? t("Skopiowano", "Copied") : t("Kopiuj VIN", "Copy VIN"), systemImage: copied ? "checkmark" : "doc.on.doc") }
                    Button { copy(m.modelQuestion()) } label: { Label(t("Zapytaj AI o model", "Ask AI for the model"), systemImage: "sparkles") }
                        .help(t("Kopiuje pytanie z kodem typu (bez numeru seryjnego) do wklejenia asystentowi", "Copies a question with the type code (no serial number) for your AI assistant"))
                }
                .buttonStyle(.glass)
            }
            .padding(14)
        } label: { Label(t("Pojazd", "Vehicle"), systemImage: "car.fill").font(.headline).padding(.bottom, 2) }
    }
}

extension String { func ifEmpty(_ s: String) -> String { isEmpty ? s : self } }

// MARK: faults

struct FaultsPage: View {
    @EnvironmentObject var m: Model
    @State var selection: Fault.ID?
    @State var search = ""
    @State var onlyActive = false
    @State var inspector = false
    @State var sort: [KeyPathComparator<Fault>] = []          // empty: the car's order (active first, engine first)

    var shown: [Fault] {
        m.faults.filter { (!onlyActive || $0.active) &&
            (search.isEmpty || "\($0.code) \($0.unit) \($0.unitText) \($0.hint?.title.text ?? "")".localizedCaseInsensitiveContains(search)) }
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
                        TableColumn(t("Status", "Status"), value: \.statusText) { f in Pill(text: f.statusText, color: f.statusColor) }.width(96)
                        TableColumn(t("Kod", "Code"), value: \.code) { f in Text(f.code).font(.body.monospaced().weight(.semibold)) }.width(72)
                        TableColumn(t("Moduł", "Module"), value: \.unitText) { f in Label(f.unitText, systemImage: f.kindSymbol).lineLimit(2) }
                            .width(min: 180, ideal: 230, max: 300)
                        TableColumn(t("Opis", "Description")) { f in
                            if let h = f.hint {
                                Label { Text(h.title.text).lineLimit(3) } icon: { Image(systemName: h.severity.symbol).foregroundStyle(h.severity.color) }
                            } else {
                                Text(t("Brak opisu – zapytaj asystenta AI", "No note – ask your AI assistant")).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .alternatingRowBackgrounds(.disabled)
                    .contextMenu(forSelectionType: Fault.ID.self) { ids in
                        Button(t("Kopiuj kod", "Copy Code")) { copy(m.faults.filter { ids.contains($0.id) }.map(\.code).joined(separator: "\n")) }
                        Button(t("Kopiuj dla AI", "Copy for AI")) { copy(m.faultsText()) }
                    } primaryAction: { _ in inspector = true }
                }
            }
            .onChange(of: selection) { _, id in if id != nil { inspector = true } }
            .searchable(text: $search, prompt: t("Szukaj kodu lub modułu", "Search code or module"))
            .inspector(isPresented: $inspector) {
                FaultInspector(fault: m.faults.first { $0.id == selection })
                    .inspectorColumnWidth(min: 240, ideal: 290, max: 360)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(t("Pokaż", "Show"), selection: $onlyActive) {
                        Text(t("Wszystkie", "All")).tag(false)
                        Text(t("Aktywne", "Active")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .help(t("Wszystkie błędy albo tylko aktywne", "All faults, or active ones only"))
                }
                ToolbarItemGroup {
                    Button { copy(m.faultsText()) } label: { Label(t("Kopiuj dla AI", "Copy for AI"), systemImage: "sparkles") }
                        .disabled(m.faults.isEmpty)
                        .help(t("Kopiuj listę błędów dla asystenta AI", "Copy the fault list for your AI assistant"))
                    Button { inspector.toggle() } label: { Label(t("Szczegóły", "Details"), systemImage: "sidebar.trailing") }
                        .help(t("Pokaż / ukryj szczegóły błędu", "Show / hide the fault details"))
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
                    LabeledContent(t("Moduł", "Module")) { Label(f.unitText, systemImage: f.kindSymbol) }
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
    var norm: Norm? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map { String(format: "%.\(digits)f", $0) } ?? "–")
                    .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                    .foregroundStyle(norm?.ok == false ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            if let norm {
                let color: Color = norm.ok == true ? .green : norm.ok == false ? .orange : .secondary
                Label {
                    Text(t("norma ", "normal ") + norm.range.text + (norm.note.map { " · " + $0.text } ?? ""))
                } icon: {
                    Image(systemName: norm.ok == true ? "checkmark.circle.fill" : norm.ok == false ? "exclamationmark.triangle.fill" : "clock")
                        .foregroundStyle(color)
                }
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .help(norm.ok == false ? t("Poza typowym zakresem", "Outside the typical range") : t("Typowy zakres dla nowoczesnego silnika benzynowego", "Typical range for a modern petrol engine"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                                    ForEach(pids, id: \.key) { p in Tile(label: Pids.label(p), value: last[p.key], unit: p.unit, digits: Self.digits[p.key] ?? 0,
                                                                     norm: last[p.key].flatMap { Norms.check(p.key, $0, in: last) }) }
                                }
                                .padding(12)
                            } label: { Text(Self.groupTitle[g]?.text ?? "").font(.headline).padding(.bottom, 2) }
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

/// The four steps across the top: done ones ticked, the current one highlighted.
struct CheckStepper: View {
    let step: Model.CheckStep
    var body: some View {
        let titles = [t("Przygotowanie", "Get ready"), t("Wolne obroty", "Idle"), t("2500 obr/min", "2500 rpm"), t("Wynik", "Result")]
        HStack(spacing: 10) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, title in
                let done = i < step.rawValue, now = i == step.rawValue
                if i > 0 { Rectangle().fill(done || now ? Theme.blue : Color.secondary.opacity(0.3)).frame(height: 2) }
                HStack(spacing: 8) {
                    Group {
                        if done { Image(systemName: "checkmark").font(.headline) } else { Text("\(i + 1)").font(.headline.monospacedDigit()) }
                    }
                    .foregroundStyle(now ? .white : done ? .green : .secondary)
                    .frame(width: 30, height: 30)
                    .background(now ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(.quaternary), in: Circle())
                    Text(title).font(now ? .title3.weight(.semibold) : .title3).foregroundStyle(now ? .primary : .secondary)
                        .lineLimit(1).fixedSize()
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(done ? t("zrobione", "done") : now ? t("teraz", "current") : "")
            }
        }
    }
}

/// Where the revs are against the 2200–3200 band.
struct RpmBand: View {
    let rpm: Double
    var body: some View {
        let ok = (2200...3200).contains(rpm)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                let x = { (v: Double) in g.size.width * min(max(v, 0), 4500) / 4500 }
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 14)
                    RoundedRectangle(cornerRadius: 5).fill(Color.green.opacity(0.45)).frame(width: x(3200) - x(2200), height: 14).offset(x: x(2200))
                    Capsule().fill(ok ? Color.green : Color.orange).frame(width: 8, height: 34).offset(x: x(rpm) - 4)
                        .animation(.smooth, value: rpm)
                }
                .frame(height: 34)
            }
            .frame(height: 34)
            Text(t("Zielone pole: 2200–3200 obr/min", "Green zone: 2200–3200 rpm")).font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Obroty", "Revs")).accessibilityValue("\(Int(rpm))")
    }
}

struct EnginePage: View {
    @EnvironmentObject var m: Model
    var last: Sample { m.live.last ?? [:] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CheckStepper(step: m.checkStep)
                switch m.checkStep {
                case .prepare: prepare
                case .idle: idle
                case .mid: mid
                case .result: result
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .task(id: m.connected) { if m.connected { m.startLive() } }      // the checklist needs moving values
    }

    // MARK: 1 - get ready

    /// Why the check cannot start yet (nil = ready). Same conditions the analysis needs.
    var blocker: String? {
        guard m.connected else { return t("Najpierw połącz z autem", "Connect to the car first") }
        guard !last.isEmpty else { return t("Czekam na dane z silnika…", "Waiting for engine data…") }
        if (last["rpm"] ?? 0) < 300 { return t("Silnik nie pracuje – uruchom go", "The engine is off – start it") }
        guard let c = last["coolant"] else { return t("Brak odczytu temperatury płynu", "No coolant temperature reading") }
        if c < Analysis.warmC { return t("Silnik zimny – \(Int(c)) °C, poczekaj do 70 °C", "Engine cold – \(Int(c)) °C, wait for 70 °C") }
        if (last["speed"] ?? 0) > 0 { return t("Auto jedzie – zatrzymaj się", "The car is moving – stop first") }
        return nil
    }

    func check(_ title: String, _ ok: Bool?, _ detail: String, progress: Double? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok == true ? "checkmark.circle.fill" : ok == false ? "xmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(ok == true ? Color.green : ok == false ? Color.orange : Color.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).foregroundStyle(.secondary)
                if let progress, ok == false { ProgressView(value: min(max(progress, 0), 1)).frame(maxWidth: 260) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder var prepare: some View {
        let on = m.connected && !last.isEmpty
        let rpm = last["rpm"] ?? 0, coolant = last["coolant"], speed = last["speed"] ?? 0
        Card {
            Text(t("Przygotuj auto", "Get the car ready")).font(.title.weight(.semibold))
            Text(t("Kontrola trwa około 4 minut: najpierw silnik pracuje na wolnych obrotach, potem przez minutę trzymasz 2500 obr/min. Aplikacja tylko czyta dane – niczego w aucie nie zmienia.",
                   "The check takes about 4 minutes: first the engine idles, then you hold 2500 rpm for a minute. The app only reads data – it changes nothing in the car."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                check(t("Połączenie z autem", "Connection to the car"), m.connected,
                      m.connected ? (m.isDemo ? t("Demo – symulowane auto", "Demo – simulated car") : t("Połączono", "Connected"))
                                  : t("Kabel ENET do gniazda OBD i do Maca, zapłon włączony", "ENET cable into the OBD port and the Mac, ignition on"))
                check(t("Silnik pracuje", "Engine running"), on ? rpm >= 300 : nil,
                      !on ? "–" : rpm >= 300 ? "\(Int(rpm)) " + t("obr/min", "rpm") : t("Uruchom silnik", "Start the engine"))
                check(t("Silnik rozgrzany (płyn co najmniej 70 °C)", "Engine warm (coolant at least 70 °C)"), on ? (coolant ?? 0) >= Analysis.warmC : nil,
                      !on ? "–" : coolant.map { $0 >= Analysis.warmC ? "\(Int($0)) °C" : t("Teraz \(Int($0)) °C – poczekaj albo przejedź się i wróć", "Now \(Int($0)) °C – wait, or take a drive and come back") }
                          ?? t("Brak odczytu temperatury", "No temperature reading"),
                      progress: coolant.map { $0 / Analysis.warmC })
                check(t("Auto stoi", "Car parked"), on ? speed == 0 : nil,
                      !on ? "–" : speed == 0 ? t("0 km/h – skrzynia w P lub na luzie, hamulec postojowy", "0 km/h – gearbox in P or neutral, parking brake on")
                                             : "\(Int(speed)) km/h – " + t("zatrzymaj się", "stop first"))
            }
            .padding(.vertical, 6)
            GlassActions {
                if m.connected {
                    Button { m.startRecording() } label: { Label(t("Zacznij kontrolę", "Start the Check"), systemImage: "play.fill") }
                        .buttonStyle(.glassProminent).disabled(blocker != nil)
                } else {
                    Button { Task { await m.connect() } } label: { Label(t("Połącz z autem", "Connect to the Car"), systemImage: "cable.connector") }
                        .buttonStyle(.glassProminent)
                    Button { Task { await m.connectDemo() } } label: { Label(t("Wypróbuj demo", "Try the Demo"), systemImage: "play.rectangle") }
                }
                if m.report != nil {
                    Button { m.newCheck = false } label: { Label(t("Wróć do wyniku", "Back to the Result"), systemImage: "chevron.backward") }
                }
            }
            .disabled(m.busy != nil)
            if let blocker { Label(blocker, systemImage: "exclamationmark.circle.fill").font(.title3).foregroundStyle(.orange) }
            else { Label(t("Wszystko gotowe – kliknij „Zacznij kontrolę”.", "All set – click “Start the Check”."), systemImage: "checkmark.circle.fill").font(.title3).foregroundStyle(.green) }
        }
    }

    // MARK: 2, 3 - recording

    /// Why the current reading is not being counted (nil = it counts).
    func notCounting(_ want: String) -> String? {
        if !m.liveOn && !m.frozen { return t("Odczyt zatrzymany", "Reading stopped") }
        let rpm = last["rpm"] ?? 0
        if (last["coolant"] ?? 0) < Analysis.warmC { return t("Silnik za zimny (poniżej 70 °C) – czekam", "Engine too cold (below 70 °C) – waiting") }
        if (last["speed"] ?? 0) > 0 { return t("Auto jedzie – zatrzymaj się", "The car is moving – stop") }
        if Analysis.phase(last) == want { return nil }
        if want == "idle" {
            return rpm < 500 ? t("Silnik nie pracuje", "The engine is off") : rpm >= 1000 ? t("Puść gaz – obroty mają spaść poniżej 1000", "Let go of the pedal – revs must drop below 1000")
                : t("Sterownik jeszcze nie reguluje mieszanki – czekam", "The engine computer isn't regulating the mixture yet – waiting")
        }
        return rpm < 2200 ? t("Za nisko – dodaj gazu", "Too low – more throttle") : rpm > 3200 ? t("Za wysoko – odpuść gaz", "Too high – ease off")
            : t("Sterownik jeszcze nie reguluje mieszanki – trzymaj", "The engine computer isn't regulating the mixture yet – hold")
    }

    func recordingCard(title: String, text: String, want: String, good: String, count: Int, of total: Int, @ViewBuilder extra: () -> some View) -> some View {
        let why = notCounting(want)
        return Card {
            Text(title).font(.title.weight(.semibold))
            Text(text).font(.title3).fixedSize(horizontal: false, vertical: true)
            extra()
            Label(why ?? good, systemImage: why == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2.weight(.semibold)).foregroundStyle(why == nil ? .green : .orange)
            ProgressView(value: Double(min(count, total)), total: Double(total)) {
                Text(t("Postęp", "Progress") + ": \(min(count, total) * 100 / total) %").font(.headline.monospacedDigit())
            }
            .tint(why == nil ? Theme.blue : .orange)
            GroupBox {
                HStack(alignment: .top, spacing: 14) {
                    Tile(label: t("Obroty", "Revs"), value: last["rpm"], unit: t("obr/min", "rpm"), digits: 0)
                    Tile(label: t("Korekta chwilowa", "Short-term trim"), value: last["stft"], unit: "%", digits: 1)
                    Tile(label: t("Korekta długa", "Long-term trim"), value: last["ltft"], unit: "%", digits: 1)
                    Tile(label: t("Płyn", "Coolant"), value: last["coolant"], unit: "°C", digits: 0)
                }
                .padding(10)
            }
            GlassActions {
                if !m.liveOn && !m.frozen {
                    Button { m.startLive() } label: { Label(t("Wznów odczyt", "Resume Reading"), systemImage: "play.fill") }.buttonStyle(.glassProminent)
                }
                Button(role: .cancel) { m.cancelRecording() } label: { Label(t("Anuluj", "Cancel"), systemImage: "xmark") }
                Button { m.stopRecording() } label: { Label(t("Zakończ teraz i pokaż wynik", "Finish Now and Show the Result"), systemImage: "stop.fill") }
                    .help(t("Wynik z niepełnego nagrania może być mniej pewny", "A result from a partial recording may be less certain"))
            }
            Text(t("Nic nie musisz klikać – kolejny krok włączy się sam.", "Nothing to click – the next step starts by itself."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    var idle: some View {
        recordingCard(title: t("Wolne obroty", "Idle"),
                      text: t("Nie dotykaj gazu. Zostaw silnik na wolnych obrotach, aż pasek dojdzie do końca (około 2 minut).",
                              "Don't touch the pedal. Let the engine idle until the bar fills (about 2 minutes)."),
                      want: "idle", good: t("Nagrywam – tak trzymaj", "Recording – keep it like this"), count: m.idleCount, of: Model.idleNeeded) { EmptyView() }
    }

    var mid: some View {
        recordingCard(title: t("Trzymaj 2500 obr/min", "Hold 2500 rpm"),
                      text: t("Auto stoi (P lub luz, hamulec postojowy). Wciśnij lekko gaz i trzymaj obroty w zielonym polu, aż pasek dojdzie do końca (około minuty).",
                              "The car is parked (P or neutral, parking brake). Press the pedal lightly and keep the revs in the green zone until the bar fills (about a minute)."),
                      want: "mid", good: t("Dobrze – trzymaj", "Good – hold it"), count: m.midCount, of: Model.midNeeded) {
            HStack(alignment: .center, spacing: 20) {
                Text("\(Int(last["rpm"] ?? 0))").font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText()).frame(minWidth: 170, alignment: .leading)
                RpmBand(rpm: last["rpm"] ?? 0)
            }
        }
    }

    // MARK: 4 - result

    var again: some View {
        Button { m.newCheck = true } label: { Label(t("Nowa kontrola", "New Check"), systemImage: "arrow.counterclockwise") }
    }

    func counts(_ r: Report) -> String {
        let name = m.reportName ?? ""
        return name + " · " + t("próbek \(r.samples), na ciepłym silniku \(r.warmSamples)", "\(r.samples) samples, \(r.warmSamples) with the engine warm")
    }

    @ViewBuilder var result: some View {
        if let r = m.report {
            let levels = r.findings.map(\.level)
            let worst: Finding.Level = levels.contains(.problem) ? .problem : levels.contains(.watch) ? .watch : r.findings.isEmpty ? .unknown : .ok
            let related = m.faults.filter { f in r.findings.contains { $0.level != .ok && $0.level != .unknown && $0.relatedKinds.contains(f.kind) } }
            let file = m.captures.first { $0.lastPathComponent == m.reportName }
            Card {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: worst.symbol).font(.system(size: 40)).foregroundStyle(worst.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(worst == .problem ? t("Wykryto problem", "A problem was found") : worst == .watch ? t("Są uwagi do sprawdzenia", "Some things to check")
                             : worst == .ok ? t("Silnik bez uwag", "The engine looks fine") : t("Za mało danych na wynik", "Not enough data for a result"))
                            .font(.title.weight(.semibold))
                        Text(counts(r))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                ForEach(r.notes, id: \.self) { n in
                    Label(n.text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if !r.notes.isEmpty {
                    Text(t("Nagranie jest niepełne, więc wynik jest mniej pewny – najlepiej powtórz kontrolę.",
                           "The recording is incomplete, so the result is less certain – best repeat the check.")).font(.callout)
                }
                Text(worst == .problem || worst == .watch
                     ? t("Co dalej: przeczytaj opisy przy czerwonych i pomarańczowych pozycjach poniżej, potem kliknij „Kopiuj dla AI” i wklej wynik asystentowi albo pokaż go mechanikowi. Po naprawie zrób nową kontrolę.",
                         "What next: read the notes on the red and orange items below, then click “Copy for AI” and paste the result to your assistant, or show it to a mechanic. After the repair run a new check.")
                     : worst == .ok ? t("Nic nie trzeba robić. Powtórz kontrolę, gdy zapali się kontrolka silnika albo silnik zacznie pracować nierówno.",
                                        "Nothing to do. Repeat the check if the engine light comes on or the engine starts running unevenly.")
                     : t("Rozgrzej silnik i zrób nową kontrolę.", "Warm the engine up and run a new check."))
                    .font(.title3).fixedSize(horizontal: false, vertical: true)
                GlassActions {
                    if worst == .unknown || !r.notes.isEmpty { again.buttonStyle(.glassProminent) } else { again }
                    Button { copy(m.reportText()) } label: { Label(t("Kopiuj dla AI", "Copy for AI"), systemImage: "sparkles") }
                        .help(t("Kopiuje wynik jako tekst – wklej go swojemu asystentowi AI albo wyślij mechanikowi", "Copies the result as text – paste it to your AI assistant or send it to a mechanic"))
                    if let file {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([file]) } label: { Label(t("Pokaż zapis w Finderze", "Show the Log in Finder"), systemImage: "folder") }
                    }
                }
            }
            let order: [Finding.Level] = [.problem, .watch, .unknown, .ok]
            ForEach(r.findings.sorted { order.firstIndex(of: $0.level)! < order.firstIndex(of: $1.level)! }) { f in
                Card {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: f.level.symbol).font(.title).foregroundStyle(f.level.color).frame(width: 32)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(f.title.text).font(.title3.weight(.semibold))
                            Text(f.verdict.text).fixedSize(horizontal: false, vertical: true)
                            Text(f.values.sorted { $0.key < $1.key }.map { "\(Self.valueName($0.key)) \(String(format: "%.2f", $0.value))" }.joined(separator: " · "))
                                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !related.isEmpty {
                Card(title: t("Powiązane błędy w pamięci auta", "Related Faults in the Car's Memory"), symbol: "link") {
                    ForEach(related) { f in
                        HStack { Pill(text: f.statusText, color: f.statusColor); Text(f.code).monospaced(); Text(f.hint?.title.text ?? f.unitText).foregroundStyle(.secondary) }
                    }
                    Button(t("Zobacz błędy", "View Faults")) { m.section = .faults }.buttonStyle(.glass)
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
