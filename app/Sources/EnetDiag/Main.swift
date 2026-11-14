// Entry: `EnetDiag --mcp` serves MCP over stdio (for the owner's AI client); otherwise the app.
// `--replay <probe.json>` makes Connect open a saved probe instead of the car (demos, screenshots).
import AppKit
import EnetCore
import SwiftUI

@main enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--mcp") {
            Task { await MCP.serve(); exit(0) }
            dispatchMain()
        }
        EnetDiagApp.main()
    }
}

struct EnetDiagApp: App {
    @StateObject var model = Model()
    @AppStorage("lang") var lang = ""

    var body: some Scene {
        WindowGroup("BMW ENET Diag") {
            RootView().environmentObject(model)
                .frame(minWidth: 980, minHeight: 620)
                .tint(Theme.blue)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(t("O BMW ENET Diag", "About BMW ENET Diag")) {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(string: t(
                            "Diagnostyka tylko do odczytu przez kabel ENET.\nNiezależny projekt, niezwiązany z BMW AG.",
                            "Read-only diagnostics over the ENET cable.\nAn independent project, not affiliated with BMW AG."))])
                }
            }
            CommandMenu(t("Auto", "Car")) {
                Button(model.connected ? t("Rozłącz", "Disconnect") : t("Połącz", "Connect")) {
                    Task { model.connected ? await model.disconnect() : await model.connect() }
                }.keyboardShortcut("k")
                Button(t("Wypróbuj demo", "Try the demo")) { Task { await model.connectDemo() } }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button(t("Odczytaj błędy", "Read faults")) { model.section = .faults; Task { await model.readFaults() } }
                    .keyboardShortcut("r").disabled(!model.connected)
                Button(t("Pełny odczyt silnika", "Full engine read")) { Task { await model.runProbe() } }
                    .keyboardShortcut("p", modifiers: [.command, .shift]).disabled(!model.connected)
                Button(model.liveOn ? t("Zatrzymaj dane na żywo", "Stop live data") : t("Dane na żywo", "Live data")) {
                    model.section = .live; model.liveOn ? model.stopLive() : model.startLive()
                }.keyboardShortcut("l").disabled(!model.connected)
                Divider()
                Button(t("Pokaż zapisy w Finderze", "Show captures in Finder")) { NSWorkspace.shared.open(Captures.folder) }
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(Section.allCases.enumerated()), id: \.1) { i, s in
                    Button(s.title) { model.section = s }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
        }
        Settings { SettingsView() }
    }
}
