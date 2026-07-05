"""
dom6.py  -  Dominions 6 save-file parsing library
XOR key: 0x4F
Formats: .2h (orders), .trn (turn/map state), ftherlnd (global state)

Modules:
  - Primitives: BinReader, XOR codec
  - Headers: read_header / FileHeader
  - Commanders: scan_commanders (dynamic, no hardcoded names)
  - Provinces: parse_provinces (from ftherlnd), load_province_names (from .trn)
  - Sites: load_site_db (from MagicSites.csv)
  - Loaders: load / load_nation / load_trn / load_ftherlnd
"""

from __future__ import annotations
import csv
import struct
from pathlib import Path
from dataclasses import dataclass, field
from typing import Iterator

SAVEDIR = Path(__file__).parent.parent   # game files in mptest/
DATADIR = Path(__file__).parent.parent / 'data'
XOR_KEY = 0x4F

# ---------------------------------------------------------------------------
# Low-level binary reader
# ---------------------------------------------------------------------------

class BinReader:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def __len__(self):
        return len(self.data)

    @property
    def remaining(self):
        return len(self.data) - self.pos

    def seek(self, pos: int):
        self.pos = pos
        return self

    def peek(self, n=1) -> bytes:
        return self.data[self.pos : self.pos + n]

    def read(self, n: int) -> bytes:
        chunk = self.data[self.pos : self.pos + n]
        self.pos += n
        return chunk

    def u8(self)  -> int: return struct.unpack_from('<B', self.data, self._adv(1))[0]
    def u16(self) -> int: return struct.unpack_from('<H', self.data, self._adv(2))[0]
    def u32(self) -> int: return struct.unpack_from('<I', self.data, self._adv(4))[0]
    def i16(self) -> int: return struct.unpack_from('<h', self.data, self._adv(2))[0]
    def i32(self) -> int: return struct.unpack_from('<i', self.data, self._adv(4))[0]

    def _adv(self, n):
        p = self.pos; self.pos += n; return p

    def at_u8(self, o)  -> int: return struct.unpack_from('<B', self.data, o)[0]
    def at_u16(self, o) -> int: return struct.unpack_from('<H', self.data, o)[0]
    def at_u32(self, o) -> int: return struct.unpack_from('<I', self.data, o)[0]
    def at_i16(self, o) -> int: return struct.unpack_from('<h', self.data, o)[0]

    def hex(self, start: int, length: int) -> str:
        return ' '.join(f'{b:02X}' for b in self.data[start:start+length])

    def hexdump(self, start: int, length: int, width: int = 16) -> str:
        lines = []
        for i in range(0, length, width):
            chunk = self.data[start+i : start+i+width]
            h = ' '.join(f'{b:02X}' for b in chunk)
            a = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
            lines.append(f'  {start+i:06X}  {h:<{width*3}}  {a}')
        return '\n'.join(lines)

# ---------------------------------------------------------------------------
# XOR string codec
# ---------------------------------------------------------------------------

def xor_decode(data: bytes, start: int, max_len: int = 256) -> str:
    """Decode XOR-encoded null-terminated string (terminator = 0x4F = XOR of 0x00)."""
    result = []
    for i in range(start, min(start + max_len, len(data))):
        b = data[i]
        if b == XOR_KEY:  # null terminator
            break
        c = b ^ XOR_KEY
        result.append(chr(c) if 32 <= c < 127 else f'\\x{c:02x}')
    return ''.join(result)

def xor_encode(s: str) -> bytes:
    return bytes((ord(c) ^ XOR_KEY) for c in s) + bytes([XOR_KEY])

def find_xor_strings(data: bytes, min_len: int = 4, max_len: int = 256,
                     only_ascii: bool = True) -> Iterator[tuple[int, str]]:
    """Scan binary data for all XOR-encoded printable strings."""
    i = 0
    while i < len(data):
        if data[i] == XOR_KEY:
            i += 1
            continue
        c = data[i] ^ XOR_KEY
        if 32 <= c < 127:
            end = i
            chars = []
            while end < len(data) and end < i + max_len:
                b = data[end]
                if b == XOR_KEY:
                    break
                d = b ^ XOR_KEY
                if only_ascii and not (32 <= d < 127):
                    break
                chars.append(chr(d))
                end += 1
            s = ''.join(chars)
            if len(s) >= min_len and data[end] == XOR_KEY:
                yield (i, s)
                i = end + 1
                continue
        i += 1

