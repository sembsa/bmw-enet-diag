"""dme - what the engine unit tells, decoded: public SAE J1979 PIDs and UDS fault memory.

Dme(link).snapshot() -> {name: value}, .faults() -> {...}, .probe() -> everything for a capture.
Only reads: every request goes through link.request, which refuses anything else.
"""
import time

from .link import DME

u8 = lambda d: d[0]
u16 = lambda d: d[0] * 256 + d[1]
# key: (pid, bytes, decode, unit) - SAE J1979 formulas
PIDS = {
    'load':        (0x04, 1, lambda d: u8(d) * 100 / 255, '%'),
    'coolant':     (0x05, 1, lambda d: u8(d) - 40, '°C'),
    'stft':        (0x06, 1, lambda d: (u8(d) - 128) * 100 / 128, '%'),
    'ltft':        (0x07, 1, lambda d: (u8(d) - 128) * 100 / 128, '%'),
    'map':         (0x0B, 1, lambda d: u8(d), 'kPa'),
    'rpm':         (0x0C, 2, lambda d: u16(d) / 4, 'rpm'),
    'speed':       (0x0D, 1, lambda d: u8(d), 'km/h'),
    'timing':      (0x0E, 1, lambda d: u8(d) / 2 - 64, '°'),
    'iat':         (0x0F, 1, lambda d: u8(d) - 40, '°C'),
    'maf':         (0x10, 2, lambda d: u16(d) / 100, 'g/s'),
    'throttle':    (0x11, 1, lambda d: u8(d) * 100 / 255, '%'),
    'baro':        (0x33, 1, lambda d: u8(d), 'kPa'),
    'lambda':      (0x34, 4, lambda d: u16(d) * 2 / 65536, ''),
    'voltage':     (0x42, 2, lambda d: u16(d) / 1000, 'V'),
    'abs_load':    (0x43, 2, lambda d: u16(d) * 100 / 255, '%'),
    'lambda_cmd':  (0x44, 2, lambda d: u16(d) * 2 / 65536, ''),
    'rel_throttle': (0x45, 1, lambda d: u8(d) * 100 / 255, '%'),
    'ambient':     (0x46, 1, lambda d: u8(d) - 40, '°C'),
    'pedal':       (0x49, 1, lambda d: u8(d) * 100 / 255, '%'),
    'oil':         (0x5C, 1, lambda d: u8(d) - 40, '°C'),
}
BY_PID = {v[0]: k for k, v in PIDS.items()}
VIN_DID = bytes([0xF1, 0x90])


def pcode(b1, b2):
    """Two DTC bytes -> 'P0171' (SAE J2012)."""
    return 'PCBU'[b1 >> 6] + '%X%X%02X' % ((b1 >> 4) & 3, b1 & 0xF, b2)


class Dme:
    def __init__(self, link):
        self.link = link
        self._sup = None

    def _ask(self, uds):
        return self.link.request(DME, uds)

    def supported(self):
        """PIDs the engine unit answers (bitmaps 01 00, 01 20, ...)."""
        if self._sup is None:
            sup, base = set(), 0
            while base <= 0xC0:
                r = self._ask([0x01, base])
                if not r or r[0] != 0x41 or len(r) < 6:
                    break
                bits = int.from_bytes(r[2:6], 'big')
                sup |= {base + i + 1 for i in range(32) if bits & (1 << (31 - i))}
                if base + 0x20 not in sup:
                    break
                base += 0x20
            self._sup = sup
        return self._sup

    def _pid(self, sid, key, frame=None):
        pid, n, dec, _ = PIDS[key]
        r = self._ask([sid, pid] + ([frame] if frame is not None else []))
        off = 2 + (1 if frame is not None else 0)
        if not r or r[0] != sid + 0x40 or r[1] != pid or len(r) < off + n:
            return None
        return round(dec(r[off:off + n]), 3)

    def snapshot(self, keys=None):
        """{key: value} for the wanted keys the unit supports; t = seconds since the epoch."""
        sup = self.supported()
        out = {'t': round(time.time(), 2)}
        for k in keys or PIDS:
            if PIDS[k][0] in sup:
                out[k] = self._pid(0x01, k)
        return out

    def faults(self):
        """The engine unit's fault memory (BMW 6-digit codes) and the OBD codes it reports."""
        out = {'dme': [], 'obd_stored': [], 'obd_pending': []}
        r = self._ask([0x19, 0x02, 0xFF])
        if r and r[:2] == b'\x59\x02':
            for i in range(3, len(r) - 3, 4):
                st = r[i + 3]
                out['dme'].append({'code': r[i:i + 3].hex().upper(), 'status': st,
                                   'active': bool(st & 0x01), 'confirmed': bool(st & 0x08),
                                   'pending': bool(st & 0x04)})
        for sid, key in ((0x03, 'obd_stored'), (0x07, 'obd_pending')):
            r = self._ask([sid])
            if r and r[0] == sid + 0x40:
                data = r[2:] if len(r) % 2 == 0 else r[1:]   # CAN: a count byte after the SID
                out[key] = [pcode(data[i], data[i + 1]) for i in range(0, len(data) - 1, 2) if data[i] or data[i + 1]]
        return out

    def fault_details(self, code):
        """Raw snapshot (19 04) and extended data (19 06) of one BMW code: BMW encodes them, kept as hex."""
        dtc = list(bytes.fromhex(code))
        res = {}
        for sub, name in ((0x04, 'snapshot'), (0x06, 'extended')):
            r = self._ask([0x19, sub] + dtc + [0xFF])
            res[name] = r.hex() if r else None
        return res

    def freeze_frame(self):
        """OBD freeze frame 0 (service 02): the conditions when an emission code was stored."""
        sup = self.supported()
        r = self._ask([0x02, 0x02, 0x00])
        out = {'trigger': pcode(r[3], r[4]) if r and len(r) >= 5 and r[0] == 0x42 and (r[3] or r[4]) else None}
        if out['trigger']:
            for k in PIDS:
                if PIDS[k][0] in sup:
                    out[k] = self._pid(0x02, k, frame=0)
        return out

    def vin(self):
        r = self._ask([0x22] + list(VIN_DID))
        if r and r[:3] == b'\x62\xf1\x90':
            return r[3:].decode('ascii', 'replace').strip()
        r = self._ask([0x09, 0x02])
        return r[3:].decode('ascii', 'replace').strip() if r and r[0] == 0x49 else None

    def probe(self):
        """Everything worth keeping from one visit, for the first look and as a replay capture."""
        f = self.faults()
        details = {x['code']: self.fault_details(x['code']) for x in f['dme']}
        sup = self.supported()
        return {
            'at': time.strftime('%Y-%m-%dT%H:%M:%S'),
            'vin': self.vin(),
            'supported_pids': sorted('%02X' % p for p in sup),
            'known_pids': sorted(k for k in PIDS if PIDS[k][0] in sup),
            'has_maf': 0x10 in sup,
            'snapshot': self.snapshot(),
            'faults': f,
            'fault_details': details,
            'freeze_frame': self.freeze_frame(),
        }
