# bmw-enet-diag – plan

Read-only engine diagnostics over a BMW ENET cable (HSFZ, TCP 6801) for an F40 with the B38,
first job: find why the DME keeps 101F01 (air mass plausibility).

## Safety rules (the design follows from these)

1. **One choke point.** Every byte sent to the car goes through `Link.request(target, uds)`.
   It refuses anything not on the allowlist before a socket is touched:
   - targets: DME `0x12` only (head unit `0x63` and every other unit refused);
   - services: OBD `01 02 03 07 09`, UDS `22` (read by identifier), UDS `19` with
     sub-functions `01 02 04 06` (read fault memory, its snapshot and extended data).
   - everything else, including OBD `04` (clear codes), UDS `14` (clear), `10` (session),
     `27` (security access), `2E`/`2F`/`31` (write, control, routines), `3E`, `11` (reset),
     `28`, `85`, `34-37` (download), raises `NotAllowed`.
2. **No raw passthrough.** CLI, MCP and the GUI only name operations (probe, snapshot, faults,
   log); none of them accepts request bytes.
3. **Gentle on the bus.** One request at a time, at least 40 ms between requests.
4. **No head unit, no Store tooling.** Nothing from `mgu-store/deploy` is imported.
5. **Privacy.** Captures hold the VIN: `captures/` is git-ignored; MCP is stdio only, no listener.
6. **Driver safety.** Logging is started at standstill; a passenger or a parked test drives it.

## Modules

| Module | Interface | Behind it |
|---|---|---|
| `link` | `discover() -> gateway`, `TcpLink(host)`, `ReplayLink(capture)`, `.request(target, uds) -> bytes` | allowlist, HSFZ framing, acks / 7F 78 pending, pacing, recording |
| `dme` | `Dme(link)`: `.probe()`, `.snapshot()`, `.faults()` | supported-PID bitmaps, J1979 decoding, UDS 19 parsing, P-codes, freeze frame |
| `analyze` | `analyze(rows) -> report`, `render(report) -> text` | idle / 2500 rpm bins, trims, MAF vs speed-density, no-MAF engines |
| front-ends | CLI `probe/faults/live/log/analyze`; MCP stdio tools; SwiftUI app over the CLI's `--json` | presentation only |

`TcpLink` and `ReplayLink` are the two adapters at the `link` seam: tests and the analyzer run on a
real capture without the car.

## Order

1. Core + CLI `probe` and `log` + tests (fake gateway, replay, allowlist).
2. **One real capture from the car** (`probe`, then a 10 min `log`). It settles: does the B38 have
   an air mass meter (PID 10 present and non-zero), which PIDs answer, what 101F01's snapshot holds.
3. Analyzer tuned on that capture; correct the 101F01 checklist if the engine has no MAF.
4. MCP server (analyze logs, read faults / snapshot live through the same `Dme`).
5. SwiftUI app: connect, live gauges, record a log, analysis view; Local Network usage key.
6. Repo: only with consent; publish without captures.
