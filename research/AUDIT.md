# BMW ENET Diag: audit (2026-11-14)

Scope: `app/` (EnetCore, EnetDiag, tests), read against `PLAN.md` and `README.md`. Nothing in the repo was edited.
Built with Swift 6.4.2 / SDK 27.2; `swift build` and `swift test` pass (10 tests).

How things were checked:

- **Ran:** `swift test`; the MCP server over stdio against a replay file and a scratch captures folder; a socket test on loopback and TEST-NET; an in-process SwiftUI repro of the sidebar list.
- **Type-checked only:** every SwiftUI snippet below, for macOS 14 and macOS 26 targets.
- **Not done:** real window screenshots. The screen was locked for the whole run, so `winshot` / `screencapture` failed ("could not create image from window"). Instead the app's own views were rendered offscreen from a scratch copy (demo car, light and dark). These show page content but no window chrome, toolbar or glass, so toolbar and material remarks come from the code.
- **Not done:** a real click on the sidebar (no input events allowed), and anything against a real car.

Renders: offscreen, demo data (not kept in the repo).

## Summary verdict

The read-only core is sound: the allowlist is correct and tested, `Car` is a deep module, and no path was found that puts a non-allowlisted UDS request on the wire. The app around it is not ready for a car yet:

- **The sidebar cannot switch sections**, in the committed code and in the uncommitted fix. Cause confirmed (P0-1).
- **The app can be killed by SIGPIPE** when the gateway goes away, and a wrong IP blocks Connect for over 20 s (P1-1, P1-2).
- **The MCP server crashes** on a log containing `nan` or `inf`, and `read_capture` follows symlinks out of the captures folder (P1-3, S-2).
- **The VIN leaves the Mac** through `read_capture`, and probably sits in the toolbar via the gateway ident string (P1-4).
- **The head unit is reached** by the functional scan and by `probe()`. That matches PLAN.md but conflicts with "no head-unit access" (P1-5, needs a decision).
- **It looks like a dashboard web page inside a Mac window**: large in-content titles, hand-made cards, a custom split instead of `.inspector`, a forced tint, an empty window title, a home-made language switch. The structure (NavigationSplitView, Table, Settings, menus) is right, so this is a restyle, not a rewrite.
- **Live data is thin**: 18 PIDs decoded, 12 shown, about 1 sample per second. Readiness, MIL status, misfire counters, fuel pressure and downstream O2 are all available from public J1979 and missing.

---

## P0

### P0-1 Sidebar does not switch sections
`app/Sources/EnetDiag/Views.swift:13-17`, `app/Sources/EnetDiag/Model.swift:8-10`

The List selects values of type `Section` (the binding is `Section?`), but no row carries a `Section` tag:

| Variant | Row tag the List sees (inferred) | Preselected row highlighted | Binding after selecting row "live" |
|---|---|---|---|
| HEAD: `.tag(s).badge(…)` | implicit id, a `String` (the tag is buried under `.badge`) | no | `nil` |
| Working tree: `.badge(…).tag(Optional(s))` | `Section?`, not `Section` | no | `nil` |
| Same, without `.badge` | `Section?` | no | `nil` |
| `.badge(…).tag(s)` | `Section` | yes | `.live` |
| `id: Self`, no tag | `Section` | yes | `.live` |

So the suspicion about `.badge` and `.tag` order was right for the committed code, and the uncommitted fix trades it for a type mismatch. In both, a click sets `m.section = nil`, and `m.section ?? .overview` (line 22) shows Overview. The tag column is my reading of why; the two right-hand columns are measured. This is also why the menu shortcuts ⌘1–6 and `--section` still work: they set the model directly. The offscreen render of `RootView` with the model's section set to Faults shows the Faults page with no sidebar row highlighted.

Measured in a standalone repro (seven lists, the NSTableView behind each read and driven in-process, built for macOS 14 and 27). The selection was made with `selectRowIndexes`, not a real click.

Fix: make the row identity the selection type, so no tag is needed and modifier order stops mattering.

```swift
enum Section: String, CaseIterable, Identifiable {
    case overview, faults, live, engine, captures, ai
    var id: Self { self }          // was: String { rawValue }
```
```swift
List(Section.allCases, selection: $m.section) { s in
    Label(s.title, systemImage: s.symbol)
        .badge(s == .faults ? m.faults.filter(\.active).count : 0)
}
```
`Main.swift:56` (`ForEach(…, id: \.1)`) keeps working. Add a guard so a deselect (click on empty sidebar space) cannot blank the detail: keep `?? .overview`, or reset `nil` to the previous value.

