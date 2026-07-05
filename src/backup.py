"""
backup.py  -  Dominions 6 save-file backup / restore / snapshot utility

Usage:
  python backup.py save-state  <label>          # snapshot ftherlnd + all .trn files
  python backup.py save-orders <label>          # snapshot all .2h files
  python backup.py save-all    <label>          # both of the above

  python backup.py list                         # list all snapshots
  python backup.py restore     <label>          # restore a snapshot (state+orders)
  python backup.py restore     <label> --state  # restore only state
  python backup.py restore     <label> --orders # restore only orders

  python backup.py snapshot-2h <src_label> <dst_label>
                                                # copy a .2h snapshot under a new name
                                                # (for systematic single-var experiments)

Snapshots are stored under:
  <savedir>/backups/<label>/state/   <- ftherlnd + *.trn
  <savedir>/backups/<label>/orders/  <- *.2h

Labels may contain letters, digits, hyphens and underscores.
"""

import argparse
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from dom6 import SAVEDIR

BACKUP_DIR = SAVEDIR / 'backups'
LABEL_RE   = re.compile(r'^[a-zA-Z0-9_\-]+$')


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _validate_label(label: str) -> str:
    if not LABEL_RE.match(label):
        sys.exit(f'ERROR: label "{label}" contains invalid characters (use a-z, 0-9, - _)')
    return label


def _snapshot_dir(label: str) -> Path:
    return BACKUP_DIR / label


def _state_files() -> list[Path]:
    files = [SAVEDIR / 'ftherlnd']
    files += sorted(SAVEDIR.glob('*.trn'))
    return [f for f in files if f.exists()]


def _order_files() -> list[Path]:
    return sorted(SAVEDIR.glob('*.2h'))


def _copy_files(src_paths: list[Path], dst_dir: Path, tag: str) -> None:
    dst_dir.mkdir(parents=True, exist_ok=True)
    for src in src_paths:
        dst = dst_dir / src.name
        shutil.copy2(src, dst)
        print(f'  {tag}  {src.name}  ->  {dst.relative_to(SAVEDIR)}')


def _restore_files(src_dir: Path, dst_dir: Path, tag: str) -> None:
    if not src_dir.exists():
        print(f'  (no {tag} snapshot in this backup)')
        return
    for src in sorted(src_dir.iterdir()):
        dst = dst_dir / src.name
        shutil.copy2(src, dst)
        print(f'  {tag}  {src.name}  ->  {dst.relative_to(SAVEDIR)}')


def _write_meta(snap_dir: Path, label: str, kinds: list[str]) -> None:
    meta = snap_dir / 'meta.txt'
    ts   = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    with meta.open('w') as f:
        f.write(f'label:   {label}\n')
        f.write(f'time:    {ts}\n')
        f.write(f'content: {", ".join(kinds)}\n')


def _read_meta(snap_dir: Path) -> dict[str, str]:
    meta = snap_dir / 'meta.txt'
    if not meta.exists():
        return {}
    result = {}
    for line in meta.read_text().splitlines():
        if ':' in line:
            k, v = line.split(':', 1)
            result[k.strip()] = v.strip()
    return result


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_save_state(label: str) -> None:
    _validate_label(label)
    snap = _snapshot_dir(label)
    files = _state_files()
    if not files:
        sys.exit('ERROR: no state files found (ftherlnd / *.trn)')
    print(f'Saving state snapshot "{label}":')
    _copy_files(files, snap / 'state', 'STATE')
    kinds = ['state']
    if (snap / 'orders').exists():
        kinds.append('orders')
    _write_meta(snap, label, kinds)
    print('Done.')


def cmd_save_orders(label: str) -> None:
    _validate_label(label)
    snap = _snapshot_dir(label)
    files = _order_files()
    if not files:
        sys.exit('ERROR: no order files found (*.2h)')
    print(f'Saving orders snapshot "{label}":')
    _copy_files(files, snap / 'orders', 'ORDERS')
    kinds = ['orders']
    if (snap / 'state').exists():
        kinds.append('state')
    _write_meta(snap, label, sorted(kinds))
    print('Done.')