def find_literal(data: bytes, s: str) -> list[int]:
    """Find all offsets of a literal XOR-encoded string."""
    encoded = xor_encode(s)[:-1]  # without terminator, for substring search
    offsets = []
    start = 0
    while True:
        idx = data.find(encoded, start)
        if idx == -1:
            break
        offsets.append(idx)
        start = idx + 1
    return offsets

# ---------------------------------------------------------------------------
# File headers
# ---------------------------------------------------------------------------

@dataclass
class FileHeader:
    magic: bytes
    file_type: int      # 1=ftherlnd, 2=.trn, 3=.2h
    game_id: int
    turn: int
    nation_id: int
    raw: bytes

FILE_TYPES = {1: 'ftherlnd', 2: '.trn', 3: '.2h'}

def read_header(data: bytes) -> FileHeader:
    # Confirmed layout (all files share this header):
    # [0x00] 3 bytes magic (01 02 04)
    # [0x03] 3 bytes 'DOM'
    # [0x06] u16 checksum/hash
    # [0x08] u16 = 1 (constant)
    # [0x0A] u16 game version (636 = v6.36)
    # [0x0C] u16 = 0
    # [0x0E] u16 turn number
    # [0x10] u16 = 0
    # [0x12] u16 file type (0 = .2h, 1 = .trn / ftherlnd)
    # [0x14] u16 = 0
    # [0x16] u16 game ID
    # [0x18] u16 = 0
    # [0x1A] u16 nation ID (0xFFFF = ftherlnd/global)
    magic   = data[0:6]
    ftype   = struct.unpack_from('<H', data, 0x12)[0]
    game_id = struct.unpack_from('<H', data, 0x16)[0]
    turn    = struct.unpack_from('<H', data, 0x0E)[0]
    nation  = struct.unpack_from('<H', data, 0x1A)[0]
    return FileHeader(magic, ftype, game_id, turn, nation, data[:32])

# ---------------------------------------------------------------------------
# Commander records
# ---------------------------------------------------------------------------
#
# Layout in .2h (confirmed from binary analysis):
#   [00 00] [cmdr_type u16] [00 00] [name XOR...] 4F
#   [serial u32]  [u32 unknown]
#   [FF × 16-20]  <- present when commander has a move order
#   [00 × 92]     <- zero pad
#   [00 00] [target_prov u16] [00...]  <- move target province (0 = stay)
#
# cmdr_type matches unit IDs in MagicSites/BaseU game data.
# serial is a unique per-unit game ID.

@dataclass
class CommanderRecord:
    name: str
    name_off: int       # offset of XOR name start in file
    cmdr_type: int      # u16 at name_off - 4
    serial: int         # u32 at name_off + len(name) + 1
    target_prov: int    # 0 = no move order
    order_code: int = 7        # byte at nend+164; 7=hold/search, 8=blood hunt, etc.
    battle_order_code: int = 0 # byte at nend+198

    @property
    def is_moving(self) -> bool:
        return self.order_code in (1, 2)

    @property
    def order(self) -> str:
        if self.is_moving and self.target_prov:
            return f'move -> {self.target_prov}'
        return cmdr_order_name(self.order_code)

    @property
    def battle_order(self) -> str:
        return battle_order_name(self.battle_order_code)


