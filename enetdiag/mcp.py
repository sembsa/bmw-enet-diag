"""mcp - the toolkit as an MCP server over stdio, for the owner's own AI client (Claude Code, Claude Desktop ...).

  claude mcp add bmw-enet -- python3 -m enetdiag.mcp        (run from this folder)

Read-only like everything here: the tools only name operations, no request bytes go through.
No network listener: the client starts this process and talks over stdin/stdout.
"""
import glob
import json
import os
import sys

from . import car
from .analyze import analyze, render
from .cli import CAPTURES, read_csv
from .dme import Dme
from .link import ReplayLink, TcpLink, discover

PROTOCOL = '2025-06-18'
INSTRUCTIONS = (
    'Read-only BMW diagnostics over the owner\'s ENET cable (engine unit live data, every control unit\'s fault '
    'memory). Nothing can be written, coded or cleared from here: clearing faults is done by the owner in the '
    'MGU Store app "Fault Scanner" or at a workshop. Fault codes are BMW 6-digit hex codes per control unit; '
    'explain them for the owner in plain language, rank by what needs a workshop, and say when a code is only '
    'informational. Live reads need the car on ignition with the ENET cable plugged in; never suggest operating '
    'the computer while driving.')

HOST = {'type': 'string', 'description': 'ENET gateway IP; omit to discover it'}
TOOLS = [
    {'name': 'read_faults', 'description': 'Read every control unit\'s fault memory now (read-only), with unit names, '
     'status and our hints where we have one.', 'inputSchema': {'type': 'object', 'properties': {'host': HOST}}},
    {'name': 'engine_snapshot', 'description': 'One reading of the engine unit\'s OBD values now (rpm, coolant, fuel '
     'trims, MAP, MAF if fitted, lambda ...).', 'inputSchema': {'type': 'object', 'properties': {'host': HOST}}},
    {'name': 'list_captures', 'description': 'Saved probes and logs.', 'inputSchema': {'type': 'object', 'properties': {}}},
    {'name': 'read_capture', 'description': 'A saved probe (faults, supported values, snapshot, freeze frame).',
     'inputSchema': {'type': 'object', 'properties': {'file': {'type': 'string'}}, 'required': ['file']}},
    {'name': 'analyze_log', 'description': 'Fuel trim / air mass analysis of a saved log for fault 101F01.',
     'inputSchema': {'type': 'object', 'properties': {'file': {'type': 'string'}}, 'required': ['file']}},
]


def _capture(name):
    """A file inside the captures folder only."""
    base = os.path.realpath(CAPTURES)
    path = os.path.realpath(os.path.join(base, os.path.basename(name)))
    if not path.startswith(base + os.sep) or not os.path.isfile(path):
        raise ValueError('no such capture: %s' % name)
    return path


def _link(args):
    if os.environ.get('ENETDIAG_REPLAY'):
        return ReplayLink.from_file(os.environ['ENETDIAG_REPLAY'])
    host = args.get('host')
    if not host:
        found = discover()
        if not found:
            raise RuntimeError('no ENET gateway answered: cable plugged in, ignition on? or pass host')
        host = found[0]
    return TcpLink(host)


def call(name, args):
    if name in ('read_faults', 'engine_snapshot'):
        link = _link(args)
        try:
            return car.scan(link) if name == 'read_faults' else Dme(link).snapshot()
        finally:
            link.close()
    if name == 'list_captures':
        return sorted(os.path.basename(p) for p in glob.glob(os.path.join(CAPTURES, '*')))
    if name == 'read_capture':
        with open(_capture(args['file'])) as f:
            d = json.load(f)
        d.pop('exchanges', None)
        return d
    if name == 'analyze_log':
        rep = analyze(read_csv(_capture(args['file'])))
        return {'report': rep, 'text': render(rep)}
    raise ValueError('unknown tool %s' % name)


def handle(msg):
    mid, method = msg.get('id'), msg.get('method')
    if mid is None:
        return None                                  # notifications
    if method == 'initialize':
        res = {'protocolVersion': PROTOCOL, 'capabilities': {'tools': {}},
               'serverInfo': {'name': 'bmw-enet-diag', 'version': '0.1.0'}, 'instructions': INSTRUCTIONS}
    elif method == 'tools/list':
        res = {'tools': TOOLS}
    elif method == 'tools/call':
        p = msg.get('params') or {}
        try:
            out = call(p.get('name'), p.get('arguments') or {})
            res = {'content': [{'type': 'text', 'text': json.dumps(out, ensure_ascii=False, indent=1)}]}
        except Exception as e:                       # the client shows it; the server keeps running
            res = {'content': [{'type': 'text', 'text': '%s: %s' % (type(e).__name__, e)}], 'isError': True}
    elif method == 'ping':
        res = {}
    else:
        return {'jsonrpc': '2.0', 'id': mid, 'error': {'code': -32601, 'message': 'method not found'}}
    return {'jsonrpc': '2.0', 'id': mid, 'result': res}


def main():
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            reply = handle(json.loads(line))
        except ValueError:
            reply = {'jsonrpc': '2.0', 'id': None, 'error': {'code': -32700, 'message': 'parse error'}}
        if reply:
            sys.stdout.write(json.dumps(reply, ensure_ascii=False) + '\n')
            sys.stdout.flush()


if __name__ == '__main__':
    main()