---

## P1

### P1-1 SIGPIPE kills the app when the gateway closes the connection
`app/Sources/EnetCore/Transport.swift:32, 86`

The socket has no `SO_NOSIGPIPE`. A loopback test with the same setup (peer closes, tester sends) ended with exit 141, killed by SIGPIPE. In the app: ignition off, the live loop gets "the gateway closed the connection", the UI still shows connected (P2-1), the owner presses Read faults, and the process dies. The MCP server dies the same way.

```swift
fd = socket(AF_INET, SOCK_STREAM, 0)
guard fd >= 0 else { throw LinkError(description: "no socket: \(String(cString: strerror(errno)))") }
var on: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
```
`socket()` is also unchecked today (line 32), and in `discoverGateway` (line 138).

### P1-2 Connect blocks for a long time on a wrong or dead IP
`app/Sources/EnetCore/Transport.swift:33-37`

`SO_SNDTIMEO` does not bound `connect()` on macOS. Measured: still blocked after 20 s with the 3 s timeout set. The UI shows "Connecting…" with no cancel, and the MCP tool call hangs.

```swift
var secs: Int32 = 4
setsockopt(fd, IPPROTO_TCP, TCP_CONNECTIONTIMEOUT, &secs, socklen_t(MemoryLayout<Int32>.size))
```
Measured with this option: `connect` returns "Operation timed out" after 4.0 s.

### P1-3 MCP server crashes on a log with `nan` or `inf`
`app/Sources/EnetCore/Captures.swift:68`, `app/Sources/EnetCore/MCP.swift:83`

`Double("nan")` and `Double("inf")` parse. The value reaches `Finding.values`, and `JSONSerialization.data` raises an Objective-C exception that Swift cannot catch. Reproduced with a two-row CSV through `analyze_log`: "Invalid number value (NaN) in JSON write", process terminated, later requests lost.

Fix at the trust boundary, one line in `readLog`, plus a guard before serialising:
```swift
if let d = Double(v), d.isFinite { s[k] = d }
```
```swift
guard JSONSerialization.isValidJSONObject(out) else { throw LinkError(description: "result is not JSON") }
```

### P1-4 VIN handling
- `app/Sources/EnetCore/MCP.swift:53-57`: `read_capture` returns the whole probe except `exchanges`, so `vin` and `connection` go to the AI client and its provider. The tool description does not say so.
- `app/Sources/EnetCore/Car.swift:57`, `Views.swift:64, 218`: `connection` is the IP plus the gateway's ident text. The HSFZ identification answer is commonly documented as carrying the VIN (`DIAGADR…BMWMAC…BMWVIN…`); not verified on this car. If so, the VIN is in the toolbar, on the Overview card and in every screenshot.
- `app/Sources/EnetCore/Car.swift:171`: `exchanges` in a saved probe holds the raw `62 F1 90 <VIN>` answer, so removing the `vin` field does not anonymise a capture. PLAN step 6 ("the capture becomes a test fixture, VIN removed") has no function to do it.

Fix: one `Probe.redacted()` in EnetCore that blanks `vin`, strips the ident from `connection`, and replaces the VIN bytes in `exchanges["12:22f190"]`. Use it in `read_capture` by default (show the last 7 characters at most), in an "Export without VIN" action, and for fixtures. Show only the IP in the toolbar.

### P1-5 The head unit is reached (decision needed)
`app/Sources/EnetCore/Allowlist.swift:22-27`, `app/Sources/EnetCore/Car.swift:101, 145-150`, `app/Tests/EnetCoreTests/CoreTests.swift:11`

- The functional scan `19 02 FF` to `0xDF` reaches every unit, including the head unit (`0x63`), telematics (`0x61`) and the cluster.
- `probe()` sends physical `19 04` / `19 06` to any unit with an active fault, so to `0x63` when it has one.
- The allowlist test asserts `(0x63, 22 F1 90)` passes.

PLAN.md says "every unit", so the code does what the plan says. The audit brief says "no head-unit access". If the brief wins:
- refuse physical requests to `0x63` (and `0x61` if wanted) in `Allowlist.check`, with a test;
- limit `probe()` details to the engine unit;
- accept that a functional `0xDF` request cannot exclude one unit; the alternative is physical `19 02` to a list of addresses, which is slower and still read-only.

