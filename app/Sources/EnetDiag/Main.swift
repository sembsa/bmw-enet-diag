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
        if let i = CommandLine.arguments.firstIndex(of: "--render"), i + 1 < CommandLine.arguments.count {
            render(to: CommandLine.arguments[i + 1])                  // screenshots while the screen is locked
        }
        EnetDiagApp.main()
    }

    /// Draws the demo window's content (no title bar or toolbar) into a PNG, offscreen, then exits.
    @MainActor static func render(to path: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let dark = CommandLine.arguments.contains("--dark")
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let model = Model()
        let host = NSHostingView(rootView: RootView().environmentObject(model).frame(width: 1280, height: 800))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        w.appearance = app.appearance
        w.backgroundColor = .windowBackgroundColor
        w.contentView = host
        Task { @MainActor in
            if !CommandLine.arguments.contains("--offline") { await model.connectDemo() }
            if model.section == .live { model.startLive() }
            if let i = CommandLine.arguments.firstIndex(of: "--engine-step"), i + 1 < CommandLine.arguments.count { model.seed(CommandLine.arguments[i + 1]) }
            try? await Task.sleep(for: .seconds(4))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
        app.run()
    }
}

struct EnetDiagApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var model = Model()

    var body: some Scene {
        Window("BMW ENET Diag", id: "main") {
            RootView().environmentObject(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            SidebarCommands()
            InspectorCommands()
            ToolbarCommands()
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

/// Closing the window ends the app (one window, nothing left polling the car).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
