"""bmw-enet-diag - read-only engine diagnostics over the ENET cable.

  python3 -m enetdiag probe   [--host IP]           everything once -> captures/probe-<time>.json
  python3 -m enetdiag faults  [--host IP]           every control unit's faults, with hints
  python3 -m enetdiag live    [--host IP]           values every second until Ctrl+C
  python3 -m enetdiag log     [--host IP] --minutes 10   -> captures/log-<time>.csv
  python3 -m enetdiag analyze captures/log-....csv  the 101F01 reading of a log
  --json prints machine output (the GUI and MCP use it); --replay CAPTURE uses a probe file instead of the car.
"""
import argparse
import csv
import json
import os
import sys
import time

from . import car
from .analyze import analyze, render
from .dme import PIDS, Dme
from .link import ReplayLink, TcpLink, discover

CAPTURES = os.environ.get('ENETDIAG_CAPTURES', 'captures')
LOG_KEYS = ['rpm', 'speed', 'coolant', 'iat', 'stft', 'ltft', 'map', 'maf', 'throttle', 'load',
            'lambda', 'lambda_cmd', 'baro', 'voltage']


def connect(a):
    if a.replay:
        return ReplayLink.from_file(a.replay), {'replay': a.replay}
    host, ident = a.host, None
    if not host:
        found = discover()
        if not found:
            sys.exit('Nie znaleziono bramki ENET. Sprawdź kabel i zapłon, albo podaj --host '
                     '(macOS: zezwól Terminalowi na "Sieć lokalna").')
        host, ident = found
    try:
        return TcpLink(host), {'host': host, 'ident': ident}
    except OSError as e:
        sys.exit('Brak połączenia z bramką %s: %s' % (host, e))


def stamp():
    return time.strftime('%Y%m%d-%H%M%S')


def read_csv(path):
    with open(path) as f:
        return [{k: (float(v) if v not in ('', None) else None) for k, v in r.items()} for r in csv.DictReader(f)]


def main(argv=None):
    p = argparse.ArgumentParser(prog='enetdiag', description='Read-only BMW engine diagnostics (ENET / HSFZ).')
    p.add_argument('cmd', choices=['probe', 'faults', 'live', 'log', 'analyze'])
    p.add_argument('file', nargs='?')
    p.add_argument('--host')
    p.add_argument('--replay')
    p.add_argument('--minutes', type=float, default=10)
    p.add_argument('--json', action='store_true')
    a = p.parse_args(argv)

    if a.cmd == 'analyze':
        rep = analyze(read_csv(a.file))
        print(json.dumps(rep, ensure_ascii=False) if a.json else render(rep))
        return

    link, where = connect(a)
    dme = Dme(link)
    try:
        if a.cmd == 'probe':
            res = dict(dme.probe(), connection=where, all_faults=car.scan(link))
            res['exchanges'] = dict(link.log)
            os.makedirs(CAPTURES, exist_ok=True)
            path = os.path.join(CAPTURES, 'probe-%s.json' % stamp())
            with open(path, 'w') as f:
                json.dump(res, f, indent=1, ensure_ascii=False)
            if a.json:
                print(json.dumps(dict(res, file=path, exchanges=None), ensure_ascii=False))
            else:
                print('Zapisano %s' % path)
                print('VIN %s | przepływomierz (PID 10): %s | PID-y: %s'
                      % (res['vin'], 'jest' if res['has_maf'] else 'BRAK', ', '.join(res['known_pids'])))
                for x in res['faults']['dme']:
                    print('  %s  %s' % (x['code'], 'ACTIVE' if x['active'] else 'stored'))
                print('  OBD: %s / oczekujące: %s' % (res['faults']['obd_stored'] or '-', res['faults']['obd_pending'] or '-'))
        elif a.cmd == 'faults':
            res = car.scan(link)
            if a.json:
                print(json.dumps(res, ensure_ascii=False))
            for f in [] if a.json else res:
                h = f['hint']
                print('%-7s %s  %-18s %s' % ('ACTIVE' if f['active'] else 'pending' if f['pending'] else 'stored',
                                             f['code'], f['unit'], h['title'] if h else '(brak opisu - zapytaj AI przez MCP)'))
                if h:
                    print('        -> ' + h['check'])
            if not a.json and not res:
                print('Brak błędów.')
        elif a.cmd in ('live', 'log'):
            keys = [k for k in LOG_KEYS if PIDS[k][0] in dme.supported()]
            out = None
            if a.cmd == 'log':
                os.makedirs(CAPTURES, exist_ok=True)
                path = os.path.join(CAPTURES, 'log-%s.csv' % stamp())
                out = csv.DictWriter(open(path, 'w', newline=''), ['t'] + LOG_KEYS)
                out.writeheader()
                print('Log -> %s (%.0f min). Nie obsługuj komputera w czasie jazdy. Ctrl+C kończy.' % (path, a.minutes),
                      file=sys.stderr)
            end = time.time() + a.minutes * 60
            try:
                while a.cmd == 'live' or time.time() < end:
                    snap = dme.snapshot(keys)
                    if out:
                        out.writerow(snap)
                    print(json.dumps(snap) if a.json or out else
                          '  '.join('%s %s%s' % (k, snap.get(k), PIDS[k][3]) for k in keys), flush=True)
                    if a.cmd == 'live':
                        time.sleep(1)
            except KeyboardInterrupt:
                pass
    finally:
        link.close()


if __name__ == '__main__':
    main()