def scan_commanders(data: bytes) -> list[CommanderRecord]:
    """
    Dynamically scan .2h for all named commander records.

    Pattern (confirmed from binary analysis):
      [00 00] [cmdr_type u16] [00 00] [XOR name] 4F [serial u32] ...

    Quality filters:
      - name_off >= 0x2000  (skip event text / header section)
      - cmdr_type in 1-4000
      - name length 2-40, all bytes decode to printable ASCII (no substitutions)
      - serial unique (deduplication)
    """
    results = []
    seen_serials: set[int] = set()
    i = 0x2004  # need at least 4 bytes of prefix
    while i < len(data) - 8:
        # Anchor: [00 00] immediately before name_off, ctype u16 two bytes before that
        # i.e. data[i-2]==0 and data[i-1]==0 and ctype = u16 at i-4
        if data[i-2] == 0x00 and data[i-1] == 0x00 and data[i] != XOR_KEY:
            fc = data[i] ^ XOR_KEY
            if 32 <= fc < 127:
                ctype = struct.unpack_from('<H', data, i - 4)[0]
                # Unit type IDs for named commanders are in 0x0100-0x03FF range
                if 0x0050 <= ctype <= 0x03FF:
                    name_off = i
                    # All bytes must decode to printable ASCII
                    end = name_off
                    while end < len(data) and end < name_off + 40 and data[end] != XOR_KEY:
                        if not (32 <= (data[end] ^ XOR_KEY) < 127):
                            end = -1; break
                        end += 1
                    if end != -1 and end > name_off and end < len(data) and data[end] == XOR_KEY:
                        name = ''.join(chr(data[j] ^ XOR_KEY) for j in range(name_off, end))
                        nend = end + 1
                        if len(name) >= 2 and nend + 4 <= len(data):
                            serial = struct.unpack_from('<I', data, nend)[0]
                            if serial not in seen_serials:
                                seen_serials.add(serial)
                                tp = _read_move_target(data, nend)
                                ocode = data[nend + 164] if nend + 165 <= len(data) else 7
                                bcode = data[nend + 198] if nend + 199 <= len(data) else 0
                                results.append(CommanderRecord(
                                    name=name, name_off=name_off,
                                    cmdr_type=ctype, serial=serial,
                                    target_prov=tp, order_code=ocode,
                                    battle_order_code=bcode,
                                ))
        i += 1
    results.sort(key=lambda r: r.name_off)
    return results


def _read_move_target(data: bytes, name_end: int) -> int:
    """Read move target province from post-name data. Returns 0 if no move.

    Layout: [serial u32] [u32?] [FF x 16-20] [00 x N] [00 00 target_u16 00...]
    The target is the first u16 in range 1-500 found after the zero-pad block.
    """
    scan_end = min(name_end + 300, len(data) - 8)
    i = name_end + 4  # skip serial
    while i < scan_end:
        if data[i:i+12] == b'\xFF' * 12:
            # Find end of FF run
            j = i + 12
            while j < scan_end and data[j] == 0xFF:
                j += 1
            zero_start = j
            # Find first non-zero byte after zero-pad
            while j < scan_end and data[j] == 0x00:
                j += 1
            # Read u16 at first non-zero position
            if j + 2 <= len(data):
                tp = struct.unpack_from('<H', data, j)[0]
                if 1 <= tp <= 500:
                    return tp
            return 0
        i += 1
    return 0


ORDER_NAMES = {
    0:  'Hold',
    1:  'Move (default)',
    2:  'Move',
    7:  'Defend',
    45: 'Defend',              # observed: nocommands default (variant code)
    8:  'Reanimate Soulless',   # observed: Ermor province order
    9:  'Reanimate Longdead',   # observed: Ermor province order (variant)
    10: 'Patrol',
    15: 'Pillage',
    19: 'Forge',
    20: 'Research',
    21: 'Preach',
    42: 'Attack',
    50: 'Recruit (capital)',
}

# Commander personal order codes (byte at nend+164 in commander record)
CMDR_ORDER_NAMES = {
    0:  'defend',          # confirmed: Mithok, Ermor turn 4
    1:  'move',
    4:  'research',        # confirmed: Vekhithu, Ermor turn 4
    7:  'hold/search',
    8:  'blood hunt',      # confirmed: Elle, Jotunheim turn 4
    9:  'unknown(9)',     # observed: Vekhithu pre-research (scry? another order?)
    10: 'patrol',
    18: 'build lab',            # confirmed: Pyenv, Ermor turn 4
    19: 'build temple',         # confirmed: Mithok, Ermor turn 4
    20: 'build palisades',      # confirmed: Pyenv, Ermor turn 4
    21: 'reanimate (ghouls)',   # confirmed: Zrakhnadar, Ermor turn 4 (pre-soulless)
    22: 'reanimate soulless',   # confirmed: Zrakhnadar, Ermor turn 4
    23: 'reanimate longdead',   # confirmed: Zrakhnadar, Ermor turn 4
    85: 'search (auto)',  # confirmed: Elle, Jotunheim turn 4
}

# Commander battle order codes (byte at nend+198 in commander record)
BATTLE_ORDER_NAMES = {
    0:  '',
    10: 'stay behind troops',  # confirmed: Pyenv, Ermor turn 4
}

