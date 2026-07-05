# Dominions 6 Save File Format — Reverse Engineering Notes

> Goal: decode the complete game state and turn files for all nations.  
> Status: work in progress. Confirmed = verified by binary diff or parser output.

---

## File Overview

| File | Type | Contents |
|---|---|---|
| `ftherlnd` | Global state | Province names, income, sites, map state |
| `mid_<nation>.trn` | Per-nation state | Province names from this nation's perspective |
| `mid_<nation>.2h` | Turn orders | Province/commander orders, recruits, PD |

All three files share the same **file header** (32 bytes).

---

## Shared File Header (32 bytes, confirmed)

```
Offset  Size  Type    Description
0x00    3     bytes   Magic: 01 02 04
0x03    3     bytes   ASCII literal: "DOM"
0x06    2     u16     Checksum / hash (changes with every save, do not rely on)
0x08    2     u16     Constant: 1
0x0A    2     u16     Game version (e.g. 636 = v6.36)
0x0C    2     u16     Constant: 0
0x0E    2     u16     Turn number
0x10    2     u16     Constant: 0
0x12    2     u16     File type: 0 = .2h, 1 = .trn / ftherlnd
0x14    2     u16     Constant: 0
0x16    2     u16     Game ID
0x18    2     u16     Constant: 0
0x1A    2     u16     Nation ID (0xFFFF = global / ftherlnd)
```

All multi-byte integers are **little-endian**.

---

## XOR String Encoding (confirmed)

All string values (province names, commander names) are XOR-encoded with key **`0x4F`**.

- Each byte `b` in the stream encodes character `b XOR 0x4F`.
- The string is null-terminated by a byte equal to `0x4F` (i.e. XOR of `0x00 = 0x4F`).
- Strings often appear **twice consecutively** (original map name, then overwritten name).

```python
XOR_KEY = 0x4F

def xor_decode(data, start, max_len=64):
    result = []
    for i in range(start, min(start + max_len, len(data))):
        if data[i] == XOR_KEY:   # terminator
            break
        result.append(chr(data[i] ^ XOR_KEY))
    return ''.join(result)
```

---

## `ftherlnd` — Global State File

### Province Records (confirmed)

Located throughout the file. Scan for marker `1A 02`.

```
[income i16] [1A 02] [prov_id u16] [00 00]
[name1 XOR...] 4F
[name2 XOR...] 4F      ← may be empty (just 4F)
[site_id u16] [00 00]  ← repeated up to 8 times; ends when sid=0 or pad≠0
```

- `income`: province base income (signed, can be negative).
- `prov_id`: 1–500 (filter out-of-range hits).
- Two name copies: the second (if present and non-empty) is the canonical name.
- Site IDs are 4-byte slots: `[sid u16][00 00]`. Slot with `sid=0` is empty.

### Open Issues (ftherlnd)
- [ ] Province ownership (controlling nation) — location not yet confirmed.
- [ ] Dominion levels per province.
- [ ] Army presence / unit stacks.
- [ ] Magic site activation status (found vs. unfound).
- [ ] Population / unrest values.

---

## `.trn` — Per-Nation State File

Contains the same province record format as `ftherlnd` (same `1A 02` marker, same XOR names).  
Used to extract province names from a specific nation's perspective.

### Open Issues (.trn)
- [ ] Commander location records.
- [ ] Spell research state.
- [ ] Ritual spell queue.
- [ ] Gold / resource treasury.

---

## `.2h` — Turn Orders File

Contains all orders placed by a nation for the current turn.  
File is **overwritten each time** the player makes a change in-game.

---

### Province Order Records (confirmed)

Primary scan marker: `FF FF 00 00 FF`

```
[FF FF 00 00 FF] [order_code i16] [1A 02] [prov_id u16] [00 00]
[name1 XOR...] 4F
[name2 XOR...] 4F
[00 × 24]                          ← zero padding
[?? u16]                           ← unknown, observed value: 6
[cmdr_recruit_count u16]           ← number of commander recruit orders
[unit_recruit_count u16]           ← number of unit recruit orders
[00 u16]                           ← padding
[?? u16] [nation_id u16] [nation_id u16] [nation_id u16] [00 00 00 00 00 00]
                                   ← 12-byte block; nation_id appears 3×
[pd u16]                           ← Province Defense level
[... more province stats ...]
[FF FF]                            ← recruit list separator
[type_0 u16] ... [type_N u16]      ← N = cmdr_recruit_count + unit_recruit_count
[gold_0 u16] ... [gold_N u16]      ← gold cost per recruit
[00 × (2N + 4)]                    ← zero padding after costs
```

**Notes:**
- Commanders are listed **before** units in the recruit list.
- Gold cost is stored per recruit; resources and recruitment points are **not** stored (looked up at host time).
- `prov_id > 500` → false positive, skip.
- Province name appears twice (same as ftherlnd pattern).

#### Order Codes (i16, confirmed unless noted)

| Code | Name | Notes |
|---|---|---|
| 0 | Hold | |
| 1 | Move (default) | |
| 2 | Move | |
| 7 | Defend | |
| 8 | Reanimate Soulless | Ermor standing order |
| 9 | Reanimate Longdead | Ermor variant |
| 10 | Patrol | |
| 15 | Pillage | |
| 19 | Forge | |
| 20 | Research | |
| 21 | Preach | |
| 38 | Unknown | observed: Pergami (capital?) |
| 42 | Attack | |
| 45 | Defend (variant) | observed: nocommands baseline |
| 50 | Recruit (capital) | |
| < 0 | Move/Attack relative | negative = relative province offset |