### P1-6 Faults list can show DTCs that are not faults
`app/Sources/EnetCore/Car.swift:101-104`, `app/Sources/EnetDiag/Theme.swift:22`

`19 02 FF` asks for every DTC with any status bit set, including "test not completed" bits (0x10, 0x40). Anything without bit 0 or 2 is shown as STORED, even when the confirmed bit (0x08) is clear. Whether this car's units report such records is untested.

Fix: keep only records where `status & 0x0D != 0` (failed, pending or confirmed), or request mask `0x0D`. Show "confirmed" from bit 3, which is already parsed and unused.

---

## P2

### Correctness

| # | Where | Problem | Fix |
|---|---|---|---|
| P2-1 | `Model.swift:129-131` | After a link error the live loop stops but `car` stays set: green dot, enabled buttons, an open recording that gets no more rows. | On `LinkError`, call `disconnect()` (which stops and analyses the recording) and show the error. |
| P2-2 | `Model.swift:199-204`, `Views.swift:73-79` | Buttons stay enabled while busy. A second Connect opens a second TCP session and leaks the first. | `.disabled(m.busy != nil)` on Connect, Demo, Read faults, Full read. |
| P2-3 | `Model.swift:39, 76`, `Views.swift:589` | The Settings IP field and the toolbar IP field are two copies. Model reads `host` once at launch; `connect()` writes its stale copy back and overwrites a Settings change. | One source: `@AppStorage("host")`, read at connect time. Drop one of the two fields (see redesign 4). |
| P2-4 | `Model.swift:133`, `Views.swift:385, 435-436` | The UI says "every half second" and the steps count 240 / 100 samples for "2–3 min" / "1 min". The loop asks 14 PIDs one by one (at least 40 ms each) and then sleeps 500 ms: about 1 Hz, so 240 samples take 4 min or more. | Count seconds from `t`, not samples. Better: multi-PID requests (see live data). |
| P2-5 | `Views.swift:430-433` vs `Analysis.swift:28, 35-40` | The step thresholds (70 °C, rpm ranges) are a second copy of the analysis rules, and the copy ignores `speed == 0`. A step can tick while the analysis says "few samples". | `Analysis.progress(_ rows:) -> (warm: Bool, idle: Int, mid: Int)` in EnetCore, used by both. |
| P2-6 | `Transport.swift:57` | A frame that arrives partly and then stalls loops forever (EAGAIN with `got > 0` continues with no deadline). The serial queue is stuck until Disconnect. | Deadline in `read`: throw `LinkError("short frame")` when the frame timeout passes. |
| P2-7 | `Transport.swift:71-74` | Frame length from the wire is trusted: up to 4 GB allocated. Length 0 or 1 throws "short frame" and leaves the stream out of step. | `guard (2...1_048_576).contains(len)`; for `len < 2` read and skip. |
| P2-8 | `Transport.swift:75` | HSFZ error frames (control words 0x40–0x45, 0xFF: wrong tester address, wrong target, not ready) are skipped, so the caller sees a timeout with no reason. | Map them to `LinkError` with the reason. |
| P2-9 | `Transport.swift:97-100` | A response is matched by source address only. A late answer to the functional scan from 0x12 can be taken as the answer to the next 0x12 request; in `probe()` it could be stored as a fault's "snapshot". | Accept only `sid + 0x40` or `7F sid`; skip the rest. |
| P2-10 | `Car.swift:71`, `Transport.swift:116` | `close()` closes the fd outside the serial queue while `recv` may be blocked on it (Disconnect during live). The fd number can be reused by another open. | `shutdown(fd, SHUT_RDWR)` now, `close(fd)` on the queue. |
| P2-11 | `Main.swift:22` | `WindowGroup` allows ⌘N: every window shares one Model, and each new window reruns `.task` (a second demo connect). Closing the last window leaves the app running and polling the car with no window. | `Window("BMW ENET Diag", id: "main")`: one window, and the app quits when it closes. |
| P2-12 | `Analysis.swift:108-118` | The air mass check compares MAF with a speed-density estimate at a fixed 0.85 volumetric efficiency, idle against 2500 rpm. My reasoning, with no source or log behind it: on a turbo engine with variable valve lift, air per unit of manifold pressure changes with lift and boost, so the ratio may drift on a healthy engine. Demo data gives 0.84, already near the 20 % limit. | Mark the finding "indicative" until checked on real logs from the car. |
| P2-13 | `Analysis.swift:127-132` | Idle vacuum "typical ≤ 45 kPa" is a rule of thumb not checked on this car. The one public source found (a trade article on Valvetronic engines) gives 600–690 mbar of vacuum at idle, which agrees with the limit; nothing found for B38/B48. | Confirm on the first real log before trusting a `.watch` here. |
| P2-14 | `Analysis.swift:120-125` | Charging "low" below 13.2 V. Cars with intelligent alternator control may lower the voltage on purpose, so a short idle log could land there. Reasoning only; not verified for this car. | Check on a real log; if it happens, word it as "may be normal with smart charging". |