def cmdr_order_name(code: int) -> str:
    return CMDR_ORDER_NAMES.get(code, f'unknown({code})')

def battle_order_name(code: int) -> str:
    return BATTLE_ORDER_NAMES.get(code, f'battle:{code}')

def order_name(code: int) -> str:
    if code in ORDER_NAMES:
        return ORDER_NAMES[code]
    if code < 0:
        return f'Move/Attack relative ({code})'
    return f'Unknown ({code})'


# ---------------------------------------------------------------------------
# Province order records (.2h)
# ---------------------------------------------------------------------------
#
# Province order record layout in .2h:
#   [FF FF] [00 00] [FF] [order i16] [1A 02] [prov_id u16] [00 00] [name XOR] 4F
#
# The order code is a signed i16. Negative values encode movement (observed),
# positive values encode commands (defend, patrol, etc.).

# Primary scan marker: FF FF 00 00 FF precedes [order i16] [1A 02] [prov u16]
ORDER_MARKER = bytes([0xFF, 0xFF, 0x00, 0x00, 0xFF])

def find_order_records(data: bytes) -> list[dict]:
    """
    Scan for province order records:
      [FF FF 00 00 FF] [order i16] [1A 02] [prov u16] [00 00] [name XOR] 4F

    Pre-bytes layout (5 bytes before FF FF 00 00 FF):
      [??] [nation_id u16] [pd u8] [??]
    If nation_id is non-zero → this is a province army record (PD / freespawn / capital).
    If nation_id is zero     → pure commander order record.

    record_type values:
      'commander'  - no nation ID in pre-bytes (pure commander standing order)
      'army'       - nation ID present (PD, freespawn, or capital garrison)
    """
    results = []
    i = 0
    while i < len(data) - 16:
        idx = data.find(ORDER_MARKER, i)
        if idx == -1:
            break
        # Verify [1A 02] follows [order i16] — idx points to FF FF 00 00 FF
        if idx + 9 < len(data) and data[idx+7:idx+9] == b'\x1A\x02':
            order_code = struct.unpack_from('<h', data, idx+5)[0]   # order after marker
            prov_id    = struct.unpack_from('<H', data, idx+9)[0]   # prov after 1A 02
            if prov_id > 500:
                i = idx + 1
                continue
            name_start = idx + 13                                    # skip 00 00 after prov
            name       = xor_decode(data, name_start, 64)
            # Skip both XOR name strings (province name appears twice)
            after_names  = name_start + len(name) + 1
            after_names2 = after_names + len(xor_decode(data, after_names, 64)) + 1
            # After names: fixed 56-byte province stats block, then FF FF recruit list.
            # Layout:
            #   base+ 0: [u16 ??][u16 ??][u16 ??][u16 ??]        (8 bytes, entry 0 header)
            #   base+ 8: entry 0 [12 bytes, all zeros typically]
            #   base+20: entry 1 [u16 ??][u16 ??][u16 ??][u16 cmdr_count][u16 unit_count][u16 ??]
            #   base+32: entry 2 [u16 income][u16 nation][u16 nation][u16 nation][u16 ??][u16 ??]
            #   base+44: entry 3 [u16 pd][u16 ...more stats...]
            #   base+56: FF FF   <- recruit list separator
            base   = after_names2
            ff_off = base + 56
            pd = 0
            cmdr_recruit_count = 0
            unit_recruit_count = 0
            recruits = []
            if ff_off + 1 < len(data) and data[ff_off] == 0xFF and data[ff_off+1] == 0xFF:
                cmdr_recruit_count = min(struct.unpack_from('<H', data, base + 26)[0], 32)
                unit_recruit_count = min(struct.unpack_from('<H', data, base + 28)[0], 32)
                recruit_count = cmdr_recruit_count + unit_recruit_count
                pd = data[base + 44]   # low byte only; high byte is flags
                if ff_off + 1 < len(data) and data[ff_off] == 0xFF:
                    r_off = ff_off + 2
                    n = min(recruit_count, 32)
                    # Layout: N×[unit_type u16] then N×[gold_cost u16]
                    utypes = []
                    for _ in range(n):
                        if r_off + 2 <= len(data):
                            utypes.append(struct.unpack_from('<H', data, r_off)[0])
                            r_off += 2
                    costs = []
                    for _ in range(n):
                        if r_off + 2 <= len(data):
                            costs.append(struct.unpack_from('<H', data, r_off)[0])
                            r_off += 2
                    pairs = list(zip(utypes, costs))
                    recruits = {
                        'commanders': pairs[:cmdr_recruit_count],
                        'units':      pairs[cmdr_recruit_count:],
                    }
            # Extract nation ID from pre-bytes (5 bytes before FF FF 00 00 FF)
            pre5_off  = idx - 5
            nation_id = 0
            if pre5_off + 3 <= len(data) and pre5_off >= 0:
                nation_id = struct.unpack_from('<H', data, pre5_off + 1)[0]
            # army = nation has standing presence; commander = pure province order
            # Note: a record can be 'army' AND have recruits (e.g. capital province)
            rtype = 'army' if nation_id else 'commander'
            results.append({
                'offset':        idx,
                'order_code':    order_code,
                'order_name':    order_name(order_code),
                'province':      prov_id,
                'name':          name,
                'name2':         '',
                'nation_id':     nation_id,
                'record_type':   rtype,
                'pd':            pd,
                'recruit_count':      recruit_count,
                'cmdr_recruit_count': cmdr_recruit_count,
                'unit_recruit_count': unit_recruit_count,
                'recruits':           recruits,
            })
        i = idx + 1
    return results

