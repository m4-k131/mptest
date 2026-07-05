"""
analyze.py  -  Dominions 6 save file analyser CLI

Commands:
  orders  [nation]        Commander moves from .2h  (default: jotunheim)
  sites                   All magic sites from ftherlnd, named via MagicSites.csv
  strings [file]          Dump all XOR strings from a file
  hex     file offset len Hexdump a region
  probe   file offset     Inspect a single offset
"""

import argparse
from pathlib import Path
from dom6 import (
    SAVEDIR, NATION_IDS, BinReader,
    read_header, FILE_TYPES,
    xor_decode, find_xor_strings,
    find_order_records, order_name,
    scan_commanders,
    parse_provinces, load_province_names, load_site_db,
    load, load_nation, load_trn, load_ftherlnd,
)


# ---------------------------------------------------------------------------
# orders
# ---------------------------------------------------------------------------

def cmd_orders(args):
    """Show commander move orders from a nation's .2h file."""
    nation = getattr(args, 'nation', 'jotunheim')
    hdr, r = load_nation(nation)
    nname = NATION_IDS.get(hdr.nation_id, f'nation {hdr.nation_id}')
    print(f"\n=== ORDERS  {nation}  (turn {hdr.turn}, game {hdr.game_id}) ===\n")

    # Province order records
    records = find_order_records(r.data)
    trn_path = SAVEDIR / f'mid_{nation}.trn'
    prov_names: dict[int, str] = {}
    if trn_path.exists():
        prov_names = load_province_names(trn_path.read_bytes())

    cmdr_orders = [rec for rec in records if rec['record_type'] == 'commander']
    army_orders = [rec for rec in records if rec['record_type'] == 'army']

    if cmdr_orders:
        print(f"  Province orders:")
        print(f"  {'Prov':>4}  {'Province':<24}  {'PD':>3}  {'Code':>5}  Order  / Recruits")
        print("  " + "-" * 65)
        for rec in cmdr_orders:
            pname = prov_names.get(rec['province'], f"prov {rec['province']}")
            pd_str = str(rec['pd']) if rec.get('pd') else '-'
            line = f"  {rec['province']:>4}  {pname:<24}  {pd_str:>3}  {rec['order_code']:>5}  {order_name(rec['order_code'])}"
            recs = rec.get('recruits', {})
            if recs.get('commanders'):
                line += '  [cmdrs: ' + ', '.join(f"type{u}(g{c})" for u, c in recs['commanders']) + ']'
            if recs.get('units'):
                line += '  [units: ' + ', '.join(f"type{u}(g{c})" for u, c in recs['units']) + ']'
            print(line)
        print()

    if army_orders:
        print(f"  Army/freespawn orders ({len(army_orders)}):")
        print(f"  {'Prov':>4}  {'Province':<24}  {'Nation':>8}  {'Code':>5}  Order")
        print("  " + "-" * 65)
        for rec in army_orders:
            pname  = prov_names.get(rec['province'], f"prov {rec['province']}")
            nname  = NATION_IDS.get(rec['nation_id'], f"0x{rec['nation_id']:04X}")
            pd_str = str(rec['pd']) if rec.get('pd') else '-'
            line = f"  {rec['province']:>4}  {pname:<24}  {nname:>8}  {pd_str:>3}  {rec['order_code']:>5}  {order_name(rec['order_code'])}"
            recs = rec.get('recruits', {})
            if recs.get('commanders'):
                line += '  [cmdrs: ' + ', '.join(f"type{u}(g{c})" for u, c in recs['commanders']) + ']'
            if recs.get('units'):
                line += '  [units: ' + ', '.join(f"type{u}(g{c})" for u, c in recs['units']) + ']'
            print(line)
        print()

    # Named commander move targets
    commanders = scan_commanders(r.data)
    if commanders:
        # Use ftherlnd province names for target display if available
        fth_path = SAVEDIR / 'ftherlnd'
        prov_names_fth: dict[int, str] = {}
        if fth_path.exists():
            provinces = parse_provinces(fth_path.read_bytes())
            prov_names_fth = {p.prov_id: p.name for p in provinces}

        print(f"  {'Name':<20}  {'Type':>5}  {'Serial':>8}  Order")
        print("  " + "-" * 60)
        for c in commanders:
            if c.is_moving and c.target_prov:
                tname = prov_names_fth.get(c.target_prov, f'prov {c.target_prov}')
                order_str = f'move -> {c.target_prov} ({tname})'
            else:
                order_str = c.order
            extra = f'  [{c.battle_order}]' if c.battle_order else ''
            print(f"  {c.name:<20}  {c.cmdr_type:>5}  {c.serial:>8}  {order_str}{extra}")
    print()


