"""
Validate PD and recruit parsing for Flemistan (prov 156) across test files.
"""
import struct, sys
sys.path.insert(0, r'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\src')
from dom6 import SAVEDIR, find_order_records

for fname in ['mid_ermor_flemistan_pd4.2h', 'mid_ermor_flemistan_pd5.2h', 'mid_ermor.2h']:
    path = SAVEDIR / fname
    if not path.exists():
        continue
    data = path.read_bytes()
    print(fname)
    for r in find_order_records(data):
        if r['province'] == 156:
            print(f"  pd={r['pd']}  recruit_count={r['recruit_count']}  recruits={r['recruits']}")
print()

sep = ' '
d_base   = (SAVEDIR / 'mid_ermor_flemistan_pd4.2h').read_bytes()
d_milita = (SAVEDIR / 'mid_ermor.2h').read_bytes()
print(f"pd4 baseline: {len(d_base)} bytes")
print(f"pd4+militia:  {len(d_milita)} bytes")
print()

# Full diff within first 0x2000 bytes
n = min(len(d_base), len(d_milita))
i = 0
diffs = 0
while i < min(n, 0x2000):
    if d_base[i] != d_milita[i]:
        run_start = i
        while i < min(n, 0x2000) and d_base[i] != d_milita[i]:
            i += 1
        run_end = i
        s = max(0, run_start - 10)
        e = min(n, run_end + 10)
        cb = d_base[s:e]
        cm = d_milita[s:e]
        hb = sep.join(f'{b:02X}' for b in cb)
        hm = sep.join(f'{b:02X}' for b in cm)
        marks = ''.join('^^' if run_start <= s+j < run_end else '  ' for j in range(len(cb)))
        vb = list(d_base[run_start:run_end])
        vm = list(d_milita[run_start:run_end])
        print(f"0x{run_start:05X}  ({run_end-run_start} byte(s))  {vb} -> {vm}")
        print(f"  base:   {hb}")
        print(f"  milita: {hm}")
        print(f"          {marks}")
        print()
        diffs += 1
    else:
        i += 1
print(f"Diffs in first 0x2000: {diffs}")
print()

# Dump 200 bytes of the Flemistan record from both files starting at 0x00547
print("Flemistan record region (0x00547 + 200 bytes):")
for label, d in [('base  ', d_base), ('milita', d_milita)]:
    chunk = d[0x00547: 0x00547 + 200]
    print(f"  [{label}]")
    for row in range(0, len(chunk), 16):
        rb = chunk[row:row+16]
        rh = sep.join(f'{b:02X}' for b in rb)
        mark = ' <' if any(d_base[0x00547+row+j] != d_milita[0x00547+row+j]
                           for j in range(len(rb)) if 0x00547+row+j < len(d_milita)) else ''
        print(f"    {0x547+row:05X}: {rh}{mark}")
    print()
