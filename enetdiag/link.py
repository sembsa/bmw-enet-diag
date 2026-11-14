"""link - the only way to the car: HSFZ over the ENET cable, read-only by construction.

Link.request(target, uds) checks the request against the allowlist before anything is sent;
TcpLink talks to the car's gateway, ReplayLink answers from a capture (tests, offline analysis).
"""
import json
import socket
import struct
import time

HSFZ_DIAG_PORT = 6801
HSFZ_IDENT_PORT = 6811
TESTER = 0xF4
DME = 0x12

FUNCTIONAL = 0xDF              # every control unit at once
# OBD-II read services (SAE J1979): current data, freeze frame, stored / pending codes, vehicle info
OBD_READ = {0x01, 0x02, 0x03, 0x07, 0x09}
UDS_READ_DID = 0x22
UDS_READ_DTC = 0x19
DTC_SUBS = {0x01, 0x02, 0x04, 0x06}     # count, by status, snapshot, extended data
MIN_GAP = 0.04


class NotAllowed(Exception):
    pass


def check(target, uds):
    """Raise NotAllowed unless the request only reads. Every unit (and all at once): fault memory and
    identification (22 F1xx); the engine unit also OBD current data and any 22 identifier."""
    uds = bytes(uds)
    if not 0x01 <= target <= 0xFE or target == TESTER:
        raise NotAllowed('target 0x%02X refused' % target)
    if not uds:
        raise NotAllowed('empty request')
    sid = uds[0]
    if sid == UDS_READ_DTC and len(uds) >= 2 and uds[1] in DTC_SUBS:
        return
    if sid == UDS_READ_DID and len(uds) >= 3 and (target == DME or uds[1] == 0xF1):
        return
    if target == DME and sid in OBD_READ:
        return
    raise NotAllowed('service %s to 0x%02X refused (read-only tool)' % (uds[:2].hex(' '), target))


class Link:
    """Read-only request/response to one control unit. Subclasses implement _send."""

    def __init__(self):
        self.log = []          # [(request hex, response hex or None)] for captures

    def request(self, target, uds):
        check(target, uds)
        try:
            resp = self._send(target, bytes(uds))
        except TimeoutError:
            resp = None
        self.log.append(('%02x:%s' % (target, bytes(uds).hex()), resp.hex() if resp is not None else None))
        return resp

    def request_all(self, uds):
        """The same read to every unit at once: {unit address: response}."""
        check(FUNCTIONAL, uds)
        resp = self._send_all(bytes(uds))
        self.log.append(('%02x:%s' % (FUNCTIONAL, bytes(uds).hex()), {'%02x' % a: r.hex() for a, r in resp.items()}))
        return resp

    def close(self):
        pass


class TcpLink(Link):
    def __init__(self, host, port=HSFZ_DIAG_PORT, timeout=3.0):
        super().__init__()
        self.s = socket.create_connection((host, port), timeout=timeout)
        self.timeout, self.last = timeout, 0.0

    def _read(self, n):
        buf = b''
        while len(buf) < n:
            c = self.s.recv(n - len(buf))
            if not c:
                raise IOError('the gateway closed the connection')
            buf += c
        return buf

    def _send(self, target, uds):
        wait = self.last + MIN_GAP - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        self.s.sendall(struct.pack('>IH', 2 + len(uds), 0x0001) + bytes([TESTER, target]) + uds)
        deadline = time.monotonic() + self.timeout
        try:
            while time.monotonic() < deadline:
                self.s.settimeout(max(0.2, deadline - time.monotonic()))
                try:
                    blen, ctrl = struct.unpack('>IH', self._read(6))
                except socket.timeout:
                    raise TimeoutError
                body = self._read(blen)
                src, payload = body[0], body[2:]
                if ctrl != 0x0001 or src != target or not payload:
                    continue                        # 0x0002 acks, alive checks, other units
                if len(payload) >= 3 and payload[0] == 0x7F and payload[2] == 0x78:
                    deadline = time.monotonic() + 5  # response pending
                    continue
                return payload
            raise TimeoutError
        finally:
            self.last = time.monotonic()

    def _send_all(self, uds, quiet=1.5, limit=15.0):
        self.s.sendall(struct.pack('>IH', 2 + len(uds), 0x0001) + bytes([TESTER, FUNCTIONAL]) + uds)
        out, end = {}, time.monotonic() + limit
        last = time.monotonic()
        try:
            while time.monotonic() < end and time.monotonic() - last < quiet:
                self.s.settimeout(max(0.1, min(quiet - (time.monotonic() - last), end - time.monotonic())))
                try:
                    blen, ctrl = struct.unpack('>IH', self._read(6))
                except socket.timeout:
                    break
                body = self._read(blen)
                src, payload = body[0], body[2:]
                if ctrl != 0x0001 or not payload:
                    continue
                last = time.monotonic()
                if len(payload) >= 3 and payload[0] == 0x7F and payload[2] == 0x78:
                    continue
                out[src] = payload
        finally:
            self.last = time.monotonic()
        return out

    def close(self):
        try:
            self.s.close()
        except OSError:
            pass


class ReplayLink(Link):
    """Answers from a capture's exchanges: {"12:0100": "4100be3fa813", ...}; unknown -> None."""

    def __init__(self, exchanges):
        super().__init__()
        self.ex = exchanges

    @classmethod
    def from_file(cls, path):
        with open(path) as f:
            return cls(json.load(f)['exchanges'])

    def _send(self, target, uds):
        r = self.ex.get('%02x:%s' % (target, uds.hex()))
        if r is None:
            raise TimeoutError
        return bytes.fromhex(r)

    def _send_all(self, uds):
        r = self.ex.get('%02x:%s' % (FUNCTIONAL, uds.hex())) or {}
        return {int(a, 16): bytes.fromhex(h) for a, h in r.items()}


def discover(timeout=4.0, broadcast=('169.254.255.255', '255.255.255.255')):
    """The ENET gateway: (ip, ident text) from the first answer to HSFZ identification, or None.
    macOS may need Local Network permission for the terminal; pass --host when this finds nothing."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.settimeout(0.5)
    end = time.monotonic() + timeout
    try:
        while time.monotonic() < end:
            for dst in broadcast:
                try:
                    s.sendto(bytes([0, 0, 0, 0, 0, 0x11]), (dst, HSFZ_IDENT_PORT))
                except OSError:
                    pass
            try:
                data, addr = s.recvfrom(2048)
                if len(data) > 6:
                    return addr[0], data[6:].decode('ascii', 'replace')
            except socket.timeout:
                pass
    finally:
        s.close()
    return None