# ---------------------------------------------------------------------------
# sites
# ---------------------------------------------------------------------------

def cmd_sites(args):
    """List all magic sites from ftherlnd, with names from MagicSites.csv."""
    fth_path = SAVEDIR / 'ftherlnd'
    if not fth_path.exists():
        print("ftherlnd not found"); return

    hdr, _ = load_ftherlnd()
    provinces = parse_provinces(fth_path.read_bytes())
    site_db   = load_site_db()
    with_sites = [p for p in provinces if p.site_ids]

    print(f"\n=== MAGIC SITES  (ftherlnd, turn {hdr.turn}, {len(with_sites)} provinces) ===\n")
    print(f"  {'Prov':>4}  {'Province':<22}  {'Inc':>4}  {'Site Name':<35}  Lv  Gems")
    print("  " + "-" * 90)
    for p in with_sites:
        for i, sid in enumerate(p.site_ids):
            si = site_db.get(sid)
            sname = si.name if si else f'id={sid}'
            level = str(si.level) if si else '?'
            gems  = ', '.join(f'{k}:{v}' for k, v in si.gems.items()) if si else '-'
            prefix = f"  {p.prov_id:>4}  {p.name:<22}  {p.income:>4}  " if i == 0 \
                     else f"  {'':>4}  {'':22}  {'':>4}  "
            print(f"{prefix}{sname:<35}  {level:>2}  {gems}")
    print(f"\n  {len(with_sites)} provinces  |  "
          f"{sum(len(p.site_ids) for p in with_sites)} total sites  |  "
          f"{len(site_db)} sites in db")


# ---------------------------------------------------------------------------
# strings / hex / probe
# ---------------------------------------------------------------------------

def cmd_strings(args):
    """Dump all XOR strings from a file."""
    fname = getattr(args, 'file', None) or 'mid_jotunheim.2h'
    data = (SAVEDIR / fname).read_bytes()
    min_len = getattr(args, 'min_len', 4)
    print(f"\n=== XOR STRINGS  {fname}  (min_len={min_len}) ===\n")
    count = 0
    for off, s in find_xor_strings(data, min_len=min_len):
        print(f"  [0x{off:06X}]  {s!r}")
        count += 1
    print(f"\nTotal: {count} strings")


def cmd_hex(args):
    """Hexdump a region of a file."""
    off = int(args.offset, 16)
    r = BinReader((SAVEDIR / args.file).read_bytes())
    print(f"\nHexdump {args.file}  0x{off:X}  +{args.length}\n")
    print(r.hexdump(off, int(args.length)))


def cmd_probe(args):
    """Inspect a single offset: hexdump context + decoded values."""
    off  = int(args.offset, 16)
    data = (SAVEDIR / args.file).read_bytes()
    r    = BinReader(data)
    print(f"\nProbe: {args.file}  @ 0x{off:X}\n")
    print(r.hexdump(max(0, off - 32), 80))
    print(f"\nXOR string: {xor_decode(data, off)!r}")
    if off + 4 <= len(data):
        print(f"u16={r.at_u16(off)}  u32={r.at_u32(off)}  i16={r.at_i16(off)}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(description='Dominions 6 save file analyser')
    sub = p.add_subparsers(dest='cmd')

    o = sub.add_parser('orders',  help='Commander move orders from .2h')
    o.add_argument('nation', nargs='?', default='jotunheim')

    sub.add_parser('sites', help='All magic sites from ftherlnd')

    s = sub.add_parser('strings', help='Dump XOR strings from a file')
    s.add_argument('file', nargs='?', default='mid_jotunheim.2h')
    s.add_argument('--min-len', type=int, default=4, dest='min_len')

    h = sub.add_parser('hex', help='Hexdump a region')
    h.add_argument('file'); h.add_argument('offset'); h.add_argument('length')

    pr = sub.add_parser('probe', help='Inspect an offset')
    pr.add_argument('file'); pr.add_argument('offset')

    args = p.parse_args()
    dispatch = {
        'orders':  cmd_orders,
        'sites':   cmd_sites,
        'strings': cmd_strings,
        'hex':     cmd_hex,
        'probe':   cmd_probe,
    }
    fn = dispatch.get(args.cmd)
    if fn:
        fn(args)
    else:
        p.print_help()


if __name__ == '__main__':
    main()