def cmd_save_all(label: str) -> None:
    _validate_label(label)
    snap = _snapshot_dir(label)
    state_files  = _state_files()
    order_files  = _order_files()
    if not state_files and not order_files:
        sys.exit('ERROR: no save files found')
    print(f'Saving full snapshot "{label}":')
    if state_files:
        _copy_files(state_files, snap / 'state', 'STATE ')
    if order_files:
        _copy_files(order_files, snap / 'orders', 'ORDERS')
    _write_meta(snap, label, ['state', 'orders'])
    print('Done.')


def cmd_list() -> None:
    if not BACKUP_DIR.exists() or not any(BACKUP_DIR.iterdir()):
        print('No snapshots found.')
        return
    print(f'Snapshots in {BACKUP_DIR.relative_to(SAVEDIR)}:')
    print(f'  {"Label":<30}  {"Time":<20}  Content')
    print('  ' + '-' * 65)
    for snap in sorted(BACKUP_DIR.iterdir()):
        if not snap.is_dir():
            continue
        meta = _read_meta(snap)
        ts      = meta.get('time', '?')
        content = meta.get('content', '?')
        print(f'  {snap.name:<30}  {ts:<20}  {content}')


def cmd_restore(label: str, state_only: bool, orders_only: bool) -> None:
    _validate_label(label)
    snap = _snapshot_dir(label)
    if not snap.exists():
        sys.exit(f'ERROR: snapshot "{label}" not found')
    meta = _read_meta(snap)
    print(f'Restoring snapshot "{label}" ({meta.get("time", "?")}):')
    if not orders_only:
        _restore_files(snap / 'state',  SAVEDIR, 'STATE ')
    if not state_only:
        _restore_files(snap / 'orders', SAVEDIR, 'ORDERS')
    print('Done.')


def cmd_snapshot_2h(src_label: str, dst_label: str) -> None:
    """Copy the orders sub-snapshot from src_label to dst_label (new label)."""
    _validate_label(src_label)
    _validate_label(dst_label)
    src_dir = _snapshot_dir(src_label) / 'orders'
    if not src_dir.exists():
        sys.exit(f'ERROR: snapshot "{src_label}" has no orders sub-snapshot')
    dst_snap = _snapshot_dir(dst_label)
    if dst_snap.exists():
        sys.exit(f'ERROR: snapshot "{dst_label}" already exists — choose a different label')
    print(f'Copying orders snapshot "{src_label}" -> "{dst_label}":')
    _copy_files(sorted(src_dir.iterdir()), dst_snap / 'orders', 'ORDERS')
    _write_meta(dst_snap, dst_label, ['orders'])
    print(f'Edit files in:  {(dst_snap / "orders").relative_to(SAVEDIR)}')
    print(f'Then restore with:  python backup.py restore {dst_label} --orders')
    print('Done.')


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    p = argparse.ArgumentParser(
        description='Dominions 6 save-file backup / restore utility',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = p.add_subparsers(dest='cmd', required=True)

    s = sub.add_parser('save-state',  help='Snapshot ftherlnd + *.trn')
    s.add_argument('label')

    s = sub.add_parser('save-orders', help='Snapshot *.2h order files')
    s.add_argument('label')

    s = sub.add_parser('save-all',    help='Snapshot both state and orders')
    s.add_argument('label')

    sub.add_parser('list',            help='List all snapshots')

    s = sub.add_parser('restore',     help='Restore a snapshot')
    s.add_argument('label')
    g = s.add_mutually_exclusive_group()
    g.add_argument('--state',  action='store_true', help='Restore only state files')
    g.add_argument('--orders', action='store_true', help='Restore only order files')

    s = sub.add_parser('snapshot-2h', help='Clone an orders snapshot under a new label')
    s.add_argument('src_label')
    s.add_argument('dst_label')

    args = p.parse_args()

    if args.cmd == 'save-state':
        cmd_save_state(args.label)
    elif args.cmd == 'save-orders':
        cmd_save_orders(args.label)
    elif args.cmd == 'save-all':
        cmd_save_all(args.label)
    elif args.cmd == 'list':
        cmd_list()
    elif args.cmd == 'restore':
        cmd_restore(args.label, state_only=args.state, orders_only=args.orders)
    elif args.cmd == 'snapshot-2h':
        cmd_snapshot_2h(args.src_label, args.dst_label)


if __name__ == '__main__':
    main()
