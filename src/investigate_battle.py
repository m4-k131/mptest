"""
Investigate Pyenv's battle order change: nothing -> stay behind troops.
"""
import struct, sys
sys.path.insert(0, r'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\src')
from dom6 import SAVEDIR, XOR_KEY, xor_decode

# Try the pre-battle-change backup
backup_dir = SAVEDIR / 'backups' / 'turn4-ermor-temple-lab-longdead' / 'orders'
if not backup_dir.exists():
    print('Backup not found; using current file only')
    fnames = ['mid_ermor.2h']
else:
    fnames = [str(backup_dir / 'mid_ermor.2h'), 'mid_ermor.2h']

for fname in fnames:
    path = SAVEDIR / fname if '/' not in fname else Path(fname)
    if not path.exists():
        continue
    data = path.read_bytes()
    print(f'=== {path} ===')
    i = 0x2000
    while i < len(data) - 8:
        if data[i-2] == 0 and data[i-1] == 0 and data[i] != XOR_KEY:
            if 32 <= (data[i] ^ XOR_KEY) < 127:
                ctype = struct.unpack_from('<H', data, i-4)[0]
                if 0x0050 <= ctype <= 0x03FF:
                    name = xor_decode(data, i, 40)
                    if name == 'Pyenv':
                        nend = i + len(name) + 1
                        serial = struct.unpack_from('<I', data, nend)[0]
                        ocode = data[nend+164] if nend+165 <= len(data) else -1
                        print(f'  name_off=0x{i:05X}, nend=0x{nend:05X}, serial={serial}, main_order={ocode}')
                        # dump 220 bytes from nend
                        for row in range(nend, nend+220, 16):
                            chunk = data[row:row+16]
                            if not chunk:
                                break
                            u16s = [struct.unpack_from('<H', chunk, k)[0] for k in range(0, len(chunk)-1, 2)]
                            print(f'    0x{row:05X}: {" ".join("%02X"%b for b in chunk)}  | {u16s}')
                        print()
        i += 1

# Check battle order byte for all commanders in both files
for label, path in [('backup', backup_dir / 'mid_ermor.2h'), ('current', SAVEDIR / 'mid_ermor.2h')]:
    data = path.read_bytes()
    print(f'\n=== Battle order bytes ({label}) ===')
    i = 0x2000
    while i < len(data) - 8:
        if data[i-2] == 0 and data[i-1] == 0 and data[i] != XOR_KEY:
            if 32 <= (data[i] ^ XOR_KEY) < 127:
                ctype = struct.unpack_from('<H', data, i-4)[0]
                if 0x0050 <= ctype <= 0x03FF:
                    name = xor_decode(data, i, 40)
                    if len(name) >= 2 and name in ('Mithok', 'Pyenv', 'Zrakhnadar', 'Vekhithu', 'Plaguesoul'):
                        nend = i + len(name) + 1
                        if nend + 199 <= len(data):
                            bcode = data[nend+198]
                            print(f'  {name:<15} nend=0x{nend:05X}  nend+198=0x{nend+198:05X}  bcode={bcode}')
        i += 1