### Localisation and text

| # | Where | Problem | Fix |
|---|---|---|---|
| P2-15 | `Views.swift:395`, `Decode.swift:14-31` | English UI shows raw keys as labels: `LAMBDA_CMD`, `IAT`, `STFT`. `Pid.label` is Polish only. | `label: L` in `Pid`. |
| P2-16 | `Views.swift:474` | Findings show internal keys to the owner: `trim_idle 13.90 · trim_mid 3.10`, `maf_drift 0.84`. | Labelled values with units: "Idle trim +13.9 %". |
| P2-17 | `Theme.swift:22`, `Model.swift:191` | ACTIVE / PENDING / STORED are English in the Polish UI. | `L("AKTYWNY", "ACTIVE")` etc. |
| P2-18 | `Car.swift:52` | The "gateway not found" error is Polish only, inside EnetCore, and reaches MCP clients. Other errors are English only. | Errors as cases with an `L` message. |
| P2-19 | `Resources/Info.plist` | No `CFBundleLocalizations` / `CFBundleDevelopmentRegion`. System-provided menu items and panels will not follow the app's language; with the in-app override they can never match. | See redesign 9. |
| P2-20 | `Views.swift:367, 474` | `String(format: "%.1f")` ignores the locale (Polish uses a decimal comma). | `value.formatted(.number.precision(.fractionLength(1)))`. |

### Accessibility

| # | Where | Problem | Fix |
|---|---|---|---|
| P2-21 | `Views.swift:90-92` | The error banner is dismissed by a tap gesture on a Label: not a button, not reachable by keyboard, not announced by VoiceOver. | A `Button` inside the banner, or `.alert` for errors that need an action. |
| P2-22 | `Views.swift:62` | Connection state is a coloured dot with no label. | `.accessibilityLabel(connected ? "Connected" : "Not connected")`, or the subtitle from redesign 2. |
| P2-23 | `Views.swift:509, 524` | Icon-only buttons with no label or `.help`. | `Button("Refresh", systemImage: "arrow.clockwise")` with `.labelStyle(.iconOnly)` and `.help`. |
| P2-24 | `Views.swift:361-373, 191-205` | Tiles and stat cards are read as three separate texts. | `.accessibilityElement(children: .combine)` and an `.accessibilityValue` with the unit. |
| P2-25 | `Theme.swift:63-71` | Pill text is the tint colour on 15 % of itself. Orange and light blue on a light background look below WCAG AA; not measured. | `.foregroundStyle(.primary)` on the tinted capsule, or a darker text shade. |

---

## P3