# ---------------------------------------------------------------------------
# Province records (ftherlnd)
# ---------------------------------------------------------------------------
#
# Province record layout in ftherlnd (confirmed):
#   [income i16] [1A 02] [prov_id u16] [00 00]
#   [name XOR] 4F  [name XOR] 4F        <- two copies of province name
#   [site_id u16] [00 00] × up to 8     <- site IDs in 4-byte slots, zero-padded

_PROV_MARKER = b'\x1A\x02'


@dataclass
class ProvinceRecord:
    prov_id: int
    name: str
    income: int
    site_ids: list[int] = field(default_factory=list)


def _xdec_end(data: bytes, off: int, maxlen: int = 256):
    """Decode XOR string and return (string, offset_after_terminator)."""
    end = off
    while end < len(data) and end < off + maxlen and data[end] != XOR_KEY:
        end += 1
    s = ''.join(chr(data[i] ^ XOR_KEY) if 32 <= (data[i] ^ XOR_KEY) < 127 else '?'
                for i in range(off, end))
    return s, end + 1


def _read_site_ids(data: bytes, off: int) -> tuple[list[int], int]:
    """Read up to 8 site ID slots (4 bytes each: [sid u16][00 00])."""
    site_ids = []
    for _ in range(8):
        if off + 4 > len(data):
            break
        sid = struct.unpack_from('<H', data, off)[0]
        pad = struct.unpack_from('<H', data, off + 2)[0]
        if sid == 0:
            off += 4
            continue
        if sid > 2500 or pad != 0:
            break
        site_ids.append(sid)
        off += 4
    return site_ids, off


def parse_provinces(data: bytes) -> list[ProvinceRecord]:
    """Parse all province records from ftherlnd binary data."""
    records: dict[int, ProvinceRecord] = {}
    i = 0
    while i < len(data) - 8:
        idx = data.find(_PROV_MARKER, i)
        if idx == -1:
            break
        off = idx + 2
        prov_id = struct.unpack_from('<H', data, off)[0];  off += 2
        if not (1 <= prov_id <= 500):
            i = idx + 1; continue
        if struct.unpack_from('<H', data, off)[0] != 0:
            i = idx + 1; continue
        off += 2
        # First name
        if off >= len(data) or data[off] == XOR_KEY:
            i = idx + 1; continue
        fc = data[off] ^ XOR_KEY
        if not (32 <= fc < 127):
            i = idx + 1; continue
        name1, off = _xdec_end(data, off)
        # Second name
        name2 = ''
        if off < len(data) and data[off] != XOR_KEY:
            fc2 = data[off] ^ XOR_KEY
            if 32 <= fc2 < 127:
                name2, off = _xdec_end(data, off)
        elif off < len(data) and data[off] == XOR_KEY:
            off += 1
        name = name2 or name1
        if len(name) == 0 or name.count('?') / len(name) > 0.4:
            i = idx + 1; continue
        income = struct.unpack_from('<h', data, idx - 2)[0] if idx >= 2 else 0
        site_ids, _ = _read_site_ids(data, off)
        rec = ProvinceRecord(prov_id=prov_id, name=name, income=income, site_ids=site_ids)
        # Keep record with most sites
        if prov_id not in records or len(site_ids) > len(records[prov_id].site_ids):
            records[prov_id] = rec
        i = idx + 1
    return sorted(records.values(), key=lambda r: r.prov_id)


