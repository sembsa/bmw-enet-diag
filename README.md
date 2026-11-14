# BMW ENET Diag

A native macOS app (macOS 26+) for read-only BMW diagnostics over an ENET cable, for any F/G-series BMW:
every control unit's faults with hints (Polish and English), live engine data from public OBD standards,
misfire counters per cylinder, a guided engine check with its analysis, and an MCP server so your own
Claude can explain any fault. A demo mode shows a simulated car.

## Read-only, by construction

Every request to the car passes `Allowlist.check` in `Car` (the only public way to the car) and again at
the socket:

| Allowed | To |
|---|---|
| UDS `19 01/02/04/06` – read fault memory, its snapshot and extended data | every control unit, or all at once (`0xDF`) |
| OBD `01 02 03 06 07 09 0A`, UDS `22` (read by identifier) | the engine unit (`0x12`) only |

Everything else is refused before a byte goes out: clearing (`14`, OBD `04`), sessions (`10`), security access
(`27`), writes, controls and routines (`2E 2F 31`), resets, downloads. Clearing faults is done in the MGU Store's
**Fault Scanner** or at a workshop. The app connects only to local addresses (ENET link-local or private),
sends one request at a time, survives a dropped connection, and never shows or sends the VIN to the AI
(the MCP server redacts it). Captures hold the VIN and stay in `~/Library/Application Support/EnetDiag/captures`.

## Build and run

```
cd app
./make-app.sh            # -> build/EnetDiag.app (icon, en/pl, ad-hoc signed)
open build/EnetDiag.app  # Connect, or Try the Demo
swift test               # allowlist, transport (fake gateway), decoding, analysis, demo, MCP, hardening
```

Plug the ENET cable into the OBD port and the Mac, ignition on (engine running for live data). If the gateway
isn't found, set its IP in Settings and allow **Local Network** for the app.

## Your own AI (MCP)

The app's AI page shows the command, e.g.

```
claude mcp add bmw-enet -- "/path/to/EnetDiag.app/Contents/MacOS/EnetDiag" --mcp
```

Tools: `read_faults`, `engine_snapshot`, `list_captures`, `read_capture`, `analyze_log`. Stdio only, no listener.

## Fault notes

`data/known_codes.json` (191 codes) – short notes in our own words, mostly from BMW service bulletins published
by NHTSA, each with its sources and a confidence. Add one by pull request, then `tools/embed-codes.sh`.

Control unit names: from cauliflowermossgrape/idrive7-apps `kit/runtime/ecus.js` (MIT). Not affiliated with BMW AG.
