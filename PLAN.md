# bmw-enet-diag – plan: a native macOS app

Read-only BMW diagnostics over any owner's ENET cable, as one native Swift app, for any BMW with an
ENET (F / G series) and any fault: every control unit's faults with hints, live engine values, a guided
engine check (log + analysis), and an MCP server for the owner's own Claude, which explains any code.
Clearing faults stays in the Store's Fault Scanner or a workshop. 101F01 on an F40 B38 is the first case,
not the scope.

## Why the first app showed no window

`swift run` started a bare executable: no `.app` bundle, no Info.plist, so macOS never made it a regular
foreground app (the process ran, no window). The new app is a real bundle: `EnetDiag.app` with an
Info.plist (bundle id, `NSLocalNetworkUsageDescription` for gateway discovery), ad-hoc signed.

## Safety (unchanged rules, now in Swift)

- **One choke point.** `Car` is the only public way to the car. Before any byte goes out it calls
  `Allowlist.check(target, request)`; the transports underneath are `internal`, so the app, the MCP mode
  and anything else in the binary cannot reach them.
  - every unit and all at once (`0xDF`): UDS `19 01/02/04/06` (read fault memory), `22 F1xx` (identification);
  - engine unit `0x12` only: OBD `01 02 03 07 09`, UDS `22` any identifier;
  - everything else refused (`14` / OBD `04` clear, `10` session, `27` security access, `2E 2F 31` write,
    control, routines, `11` reset, `34-37` download, `3E`, `28`, `85`) — a test lists each one.
- **Named operations only.** UI and MCP offer `faults`, `snapshot`, `probe`, `log`; no request bytes in.
- One request at a time, at least 40 ms apart.
- MCP: stdio only (no listener); files only inside the app's captures folder.
- Captures hold the VIN: kept in `~/Library/Application Support/EnetDiag/captures`, never in git.
- Not sandboxed (raw TCP/UDP to a link-local gateway, a CLI mode for MCP); hardened runtime, ad-hoc signed.
- Logging starts at standstill; the UI says not to operate the Mac while driving.

## Modules

| Module | Interface | Behind it |
|---|---|---|
| `Car` (actor) | `Car.connect(host: String?) async throws`, `Car(replay: URL)`; `.faults()`, `.snapshot()`, `.probe()`, `.close()` | allowlist, HSFZ framing (acks, `7F xx 78`, other units' frames), functional scan, pacing, supported-PID bitmaps, J1979 decoding, UDS 19 parsing, P-codes, freeze frame, exchange recording |
| `Analysis` | `analyze([Sample]) -> Report` (findings, each: check, severity, verdict, the values behind it, related fault kinds) | a set of checks, each skipped when the car doesn't give its values: mixture (trims at idle vs 2500 rpm: leak / lean / rich / normal), air mass (MAF vs speed-density, as a ratio between bins so no engine size is needed), warm-up (coolant reaches operating temperature: thermostat), charging (voltage running), idle vacuum (MAP), lambda tracking (actual vs commanded) |
| `Hints` | `hint(address, code) -> Hint?`, `kind(address, code)` | our own notes for codes people have looked into (a JSON resource anyone can add to by pull request), and a coarse kind per unit (engine, body, assist, infotainment …) for the rest; everything else goes to the owner's AI |
| `Captures` | `save(probe)`, `startLog() -> LogWriter`, `list()`, `load(name)` | Application Support folder, CSV, path confinement |
| `MCP` | `EnetDiag --mcp` (stdio) | JSON-RPC: `initialize`, `tools/list`, `tools/call` over `Car`, `Analysis`, `Captures` |
| UI | SwiftUI | presentation only |

The seam inside `Car` is `Transport` (internal): `TcpTransport` (the car) and `ReplayTransport` (a saved
probe) are its two adapters; the tests use both and a loopback fake gateway.

## Screens

1. **Connection bar**: gateway found / IP field, VIN, status; "read-only" badge.
2. **Faults**: every unit's faults in a table — status (active / pending / stored), code, unit, our hint
   and its severity (workshop / watch / info); "copy for AI" (codes as text); "clear in the Store's
   Fault Scanner" note.
3. **Live**: rpm, coolant, intake temp, MAP, MAF (when fitted), STFT / LTFT, lambda; a trims chart (Swift Charts).
4. **101F01 log**: start / stop a guided log (warm engine, 2–3 min idle, 1 min at 2500 rpm), then the
   analysis with its verdict.
5. **Captures**: probes and logs, open / reveal in Finder / analyse.
6. **AI (MCP)**: the command to add it to Claude Code (`claude mcp add bmw-enet -- <app>/Contents/MacOS/EnetDiag --mcp`) and the Claude Desktop JSON, with copy buttons.

## Project layout

```
app/
  Package.swift              EnetCore (library), EnetDiag (executable), EnetCoreTests
  Sources/EnetCore/          Allowlist, Transport (TCP, replay), Car, Decode, Analysis, Hints, Captures, MCP
  Sources/EnetDiag/          SwiftUI app + `--mcp` entry
  Resources/Info.plist
  Tests/EnetCoreTests/       the Python suite, ported
  make-app.sh                swift build -c release -> EnetDiag.app (Info.plist, icon, ad-hoc codesign)
```

## Steps, each with its check

1. **Bundle first**: an empty window from `EnetDiag.app` (`open`, then a window is listed by System Events).
2. **EnetCore** ported from Python with the tests ported 1:1 (`swift test` green).
3. **Screens** 1–6, run against a replayed probe (`--replay`), screenshots checked.
4. **MCP mode**: registered in Claude Code and every tool called once from it.
5. **Python removed** once the Swift tests cover it all: one allowlist, not two.
6. **Car test** with the owner (F40 B38, 101F01): faults, probe, a 5-minute log; the capture becomes a test
   fixture (VIN removed).
7. Repo: published only with the owner's consent, without captures.