- `Transport.swift:130`: `Dictionary(uniqueKeysWithValues:)` traps on a replay file with keys `"12"` and `"012"`. Use `uniquingKeysWith`.
- `Car.swift:11`: `Fault.id` is address + code; a unit that reports a code twice gives duplicate ids in the Table.
- `Allowlist.swift:27`: `22` with any identifier is allowed to the engine unit, but only `F190` is used. Narrow it to `F1xx` until a feature needs more.
- `MCP.swift:49-50`: snapshot values print as `7.8129999999999997`. Round to 2–3 places before serialising.
- `MCP.swift:18-26, 43-66`: tool list and `switch` are two lists to keep in step. One table of name, schema, handler.
- `Views.swift:34`: `.navigationTitle("")` gives the window an empty title in the Window menu and Mission Control.
- `Views.swift:36, 602`: `.id(lang)` rebuilds the whole tree on a language change; goes away with redesign 9.
- `Theme.swift:7`: the navy stripe segment (#0B1F3A) nearly vanishes in dark mode (see `render-live-dark.png`).
- `Main.swift:24`: minimum width 980 prevents half-screen tiling on a 13-inch display. About 720 works once the inspector can collapse.
- `README.md`: still describes the Python tool and says the app "runs the Python core". `enetdiag/` and `tests/` are still there, so there are two allowlists (the same rules today). PLAN step 5 is open.
- `research/known_codes.json` (69 entries) and `data/known_codes.json` (71) have drifted apart.
- `Package.swift:1`: tools 5.9 means Swift 5 mode, so no strict concurrency checking. `@unchecked Sendable` on the transports is safe only because `Car` serialises them on one queue.

---

## Design (deep modules, seams, testability)

What is good: `Car` is deep (four reads behind an actor, with framing, pacing, bitmaps and decoding hidden). `Transport` is a real seam with three adapters (TCP, replay, demo). `Analysis` is pure and tested through its interface.

Where to deepen, in order of payoff:

1. **The live session is in the untested target.** The polling loop, recording, step progress and error handling live in `Model` (`Model.swift:119-163`), and the EnetDiag target has no tests. Move them to EnetCore as one module, for example `LogSession(car:)` with `start()`, `stop() -> Report` and an `AsyncStream` of samples and progress. `Model` then only publishes. This also removes the duplicate thresholds in P2-5.
2. **A PID is spread over five places.** `Pids.all`, `Captures.logKeys`, `LivePage.keys`, the string keys in `Analysis`, and `DemoScenario.encode` (the inverse of `decode`, written by hand). Adding one PID means five edits. Give `Pid` its scale and offset as data so decode and the demo's encode come from one line, and derive the key lists from flags on `Pid`.
3. **Strings where types belong.** `Fault.address` is a hex string re-parsed in three places and compared with `"12"`; `kind` is a string switched on in `Theme.swift:25`; `Snapshot` is `[String: Double]`. A `UnitAddress` (UInt8), a `Kind` enum and a `PidKey` enum would move mistakes to compile time.
4. **The choke point holds by convention inside EnetCore.** `Car.transport` is internal (`Car.swift:33`), and `TcpTransport` can be built by any file in the module. Today only `Car.ask` / `askAll` reach it (grep confirms). Make it structural: `private let transport`, and call `Allowlist.check` again in `TcpTransport.write` (line 81), the only function that touches `Darwin.send`.
5. **`Probe.exchanges` mixes two things.** The replay log is stored as JSON inside a JSON string for functional answers, and `Car(replay:)` undoes that with a prefix test (`Car.swift:67`). A small Codable enum (`one(String)`, `many([String: String])`) removes the hack.
6. **`Lang.current` is a global read of UserDefaults inside EnetCore.** The core depends on a UI preference. Pass the language in, or return `L` and let the app choose.

---

## Make it feel like macOS 27

Limits of this section: the snippets are type-checked for macOS 14 and 26. APIs marked "26+" are Liquid Glass era APIs that macOS 27 keeps; nothing here is claimed as new in 27. Built with a 26+ SDK, the standard sidebar, toolbar and controls already get glass with no code. The work is mostly removing custom chrome that fights it.

In priority order:

1. **Fix the sidebar (P0-1) and restore the section** with `@SceneStorage("section")`.

2. **Give the window a title and move the status into it.** Remove the in-content `Header` (large title, subtitle, stripe) from every page. On the Mac the title belongs in the toolbar.
   ```swift
   .navigationTitle((m.section ?? .overview).title)
   .navigationSubtitle(m.connected ? m.gatewayIP : t("Niepołączono", "Not connected"))   // IP only, see P1-4
   ```
   This replaces the dot-and-text item at `.navigation` (`Views.swift:60-68`), a slot meant for back and sidebar controls.

3. **Use `.inspector` for the fault detail** instead of `HSplitView` plus a hand-sized panel (`Views.swift:278, 308`). It gives the full-height trailing column, the standard toggle and collapse on narrow windows.
   ```swift
   Table(shown, selection: $selection, sortOrder: $sort) { … }
       .inspector(isPresented: $showInspector) {
           FaultInspector(fault: selected).inspectorColumnWidth(min: 240, ideal: 280, max: 360)
       }
   ```
   Add `InspectorCommands()` and `SidebarCommands()` to `.commands`.

4. **Rebuild the toolbar from stable items.** Today the items change with the connection state and include a text field (`Views.swift:69-81`).
   - Keep the gateway IP in Settings only (it is already there), which also resolves P2-3.
   - One Connect / Disconnect item, Read faults, Full read; the per-page items (Active only, Copy for AI, Start / Stop live, Record) move from the page headers into `.toolbar` of each page.
   - On 26+ separate groups with `ToolbarSpacer(.fixed)` so they do not merge into one glass capsule.
   - Progress: the toolbar `ProgressView` is enough; drop the second "busy" banner.

5. **Make the faults table a Mac table.** Sortable columns (`TableColumn("Code", value: \.code)` with `sortOrder:`), a context menu and double-click:
   ```swift
   .contextMenu(forSelectionType: Fault.ID.self) { ids in
       Button(t("Kopiuj kod", "Copy Code")) { copy(ids) }
   } primaryAction: { _ in showInspector = true }
   ```
   "Active only" becomes a toolbar toggle or a search scope.

6. **Make Captures a Table too** (`Views.swift:514-528`): name, kind, date, size; double-click opens; context menu with Open, Analyse, Show in Finder, Move to Trash; `.draggable(url)`; `File > Open Capture…` (⌘O) with `fileImporter`; `ShareLink` for a report. Show a formatted date instead of `probe-20261114-120000.json`.

7. **Replace hand-made cards with system containers.** `Card`, `Stat`, `Step` and `Tile` each draw their own rounded rectangle with a fixed radius and stroke (`Theme.swift:74-90`, `Views.swift:184-186, 201-203, 371-372`). Use `GroupBox`, `Form` with `.formStyle(.grouped)` and `LabeledContent` for the read-outs. They follow the system's radii, materials, contrast settings and dark mode. Keep glass for things that float over content: on 26+ the status banner can be `Label(…).padding(10).glassEffect()`; do not put glass on content cards.

8. **Stop overriding the accent colour.** `.tint(Theme.blue)` on the window (`Main.swift:25`) and on buttons ignores the accent the owner chose in System Settings. Use an `AccentColor` in an asset catalog, and semantic colours (`.red`, `.orange`, `.green`) for status so they adapt to dark mode and Increase Contrast. Keep the three-colour stripe in one place (the About panel or the sidebar footer), not under every title.

9. **Use the system's language handling.** Declare `en` and `pl` in the bundle (`CFBundleLocalizations`, `CFBundleDevelopmentRegion`); macOS should then offer the per-app language under System Settings > General > Language & Region, and system menus should match (standard behaviour for bundles with several localisations; not tested with this bundle). Remove the in-app picker and `.id(lang)`; `Lang.current` becomes `Bundle.main.preferredLocalizations.first`. The `t(pl, en)` helper can stay. A String Catalog would be the full native route, but it needs the Xcode build system; whether `swift build` compiles `.xcstrings` on this toolchain was not checked.

10. **One window, standard commands.** `Window` scene (P2-11), `.windowResizability(.contentMinSize)`, a Help menu entry linking to the README, and `ToolbarCommands()`.

11. **Live page.** A `Gauge` or a small sparkline per tile, min / max since start, tiles grouped (air, fuel, temperatures, electrical), a chart picker instead of a fixed trims chart, and the chart's own legend (`chartForegroundStyleScale`) instead of the hand-made one.

12. **Welcome page.** The gradient tile with a car symbol is landing-page styling. `ContentUnavailableView` with the three steps as plain rows is enough and already used elsewhere.

13. **Model and build.** `@Observable` with `@Environment(Model.self)` instead of `ObservableObject` (narrower view updates; the live tick now republishes the whole model). An Xcode project or `xcodebuild` step would allow an asset catalog (accent colour) and an Icon Composer icon; the current `.icns` is the pre-26 format.

---

## Live data: is it enough, and what to add

Verdict: enough to see fuelling and air problems on a petrol engine at idle and 2500 rpm, which is what 101F01 needs. Not enough for a general owner's check: it cannot say whether the MIL is on, which monitors are ready, whether a cylinder misfires, what the fuel pressure is, or how the catalyst behaves.

Today: 18 PIDs decoded (`Decode.swift:13-32`), 14 logged, 12 shown. Services 03, 07, 09 and 02 are used only inside `probe()`.

Every PID below is public SAE J1979 / ISO 15031-5. Formulas were checked against the public PID table on Wikipedia unless marked "from memory". Mode 06 ids were confirmed by a web search against manufacturer Mode $06 documents, not against the standard itself. None of it was tried on the car; the engine unit reports what it supports in the `01 00/20/40…` bitmaps.

### No allowlist change needed (service 01 / 02 / 09 to 0x12)

| Add | PID | Why |
|---|---|---|
| MIL state, DTC count, readiness monitors | `01 01` (4 bytes, bit-coded) | The first thing an owner asks. Also shows monitors not yet run after a clear. |
| Monitor status this drive cycle | `01 41` | Which monitors completed today. |
| Fuel system status | `01 03` (2 bytes, bit-coded) | Open or closed loop. Trims mean nothing in open loop; the analysis should skip those samples. |
| Distance and time with MIL on | `01 21` (km), `01 4D` (min) | How long the fault has been there. |
| Since codes cleared: warm-ups, distance, time | `01 30`, `01 31`, `01 4E` | Shows a recent clear (used-car check). |
| Run time since start | `01 1F` (s) | Context for warm-up. |
| Fuel rail pressure | `01 23` or `01 59` (10 kPa per bit), `01 0A` on port injection | Separates "lean from a leak" from "lean from fuel supply". |
| Catalyst temperature B1S1 / B1S2 | `01 3C`, `01 3E` | Cat light-off, overheating with misfire. |
| O2 sensors | `01 14` (B1S1), `01 15` (B1S2): voltage and trim; wideband `01 24–2B` / `01 34–3B` | Downstream sensor activity is the owner's view of catalyst health. `01 34` is already read; its current bytes are ignored. |
| Bank 2 trims | `01 08`, `01 09` (from memory) | V engines; today only bank 1. |
| Absolute load, relative throttle, relative pedal | `01 43`, `01 45`, `01 5A` | Better load axis than `01 04` for the analysis bins. |
| Boost control | `01 70` (10 bytes, target and actual) | Turbo engines: underboost (for example fault 120308 in the demo). |
| Commanded purge, fuel level, fuel type, ethanol % | `01 2E`, `01 2F`, `01 51`, `01 52` | Purge explains trim swings at idle; fuel type lets the analysis refuse diesel. |
| Fuel rate, torque | `01 5E`, `01 61`, `01 62`, `01 63` | Consumption and load. |
| Odometer | `01 A6` | Stamp for captures (newer ECUs only). |
| OBD standard | `01 1C` | Tells which of the above to expect. |
| Calibration id, CVN, ECU name, in-use performance | `09 04`, `09 06`, `09 0A`, `09 08` | Software version of the engine unit; monitor run counts. |
| Freeze frame | `02 xx 00` | Already read in `probe()`, never shown in the UI. Show it next to the fault. |

Also free: ask up to six PIDs in one `01` request (allowed on CAN by the standard, and by the allowlist as written). 14 PIDs become 3 requests, which brings the log to the promised 2 Hz or better. The response parser must split the answer by PID length, and the engine unit must accept it; fall back to single requests if it answers `7F`.

### Needs an allowlist change (both read-only)

Add `0x06` and `0x0A` to `Allowlist.obdRead` (`Allowlist.swift:18`), extend `testReadsPass`, and keep `0x04` and `0x08` in the refused list.

| Add | Request | Why |
|---|---|---|
| Misfire counters per cylinder | `06 A2` … `06 AD` (cylinder 1–12), test ids `0B` (average over the last 10 driving cycles) and `0C` (this cycle); `06 A1` general | The most useful single addition: a rough idle with no stored code shows here first. Ignore ids beyond the cylinder count. |
| Catalyst monitor | `06 21` (bank 1), `06 22` (bank 2) | Test value against its limits: how close the catalyst is to a P0420. |
| O2 sensor monitors | `06 01` … (B1S1 onward) | Sensor response tests. |
| Other monitors, when supported | EVAP `06 39–3D`, O2 heaters `06 41…`, fuel system `06 81/82`, boost `06 85/86` (from memory; check the standard) | Each returns value, min and max, so "pass with margin" can be shown without any maker data. |
| Supported monitor ids | `06 00/20/40…` bitmaps | Same pattern as `supportedPids()`. |
| Permanent DTCs | `0A` | Codes that survive a clear until the monitor passes. |

Mode 06 results carry a "unit and scaling id" defined in the public standard; that table has to be implemented from the standard, not copied from a scan tool.

### What needs BMW-proprietary data (do not copy tables)

These need `22 xxxx` identifiers and scalings that come from BMW's diagnostic descriptions; they are not in any public standard:

- cylinder smooth-running values, injector and mixture adaptations per bank and range;
- Valvetronic and VANOS target against actual, high and low pressure fuel targets, wastegate duty;
- battery sensor state, oil level and temperature from the oil sensor, particulate filter loading;
- gearbox, chassis and body values of any kind;
- the meaning of the `19 04` snapshot and `19 06` extended records (the app stores them as hex, which is the right amount);
- BMW's fault texts for the 6-digit codes.

A clean way forward for these: keep storing raw answers, let the owner's AI reason over public sources, and accept community notes written in the contributor's own words with a source link, as `data/known_codes.json` does now.

One note on that file: 86 of its 90 source links are BMW service bulletins published by NHTSA. They are public documents. I read one entry of 71 and compared none with its bulletin, so I cannot say how close the wording is to the source. The file calls them own notes; if that holds, it is a different thing from copying a code table. Worth a spot check, and going forward: short own-words notes per code, no bulk import of bulletin text.

---

## Security findings

No path was found that sends a non-allowlisted UDS request. Details:

| Path | Result |
|---|---|
| UI and MCP arguments | Neither accepts request bytes. MCP takes a host string and a file name only. |
| `Car.ask` / `askAll` (`Car.swift:75-94`) | Both call `Allowlist.check` first. Grep shows they are the only callers of `send` / `sendAll`, and `Car.connect` the only place a `TcpTransport` is built. |
| Replay files | `ReplayTransport` never opens a socket. A crafted file can crash the process (P3, duplicate keys) but cannot reach the car. |
| Demo | `DemoTransport` never opens a socket and sits behind the same check. |
| Allowlist rules | Tested for every refused service in PLAN.md, including `19 14`, `04`, `10`, `27`, `2E`, `2F`, `31`, `11`, `3E`, `28`, `85`, `34`, `36`, `37`, and targets `00`, `F4`, `FF`. |
| Outside the allowlist by design | The UDP identification broadcast (`Transport.swift:144-153`): 6 bytes, HSFZ control word `0x11`, no UDS. |

Findings:

- **S-1 (P2) The choke point is a convention inside EnetCore.** See Design 4: `private let transport` plus a second check in `TcpTransport.write`.
- **S-2 (P2) `read_capture` and `analyze_log` follow symlinks out of the captures folder.** `Captures.url` (`Captures.swift:24-31`) compares the parent with `standardizedFileURL`, which does not resolve links. Reproduced: a `link.json` in the folder pointing outside was returned in full. It needs local write access to the folder, so the risk is low, but the function promises confinement. Fix: compare `u.resolvingSymlinksInPath()` with the resolved folder, and require a regular file. Plain traversal (`../x`, `..`, empty, absolute paths) is refused; tested.
- **S-3 (P2) MCP `host` lets the AI client choose any IPv4 address** for a TCP connection to port 6801 (`MCP.swift:16, 40`), followed by the allowlisted request bytes. Restrict it to link-local and private ranges, or drop the argument and use the address saved in Settings.
- **S-4 (P2) Discovery trusts the first answer** (`Transport.swift:160-164`): any device on the same network can answer the broadcast and be connected to. It can only feed false data (no write path exists, and the VIN is not sent), but the app would show it as the car. Prefer answers from 169.254/16, and show the address before the first read.
- **S-5 (P1) MCP crash on non-finite numbers**: P1-3.
- **S-6 (P1) SIGPIPE**: P1-1, also a remote way to kill the app for anything that can close the connection.
- **S-7 (P2) Unbounded frame length and stalled partial frame**: P2-6, P2-7. A hostile or broken gateway can exhaust memory or hang the queue.
- **S-8 (P1) VIN**: P1-4.
- **S-9 (P3) Two testers.** The app and the MCP server can both connect with tester address `0xF4`. How the gateway reacts was not tested; it may drop one. A lock file in Application Support would make the second one fail with a clear message.
- **S-10 (note) MCP robustness otherwise good.** Bad JSON, a JSON array, an unknown method, an unknown tool, wrong argument types and a missing `params` object all return an error and the server keeps running. `{"id": null}` is answered as a request; harmless.
- **S-11 (note) Hardened runtime, not sandboxed**, as PLAN.md states. `ENETDIAG_REPLAY` and `ENETDIAG_CAPTURES` are read from the environment; whoever sets the MCP config controls them, which is the owner.

---

## Suggested order

1. P0-1 sidebar.
2. P1-1, P1-2, P2-6, P2-7 in `Transport.swift` (about ten lines), with one loopback test each.
3. P1-3 and S-2 (two lines each), with tests.
4. P1-4 `Probe.redacted()`; P1-5 decision on the head unit; P1-6 status mask.
5. P2-1, P2-2, P2-3, P2-11.
6. Redesign items 2–5, then 7–9.
7. Live data: `01 01`, `01 03`, multi-PID requests, then Mode 06 misfire with the allowlist change.