#### record_type Classification

Based on the 5 bytes **before** `FF FF 00 00 FF`:

| Pattern | record_type | Meaning |
|---|---|---|
| nation_id = 0 in pre-bytes | `commander` | Province standing order (PD, recruits) |
| nation_id ≠ 0 in pre-bytes | `army` | Army/freespawn order for that nation |

---

### Commander Records (confirmed)

Located in the **second half** of the `.2h` file (offset ≥ `0x2000`).

```
[00 00] [cmdr_type u16] [00 00] [name XOR...] 4F
[serial u32]
[u32 unknown]
[FF × 16–20]          ← separator after serial block
[00 × ~92]            ← zero padding / optional squad data
[current_prov u16]    ← current province for stationary orders; destination for move orders
```

**Scan rules (quality filters):**
- `cmdr_type` in range `0x0050–0x03FF` (observed named commander types; includes low-ID commanders like Mithok 0x0063, Vekhithu 0x00EF).
- Name length: 2–40 characters, all printable ASCII.
- `serial` must be unique (deduplication).
- Skip first `0x2000` bytes (header / event text section).

**Location detection:**  
Scan forward from end of name+serial for first `u16` value in range 1–500 after the first `FF` block.

#### Commander Personal Order Byte (confirmed)

Located at `nend + 164` where `nend = name_off + len(name) + 1` (byte after XOR name terminator).

| Code | Order |
|---|---|
| 0 | defend (confirmed: Mithok, Ermor turn 4) |
| 1 | move (confirmed: Gudlaug/Greip/D3/Sigtryg, Jotunheim turn 4) |
| 4 | research (confirmed: Vekhithu, Ermor turn 4) |
| 7 | hold / search |
| 8 | blood hunt (confirmed: Elle, Jotunheim turn 4) |
| 9 | unknown (observed: Vekhithu pre-research, possibly scry) |
| 10 | patrol |
| 18 | build lab (confirmed: Pyenv, Ermor turn 4) |
| 19 | build temple (confirmed: Mithok, Ermor turn 4) |
| 20 | build palisades (confirmed: Pyenv, Ermor turn 4) |
| 21 | reanimate (ghouls) (confirmed: Zrakhnadar, Ermor turn 4) |
| 22 | reanimate soulless (confirmed: Zrakhnadar, Ermor turn 4) |
| 23 | reanimate longdead (confirmed: Zrakhnadar, Ermor turn 4) |
| 85 | search (auto) (confirmed: Elle, Jotunheim turn 4) |

The province ID stored in the commander record is the **current location** for stationary orders; for `move` (code 1) it is the destination/target.

#### Commander Battle Order Byte (confirmed)

Located at `nend + 198`.

| Code | Order |
|---|---|
| 0 | default / no special battle order |
| 10 | stay behind troops (confirmed: Pyenv, Ermor turn 4) |

#### Open Issues (commanders)
- [ ] Commander types outside `0x0100–0x03FF` range (e.g. national heroes, summons).
- [ ] Spell casting orders per commander.
- [ ] Equipment / magic item slots.
- [ ] Squad data attached to commander records (Mithok has 44 units in 2 types).

---

## Known Nation IDs

| Hex | Nation |
|---|---|
| `0x36` | Ermor |
| `0x50` | Jotunheim |
| `0xFFFF` | Global / ftherlnd |

---

## Observed Province IDs

| ID | Name | Notes |
|---|---|---|
| 132 | Cloudbreakers | |
| 139 | Pergami | Ermor capital |
| 140 | Uzid Yazran | |
| 156 | Flemistan | Controlled by Ermor in test game |
| 158 | Resting Heights | |
| 159–160 | (Jotunheim area) | |
| 169 | Delca | |

---

## Open Issues / Next Steps

### High Priority
- [ ] **Commander standing orders**: patrol, research, forge, preach — how are they encoded in `.2h`?
- [ ] **Ritual casting orders**: where in `.2h` are ritual queues stored?
- [ ] **Province ownership**: which bytes in `ftherlnd` or `.2h` record which nation owns a province?
- [ ] **Dominion**: per-province dominion strength encoding.

### Medium Priority
- [ ] **Unit stacks**: how are army compositions (non-recruit) stored?
- [ ] **Commander items**: magic item slot encoding.
- [ ] **Spell research**: current research queue and gem storage.
- [ ] **Treasury**: gold/resource totals per nation.
- [ ] **Unknown order codes**: 35 (seen on army records), 38 (seen on capital).

### Low Priority / Speculation
- [ ] `ftherlnd` province record: fields beyond site IDs (pop, unrest, fort level).
- [ ] `.d6m` / `.map` files: not yet analyzed.
- [ ] Multiple commander recruits of the same type — is the list deduplicated or not?

---

## Validation Files

| File | Description |
|---|---|
| `mid_ermor_flemistan_pd4.2h` | Baseline: Flemistan PD=4, no recruits |
| `mid_ermor_flemistan_pd5.2h` | Control: Flemistan PD=5, no recruits |
| `mid_ermor-nocommands.2h` | Baseline: all province orders removed |
| `mid_ermor.2h` | Current live file |
| `mid_jotunheim.2h` | Jotunheim orders |
| `ftherlnd` | Global map state |

---

## Tools

| File | Description |
|---|---|
| `src/dom6.py` | Parsing library (BinReader, XOR codec, header, commanders, provinces, orders) |
| `src/analyze.py` | CLI: `analyze.py orders <nation>`, `analyze.py provinces`, etc. |
| `src/_diff_ermor.py` | Scratch script for binary diffing / probing |
