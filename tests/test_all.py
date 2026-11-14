"""python3 -m unittest discover tests   (no car needed: a fake gateway and replayed answers)"""
import json
import os
import socket
import struct
import tempfile
import threading
import unittest

from enetdiag import car, mcp
from enetdiag.analyze import analyze, render
from enetdiag.dme import Dme, pcode
from enetdiag.link import NotAllowed, ReplayLink, TcpLink, check


class Allowlist(unittest.TestCase):
    def test_reads_pass(self):
        for t, r in [(0x12, [0x01, 0x0C]), (0x12, [0x02, 0x02, 0x00]), (0x12, [0x03]), (0x12, [0x07]),
                     (0x12, [0x09, 0x02]), (0x12, [0x22, 0x58, 0x89]), (0x40, [0x19, 0x02, 0xFF]),
                     (0xDF, [0x19, 0x02, 0xFF]), (0x63, [0x22, 0xF1, 0x90]), (0x12, [0x19, 0x04, 0x10, 0x1F, 0x01, 0xFF])]:
            check(t, r)

    def test_everything_else_refused(self):
        bad = [(0x12, [0x04]), (0x12, [0x14, 0xFF, 0xFF, 0xFF]), (0xDF, [0x14, 0xFF, 0xFF, 0xFF]),
               (0x12, [0x10, 0x03]), (0x12, [0x27, 0x01]), (0x12, [0x2E, 0x01, 0x02]), (0x40, [0x2F, 0x45, 0x01, 0x03]),
               (0x12, [0x31, 0x01, 0x30, 0x00]), (0x12, [0x11, 0x01]), (0x12, [0x3E, 0x00]), (0x12, [0x28, 0x00]),
               (0x12, [0x85, 0x02]), (0x12, [0x34]), (0x12, [0x19, 0x14]), (0x63, [0x22, 0x17, 0x2A]),
               (0x40, [0x01, 0x0C]), (0xF4, [0x19, 0x02, 0xFF]), (0x00, [0x19, 0x02, 0xFF]), (0x12, [])]
        for t, r in bad:
            with self.assertRaises(NotAllowed, msg='%02x %s' % (t, bytes(r).hex())):
                check(t, r)

    def test_refused_before_sending(self):
        link = ReplayLink({})
        link._send = lambda *a: self.fail('sent')
        with self.assertRaises(NotAllowed):
            link.request(0x12, [0x14, 0xFF, 0xFF, 0xFF])
        with self.assertRaises(NotAllowed):
            link.request_all([0x14, 0xFF, 0xFF, 0xFF])


def frame(src, tgt, payload, ctrl=1):
    return struct.pack('>IH', 2 + len(payload), ctrl) + bytes([src, tgt]) + payload


class FakeGateway(unittest.TestCase):
    """HSFZ framing: acks, other units' frames and 'response pending' are skipped."""

    def serve(self, replies):
        srv = socket.socket()
        srv.bind(('127.0.0.1', 0))
        srv.listen(1)
        got = []

        def run():
            c, _ = srv.accept()
            for rep in replies:
                hdr = c.recv(6)
                n = struct.unpack('>I', hdr[:4])[0]
                got.append(hdr + c.recv(n))
                c.sendall(b''.join(rep))
            c.recv(1)                     # as the real gateway: open until the tester leaves
            c.close()
            srv.close()
        threading.Thread(target=run, daemon=True).start()
        return srv.getsockname()[1], got

    def test_request_and_functional(self):
        req = frame(0xF4, 0x12, bytes([0x01, 0x0C]))
        port, got = self.serve([
            [frame(0xF4, 0x12, bytes([0x01, 0x0C]), ctrl=2), frame(0x40, 0xF4, b'\x7f\x19\x11'),
             frame(0x12, 0xF4, b'\x7f\x01\x78'), frame(0x12, 0xF4, bytes([0x41, 0x0C, 0x0C, 0x80]))],
            [frame(0x12, 0xF4, bytes.fromhex('5902ff101f0109')), frame(0x5D, 0xF4, bytes.fromhex('5902ff800abf08')),
             frame(0x29, 0xF4, bytes.fromhex('5902ff'))],
        ])
        link = TcpLink('127.0.0.1', port, timeout=2)
        self.assertEqual(Dme(link)._pid(0x01, 'rpm'), 800.0)
        self.assertEqual(got[0], req)
        link._send_all.__func__.__defaults__ = (0.3, 3.0)     # shorter quiet time in the test
        faults = car.scan(link)
        link.close()
        self.assertEqual([(f['address'], f['code'], f['active']) for f in faults], [('12', '101F01', True), ('5D', '800ABF', False)])
        self.assertEqual(faults[0]['hint']['severity'], 'service')
        self.assertEqual(got[1][-3:], bytes([0x19, 0x02, 0xFF]))
        self.assertEqual(got[1][7], 0xDF)


