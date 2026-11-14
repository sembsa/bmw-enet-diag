"""car - every control unit's fault memory in one read, named, with the owner's hints. Read-only.

scan(link) -> [{unit, address, code, active, confirmed, pending, status, hint}]
Clearing is not here on purpose: the Store's Fault Scanner (or a workshop) does that.
"""
from .hints import hint

# control unit names by diagnostic address: from cauliflowermossgrape/idrive7-apps kit/runtime/ecus.js (MIT)
UNITS = {
    0x01: 'ACSM airbag', 0x06: 'ICAM cameras', 0x07: 'SME HV battery', 0x08: 'SRR corner radar',
    0x0D: 'HKFM tailgate', 0x10: 'BDC gateway', 0x12: 'DME engine', 0x13: 'DME 2', 0x14: 'OBC charger',
    0x18: 'EGS gearbox', 0x1D: 'TFM fuel tank', 0x20: 'SRR corner radar', 0x21: 'FRR front radar',
    0x23: 'SAS assist sensors', 0x28: 'SRR corner radar', 0x29: 'DSC brakes', 0x2A: 'SRR corner radar',
    0x2C: 'USS park sensors', 0x30: 'EPS steering', 0x37: 'RAM audio', 0x38: 'VTG xDrive',
    0x39: 'DSC brake booster', 0x3A: 'EME e-motor', 0x40: 'BDC body', 0x43: 'FLM headlight',
    0x44: 'FLM headlight', 0x45: 'DCS driver camera', 0x56: 'FZD roof', 0x5D: 'KAFAS camera',
    0x5E: 'GWS gear selector', 0x60: 'KOMBI cluster', 0x61: 'ATM telematics', 0x63: 'Head unit',
    0x64: 'PDC parking', 0x67: 'ZBE controller', 0x6D: 'SM seat module', 0x76: 'VDP dampers',
    0x78: 'IHKA climate',
}


def unit_name(addr):
    return UNITS.get(addr, 'ECU 0x%02X' % addr)


def parse_dtcs(resp):
    """59 02 <mask> (<3-byte code> <status>)* -> [(code, status)]"""
    if not resp or resp[:2] != b'\x59\x02':
        return []
    return [(resp[i:i + 3].hex().upper(), resp[i + 3]) for i in range(3, len(resp) - 3, 4)]


def scan(link):
    out = []
    for addr, resp in sorted(link.request_all([0x19, 0x02, 0xFF]).items()):
        for code, st in parse_dtcs(resp):
            out.append({'unit': unit_name(addr), 'address': '%02X' % addr, 'code': code, 'status': st,
                        'active': bool(st & 0x01), 'pending': bool(st & 0x04), 'confirmed': bool(st & 0x08),
                        'hint': hint(addr, code)})
    # active first, then the engine, then by unit
    out.sort(key=lambda f: (not f['active'], f['address'] != '12', f['address'], f['code']))
    return out
