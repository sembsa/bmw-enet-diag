# bmw-enet-diag

Read-only BMW diagnostics over an ENET cable: every control unit's fault memory with hints, live engine
values (SAE J1979), and an analysis of fuel trims for fault **101F01** (air mass plausibility). A command
line tool, an MCP server for your own AI client, and a small macOS app. Python 3 standard library only.

## Read-only, by construction

Every request to the car goes through one function, `link.check`, before a socket is touched:

| Allowed | To |
|---|---|
| UDS `19 01/02/04/06` read fault memory, its snapshot and extended data | every control unit, or all at once (`0xDF`) |
| UDS `22 F1xx` identification | every control unit |
| OBD `01 02 03 07 09`, UDS `22` any identifier | the engine unit (`0x12`) only |

Everything else is refused (`NotAllowed`): clearing (`14`, OBD `04`), sessions (`10`), security access (`27`),
writing and control (`2E`, `2F`, `31`), resets, downloads. The tools only name operations; none takes
request bytes. Clearing faults is done in the MGU Store's **Fault Scanner** or at a workshop.
Requests go one at a time, at least 40 ms apart. Captures hold the VIN and stay out of git (`captures/`).

## Use

Plug the ENET cable into the OBD port and the Mac, ignition on (engine running for live values).

```
python3 -m enetdiag faults            # every unit's faults, with our hint where we have one
python3 -m enetdiag probe             # engine: supported values, snapshot, faults, freeze frame -> captures/
python3 -m enetdiag live              # engine values every second
python3 -m enetdiag log --minutes 10  # -> captures/log-<time>.csv
python3 -m enetdiag analyze captures/log-<time>.csv
```

No gateway found: pass `--host <ip>`, and on macOS allow the terminal (or the app) **Local Network** access
in System Settings > Privacy & Security.

For a 101F01 log: warm engine, 2-3 min at idle, then about 2500 rpm for a minute, at standstill. Don't
operate the computer while driving.

## Your own AI (MCP)

```
claude mcp add bmw-enet -- python3 -m enetdiag.mcp      # from this folder
```

Tools: `read_faults`, `engine_snapshot`, `list_captures`, `read_capture`, `analyze_log`. Stdio only, no
listener; the same allowlist applies. Ask it to explain the faults and what to check first.

## App

```
cd app && swift run
```

Read faults (with hints), probe the engine, analyse a log. It runs the Python core, so the allowlist stays
in one place.

## Tests

```
python3 -m unittest discover tests
```

A fake HSFZ gateway and replayed answers: the allowlist, framing (acks, other units, response pending),
the all-units scan, decoding, the analyzer's verdicts and the MCP server.

Control unit names: from cauliflowermossgrape/idrive7-apps `kit/runtime/ecus.js` (MIT).