def replay():
    ex = {'12:0100': '4100be1fa813', '12:0120': '41208005b011', '12:0140': '4140fed08c01',
          '12:010c': '410c0c80', '12:0105': '41057d', '12:0106': '410690', '12:0107': '41078a', '12:010b': '410b20',
          '12:0110': '41100190', '12:010f': '410f3c', '12:010d': '410d00', '12:0111': '41110c',
          '12:1902ff': '5902ff101f0109', '12:03': '43010171', '12:07': '4700', '12:22f190': '62f190' + b'WBA00000000000000'.hex(),
          '12:0202 00'.replace(' ', ''): '420200000000',
          'df:1902ff': {'12': '5902ff101f0109', '37': '5902ffb7f50009'}}
    return ReplayLink(ex)


class Engine(unittest.TestCase):
    def test_probe_from_replay(self):
        link = replay()
        p = Dme(link).probe()
        self.assertEqual(p['vin'], 'WBA00000000000000')
        self.assertTrue(p['has_maf'])
        self.assertEqual(p['snapshot']['rpm'], 800.0)
        self.assertEqual(p['snapshot']['coolant'], 85)
        self.assertAlmostEqual(p['snapshot']['stft'], 12.5)
        self.assertEqual(p['faults']['dme'][0]['code'], '101F01')
        self.assertEqual(p['faults']['obd_stored'], ['P0171'])
        self.assertIsNone(p['freeze_frame']['trigger'])
        self.assertEqual([f['unit'] for f in car.scan(link)], ['DME engine', 'RAM audio'])

    def test_pcode(self):
        self.assertEqual(pcode(0x01, 0x71), 'P0171')
        self.assertEqual(pcode(0xC1, 0x00), 'U0100')


def rows(idle_trim, mid_trim, coolant=85, maf=True):
    out = []
    for i in range(30):
        out.append({'rpm': 780, 'speed': 0, 'coolant': coolant, 'stft': idle_trim / 2, 'ltft': idle_trim / 2,
                    'map': 32, 'iat': 25, 'maf': 3.0 if maf else None})
        out.append({'rpm': 2600, 'speed': 0, 'coolant': coolant, 'stft': mid_trim / 2, 'ltft': mid_trim / 2,
                    'map': 45, 'iat': 25, 'maf': 13.5 if maf else None})
    return out


class Analyzer(unittest.TestCase):
    def test_verdicts(self):
        self.assertEqual(analyze(rows(16, 3))['verdict'], 'leak')
        self.assertEqual(analyze(rows(14, 13))['verdict'], 'lean_everywhere')
        self.assertEqual(analyze(rows(2, -1))['verdict'], 'trims_normal')
        self.assertEqual(analyze(rows(-12, -10))['verdict'], 'rich')
        self.assertEqual(analyze(rows(16, 3, coolant=40))['verdict'], 'not_warm')
        r = analyze(rows(16, 3, maf=False))
        self.assertFalse(r['has_maf'])
        self.assertIn('NIESZCZELNO', render(r))


class Mcp(unittest.TestCase):
    def test_protocol_and_paths(self):
        init = mcp.handle({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {}})
        self.assertIn('Read-only', init['result']['instructions'])
        names = [t['name'] for t in mcp.handle({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'})['result']['tools']]
        self.assertNotIn('clear', ' '.join(names))
        self.assertIsNone(mcp.handle({'jsonrpc': '2.0', 'method': 'notifications/initialized'}))
        bad = mcp.handle({'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call',
                          'params': {'name': 'read_capture', 'arguments': {'file': '../../etc/passwd'}}})
        self.assertTrue(bad['result']['isError'])

    def test_faults_and_analysis_through_mcp(self):
        d = tempfile.mkdtemp()
        cap = os.path.join(d, 'probe.json')
        with open(cap, 'w') as f:
            json.dump({'exchanges': replay().ex}, f)
        os.environ['ENETDIAG_REPLAY'] = cap
        try:
            r = mcp.handle({'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call', 'params': {'name': 'read_faults', 'arguments': {}}})
        finally:
            del os.environ['ENETDIAG_REPLAY']
        self.assertIn('101F01', r['result']['content'][0]['text'])
        old = mcp.CAPTURES
        mcp.CAPTURES = d
        try:
            with open(os.path.join(d, 'log-1.csv'), 'w') as f:
                keys = ['rpm', 'speed', 'coolant', 'stft', 'ltft', 'map', 'iat', 'maf']
                f.write(','.join(keys) + '\n')
                for x in rows(16, 3):
                    f.write(','.join('' if x[k] is None else str(x[k]) for k in keys) + '\n')
            r = mcp.handle({'jsonrpc': '2.0', 'id': 5, 'method': 'tools/call',
                            'params': {'name': 'analyze_log', 'arguments': {'file': 'log-1.csv'}}})
            self.assertIn('"leak"', r['result']['content'][0]['text'])
        finally:
            mcp.CAPTURES = old


if __name__ == '__main__':
    unittest.main()