def load_province_names(trn_data: bytes) -> dict[int, str]:
    """Extract province ID -> name mapping from .trn binary data."""
    names: dict[int, str] = {}
    i = 0
    while i < len(trn_data) - 8:
        idx = trn_data.find(_PROV_MARKER, i)
        if idx == -1:
            break
        pid = struct.unpack_from('<H', trn_data, idx + 2)[0]
        if not (1 <= pid <= 500):
            i = idx + 1; continue
        if struct.unpack_from('<H', trn_data, idx + 4)[0] != 0:
            i = idx + 1; continue
        name_off = idx + 6
        if name_off >= len(trn_data) or trn_data[name_off] == XOR_KEY:
            i = idx + 1; continue
        fc = trn_data[name_off] ^ XOR_KEY
        if not (32 <= fc < 127):
            i = idx + 1; continue
        name1, e1 = _xdec_end(trn_data, name_off)
        name2 = ''
        if e1 < len(trn_data) and trn_data[e1] != XOR_KEY:
            fc2 = trn_data[e1] ^ XOR_KEY
            if 32 <= fc2 < 127:
                name2, _ = _xdec_end(trn_data, e1)
        if pid not in names:
            names[pid] = name2 or name1
        i = idx + 1
    return names


# ---------------------------------------------------------------------------
# Site database (MagicSites.csv from dom6inspector)
# ---------------------------------------------------------------------------

@dataclass
class SiteInfo:
    site_id: int
    name: str
    level: int
    gems: dict[str, int] = field(default_factory=dict)  # path -> gem count


_GEM_COLS  = ['F', 'A', 'W', 'E', 'S', 'D', 'N', 'B']
_GEM_NAMES = {'F': 'Fire', 'A': 'Air', 'W': 'Water', 'E': 'Earth',
              'S': 'Astral', 'D': 'Death', 'N': 'Nature', 'B': 'Blood'}


def load_site_db(csv_path: Path | None = None) -> dict[int, SiteInfo]:
    """
    Load site ID -> SiteInfo from MagicSites.csv (dom6inspector format, TSV).
    Returns empty dict if file not found.
    """
    path = csv_path or (DATADIR / 'MagicSites.csv')
    if not path.exists():
        return {}
    db: dict[int, SiteInfo] = {}
    for row in csv.DictReader(path.read_text(encoding='utf-8', errors='replace').splitlines(),
                               delimiter='\t'):
        sid_str = row.get('id', '').strip()
        if not sid_str.isdigit():
            continue
        sid  = int(sid_str)
        name = row.get('name', f'site_{sid}').strip()
        try:
            level = int(row.get('level', '0') or '0')
        except ValueError:
            level = 0
        gems = {}
        for col in _GEM_COLS:
            v = row.get(col, '').strip()
            if v and v != '0':
                try:
                    gems[_GEM_NAMES[col]] = int(v)
                except ValueError:
                    pass
        db[sid] = SiteInfo(site_id=sid, name=name, level=level, gems=gems)
    return db


# ---------------------------------------------------------------------------
# High-level file loaders
# ---------------------------------------------------------------------------

def load(path: str | Path) -> tuple[FileHeader, BinReader]:
    data = Path(path).read_bytes()
    return read_header(data), BinReader(data)

def load_nation(nation_name: str, turn_prefix: str = 'mid') -> tuple[FileHeader, BinReader]:
    p = SAVEDIR / f'{turn_prefix}_{nation_name}.2h'
    return load(p)

def load_trn(nation_name: str, turn_prefix: str = 'mid') -> tuple[FileHeader, BinReader]:
    p = SAVEDIR / f'{turn_prefix}_{nation_name}.trn'
    return load(p)

def load_ftherlnd() -> tuple[FileHeader, BinReader]:
    return load(SAVEDIR / 'ftherlnd')

NATION_IDS = {
    0x50: 'Jotunheim',
    0x36: 'Ermor',
    0xFFFF: 'global (ftherlnd)',
}
