# Deep decode of Jotunheim .2h orders file
# XOR key = 0x4F confirmed
# Unit records are ~0x1B0 bytes each (6 commanders seen before the big FF block at 0x0BB9)
# Records start with a unit/commander ID (4 bytes LE)

$KEY = 0x4F
$path = 'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\mid_jotunheim.2h'
$bytes = [System.IO.File]::ReadAllBytes($path)
$out = [System.Collections.Generic.List[string]]::new()

function xstr($start, $end) {
    $s = ""
    for ($k = $start; $k -lt $end -and $k -lt $bytes.Length; $k++) {
        $c = $bytes[$k] -bxor $KEY
        if ($c -ge 32 -and $c -le 126) { $s += [char]$c } else { $s += ("?{0:X2}" -f $bytes[$k]) }
    }
    return $s
}
function hex($start, $len) {
    $s = ""
    for ($k = $start; $k -lt ($start+$len) -and $k -lt $bytes.Length; $k++) {
        $s += "{0:X2} " -f $bytes[$k]
    }
    return $s.TrimEnd()
}
function u16($off) { [BitConverter]::ToUInt16($bytes, $off) }
function u32($off) { [BitConverter]::ToUInt32($bytes, $off) }
function i16($off) { [BitConverter]::ToInt16($bytes, $off) }
function i32($off) { [BitConverter]::ToInt32($bytes, $off) }
function Add($s) { $out.Add($s) }

# ---- HEADER ----
Add "================================================================"
Add "JOTUNHEIM .2H ORDERS FILE - DEEP DECODE"
Add "================================================================"
Add ""
Add "=== HEADER (bytes 0x00-0x5F) ==="
Add ("  Magic:        01 02 04 DOM")
Add ("  Build:        {0} (0x{0:X})" -f (u16 10))
Add ("  FileType:     0x{0:X4} (4=trn/ftherlnd, 3=.2h)" -f (u16 14))
Add ("  Flags[18-19]: 0x{0:X4}" -f (u16 18))
Add ("  GameID:       0x{0:X4} = {1}" -f (u16 22), (u16 22))
Add ("  NationID:     0x{0:X2} = {1} (0x50=80=Jotunheim)" -f $bytes[26], $bytes[26])
Add ("  Bytes[0x22]:  0x{0:X8} (checksum/random seed?)" -f (u32 0x22))
# 0x26 onward: game name XOR encoded (terminates at 0x4F)
$gnStart = 0x26
$gnEnd = $gnStart
while ($gnEnd -lt $bytes.Length -and $bytes[$gnEnd] -ne 0x4F) { $gnEnd++ }
Add ("  GameName:     '{0}'" -f (xstr $gnStart $gnEnd))
Add ""

# ---- The 6 commander blocks before the big FF region ----
# From analysis: 6 commander records, each ~0x1B0 bytes
# They start around 0x62 and the last ends around 0x0BB8
# Let's look at the structure of record 1 which is at ~0x62

Add "=== COMMANDER RECORDS (0x62 - 0x0BB8) ==="
Add ""
Add "Each record appears to be ~0x1B0 bytes. The 4F 4F sentinel marks end of"
Add "the name/description string block, followed by 0x12 bytes of FF (fog of war)."
Add ""

# Record boundaries identified from 4F4F positions:
# 4F4F at: 0x0114, 0x02C5, 0x052D, 0x0749, 0x090D, 0x0ACC
# Record starts: 0x0062, 0x01C1(?), estimated...
# Let's scan from 0x62 and parse each record

# From the hex dump, the structure around each commander seems to be:
# [unit_id: 4B] [unit_type: 2B] ... [prov_id: 2B] [nation: 2B] [order_type: 2B] ...
# Then XOR strings (province name + description), then 4F4F, then 18 bytes FF, then next record

# Commander block starts - let me find them by looking at what precedes each 4F4F
# Going back from 4F4F positions to find the start of each block
# The pattern before 4F4F: lots of XOR text ending in 4F, then immediately 4F4F

# Known from analysis: province names decoded:
# 0x0024: "mptest" (game name)
# 0x003B-0x004A: "OOOCliff Coast" / "Cliff Coast" -> province name = "Cliff Coast"  
# 0x01E2-0x01F5: "Kingstomb Desert"
# 0x044E-0x045F: "Stinging Swamp"
# 0x060D: "Jotunheim" (capital!)
# 0x0824: "The Great Mountains"
# 0x09E1: "Snowford"

# The strings appear TWICE - the first occurrence seems XOR-encoded with extra leading "OOO" bytes
# The double-string pattern: first = some header info + name, second = just the name
# This might be: [province_description_xor] [province_name_xor] separated by something

# Commander records - let me parse the non-string data
# Looking at bytes 0x62-0xB0 (first commander's header):
Add "--- Commander 1 header (around 0x62-0xB5) ---"
Add ("  Raw: {0}" -f (hex 0x62 0x56))
Add ""
# 0x62: 00 00 02 31 00 00 = ?
# Bytes 0x66-0x67: 0x86 0x00 = 134 (commander/unit ID?)
Add ("  Bytes[0x66-0x67] unit_type_id?: {0} (0x{0:X})" -f (u16 0x66))
Add ("  Bytes[0x68-0x69] ?: {0}" -f (u16 0x68))
# 0x6E: 0x0B 0x00 = 11 
Add ("  Bytes[0x6E-0x6F]: {0}" -f (u16 0x6E))
# 0x76-0x77: 0x23 0x00 = 35
Add ("  Bytes[0x70-0x7F]: {0}" -f (hex 0x70 0x10))
# The pattern XX 00 50 00 50 00 50 00 appears -> XX = commander serial/slot, 50 = nation Jotunheim
# At 0x78: 23 00 50 00 50 00 50 00 -> commander slot 0x23=35?
Add ("  Bytes[0x78-0x7F] [slot?][nation][nation][nation]: {0}" -f (hex 0x78 0x08))
Add ""

# Province IDs from the earlier analysis - these are the key data points:
# 0x01E1: province 136 (0x88) "Kingstomb Desert" 
# 0x0259: province 72 (0x48)
# 0x044D: province 157 (0x9D) "Stinging Swamp"
# 0x060C: province 159 (0x9F) "Three Pine Grove" (near Jotunheim)  
# 0x0823: province 160 (0xA0) "The Great Mountains"
# 0x09E0: province 161 (0xA1) "Snowford"

Add "=== PROVINCE/LOCATION ASSIGNMENTS PER COMMANDER ==="
Add ""
Add "  Cmdr 1: Province 0x88 = 136 'Kingstomb Desert'"
Add "  Cmdr 2: Province 0x48 = 72  (name not in .2h visible region)"
Add "  Cmdr 3: Province 0x9D = 157 'Stinging Swamp'"
Add "  Cmdr 4: Province 0x9F = 159 'Three Pine Grove' (near Jotunheim capital?)"
Add "  Cmdr 5: Province 0xA0 = 160 'The Great Mountains'"
Add "  Cmdr 6: Province 0xA1 = 161 'Snowford'"
Add ""

# Now decode the ORDER data in each commander block
# The key insight: just before/around each province ID are ORDER bytes
# Pattern at 0x01DD-0x01E5:
#   FF FF 00 00 FF 2A 00 1A 02 88 00 00 00 04 ...
#   -> 0xFF FF = some flags, 0x2A = order value, 0x1A02 = ?, 0x88 00 = prov 136
# Let's decode the order bytes

Add "=== ORDER DECODING ==="
Add ""

# Look at what precedes each province ID:
# Pattern: [?? ??] [order_code: 2B] [??] [prov_id: 2B]
# 0x01DB: FF FF 00 00 FF [2A 00] [1A 02] [88 00]
# 0x044B: F8 FF 00 00 FF [F8 FF] [1A 02] [9D 00]  -- hmm, negative?
# 0x060A: FF FF 00 00 FF [07 00] [1A 02] [9F 00]
# 0x0821: FF FF 00 00 FF [D9 FF] [1A 02] [A0 00]  -- negative!
# 0x09DE: FF FF 00 00 FF [DA FF] [1A 02] [A1 00]  -- negative!

# Let me look at 2 bytes before the [1A 02] pattern
# Actually 0x1A02 little-endian = 0x021A = 538... or read as two bytes: 0x1A=26, 0x02=2
# Could be "26 02" = some encoding

# Let me re-examine around each province ID more carefully
$provOffsets = @(0x01E1, 0x0259, 0x044D, 0x060C, 0x0823, 0x09E0)
$provNames = @("Kingstomb Desert(136)", "Unknown(72)", "Stinging Swamp(157)", "Three Pine Grove(159)", "The Great Mountains(160)", "Snowford(161)")

for ($ri = 0; $ri -lt $provOffsets.Count; $ri++) {
    $po = $provOffsets[$ri]
    $pn = $provNames[$ri]
    Add ("--- Commander {0} at province {1} ---" -f ($ri+1), $pn)
    Add ("  Context [-0x20 .. +0x20]:")
    Add ("    {0}" -f (hex ($po-0x20) 0x40))
    # Try to decode order
    # The bytes just before 1A 02 [prov]:
    $orderByte = i16($po - 4)  # 2 bytes before "1A 02"
    $flagByte = u16($po - 6)
    Add ("  FlagWord[-6]:  0x{0:X4} = {1}" -f $flagByte, $flagByte)
    Add ("  OrderCode[-4]: 0x{0:X4} = {1} (signed: {2})" -f (u16($po-4)), (u16($po-4)), (i16($po-4)))
    Add ("  Marker[-2]:    0x{0:X4}" -f (u16($po-2)))
    Add ("  ProvID:        {0}" -f (u16 $po))
    Add ("  AfterProv:     {0}" -f (hex ($po+2) 0x08))
    Add ""
}

# Now look at the order codes - what do the numbers mean?
# Known Dominions order codes (from community research):
# In .2h files, common order opcodes:
#   0x0001 / 1  = No order / Stay
#   0x0002 / 2  = Move to province  
#   0x0003 / 3  = Attack province
#   0x0004 / 4  = Move + attack (storm?)
#   0x0005 / 5  = Patrol
#   0x0007 / 7  = Defend
#   0x000B / 11 = Recruit unit
#   0x000D / 13 = Recruit commander
#   0x0011 / 17 = Cast ritual
#   0x0019 / 25 = Forge item
#   0x002A / 42 = Attack (?)
# Negative values might be "attack province -X" relative encoding?

Add "=== ORDER CODE ANALYSIS ==="
Add ""
Add "  Cmdr1 Province 136: OrderCode=0x002A (42) - possibly ATTACK"
Add "  Cmdr2 Province  72: need deeper look"  
Add "  Cmdr3 Province 157: OrderCode=0xFFF8 (-8 signed) - unknown"
Add "  Cmdr4 Province 159: OrderCode=0x0007 (7) - DEFEND?"
Add "  Cmdr5 Province 160: OrderCode=0xFFD9 (-39 signed) - unknown"
Add "  Cmdr6 Province 161: OrderCode=0xFFDA (-38 signed) - unknown"
Add ""

# Look at commander 2 more carefully (province 72 at 0x0259)
Add "--- Commander 2 detailed (around 0x0230-0x0270) ---"
Add (hex 0x0230 0x50)
Add ""

# Now look at the UNIT records (0x1A88 onwards after the big FF block)
Add "================================================================"
Add "=== UNIT/TROOP RECORDS (0x1A88+) ==="
Add "================================================================"
Add ""
Add "After the big FF block (fog-of-war data for provinces 0x0BB9-0x1A87),"
Add "we have individual unit records. Pattern: [unit_id: 4B] [unit_type: 2B] ..."
Add "followed by [prov: 2B] [nation: 2B] and optional orders."
Add ""

# From the dump, starting at 0x1A88 we see structured records
# At 0x1AB0: 01 51 = unit at province 0x51=81?
# Let's look at the repeating structure in 0x1B10 onwards:
# 0x1B10: 03 01 00 01 00 86 22 ... then a long list of unit IDs (2B each)
# This looks like a unit roster with spell IDs
# At 0x1B40+: 4F 04 50 04 51 04 ... these are 2-byte IDs in sequence (0x44F, 0x450, 0x451...)
# These are likely UNIT TYPE IDs

Add "--- Spell/unit type list at 0x1B10 ---"
Add ("  {0}" -f (hex 0x1B10 0x60))
Add ""
Add "  Byte[0x1B10]=0x03 (count?), Byte[0x1B12]=0x01, Byte[0x1B14]=0x00"
Add "  Byte[0x1B15]=0x86=134... unit type?"  
Add "  Byte[0x1B16]=0x22=34..."
Add "  Followed by list of 2-byte IDs:"

$listStart = 0x1B17
Add ("  ID list: ", "")
$ids = [System.Collections.Generic.List[string]]::new()
for ($k = $listStart; $k -lt 0x1B63 -and $k -lt $bytes.Length - 1; $k += 2) {
    $id = u16 $k
    if ($id -eq 0xFFFF) { break }
    $ids.Add(("0x{0:X3}" -f $id))
}
Add ("    {0}" -f ($ids -join ", "))
Add ""

# Commander records in 0x1BB0+ region
# Each commander has: unit_id (4B), then ~0xE0 bytes of stats/equip
# At 0x1BB8: FF FF FF FF 12 01 28 00 9F 00 9F 00 ...
# 0x12 01 = unit_type 0x0112 = 274? 
# 0x28 00 = 40 (HP? or stat?)
# 0x9F 00 = 159 (province 159!)  
# At 0x1C08: 76 00 50 00 -> unit at prov 0x76=118? nation 0x50=Jotunheim

Add "--- Unit records from 0x1BB8 (commanders with province assignments) ---"
Add ""
# Pattern seems: [FF FF FF FF] [unit_type: 2B] [stat1: 2B] [prov: 2B] [prov2: 2B] [flags: 2B] ... [unitID: 2B] [nation: 2B]
# Let's look at each ~0xE0 sized block

$unitStarts = @(0x1BB8, 0x1C70, 0x1D28, 0x1DC0, 0x1E70, 0x1F20, 0x1FD0, 0x2080, 0x2130, 0x21E0, 0x2290, 0x2340, 0x23F0, 0x24A0)

foreach ($us in $unitStarts) {
    if ($us + 0x20 -ge $bytes.Length) { break }
    # Look for FFFF pattern to find unit type
    $typeOff = -1
    for ($k = $us; $k -lt [Math]::Min($us+0x10, $bytes.Length-1); $k++) {
        if ($bytes[$k] -eq 0xFF -and $bytes[$k+1] -eq 0xFF) { $typeOff = $k+2; break }
    }
    if ($typeOff -lt 0) { continue }
    if ($typeOff + 8 -ge $bytes.Length) { break }
    $utype = u16 $typeOff
    $stat1 = u16($typeOff+2)
    $prov  = u16($typeOff+4)
    $prov2 = u16($typeOff+6)
    # Find unit ID: look for XX 00 50 00 pattern
    $uid = -1
    for ($k = $typeOff+8; $k -lt [Math]::Min($typeOff+0x80, $bytes.Length-1); $k++) {
        if ($bytes[$k+1] -eq 0x00 -and $bytes[$k+2] -eq 0x50 -and $bytes[$k+3] -eq 0x00 -and $bytes[$k] -lt 0x80) {
            $uid = $bytes[$k]
            break
        }
    }
    Add ("  [0x{0:X4}] UnitType=0x{1:X4}({1}) Stat1=0x{2:X4} Prov={3} Prov2={4} UnitID=0x{5:X2}" -f $us, $utype, $stat1, $prov, $prov2, $uid)
}

Add ""
Add "=== LARGE UNIT BLOCK (0x2530+) - Recruited/army units ==="
Add ""
Add "From 0x2530 onwards, records of ~0xA8 bytes each with:"
Add "[unit_id_global: 4B] [flags: 4B] [unit_type: 2B] [prov: 2B] [nation: 2B] ... [count_or_hp: 2B] ..."
Add ""

# These records: at 0x2539: A7 1D 00 00 = unit global ID 0x1DA7=7591
# 0x2551: FF FF FF FF -> then 0x14 01 = type 276
# 0x2553: 21 00 = 33, 0x2555: A1 00 = 161 prov, 0x2557: 9F 00 = 159
# 0x255D: 1A 00 = 26 (something)
# 0x2576: 4A 00 = 74 (unit ID local)
# 0x2578: 50 00 = nation Jotunheim
# 0x257A: B2 06 = 0x06B2 = 1714... hmm. XP? or unit type ID again?
# 0x257E: 06 00 06 00 = count 6? 

$bigBlocks = @(0x2539, 0x25E6, 0x2693, 0x2740, 0x27ED, 0x289A, 0x2947, 0x29F5, 0x2AA2, 0x2B4F, 0x2BFB, 0x2CA8)
foreach ($bb in $bigBlocks) {
    if ($bb + 0x50 -ge $bytes.Length) { break }
    $gid = u32 $bb
    # Find FFFF then type
    $typeOff = -1
    for ($k = $bb; $k -lt [Math]::Min($bb+0x20, $bytes.Length-1); $k++) {
        if ($bytes[$k] -eq 0xFF -and $bytes[$k+1] -eq 0xFF -and $bytes[$k+2] -eq 0xFF -and $bytes[$k+3] -eq 0xFF) {
            $typeOff = $k+4; break
        }
    }
    if ($typeOff -lt 0) { continue }
    if ($typeOff + 0x14 -ge $bytes.Length) { break }
    $utype  = u16 $typeOff
    $stat1  = u16($typeOff+2)
    $prov   = u16($typeOff+4)
    $prov2  = u16($typeOff+6)
    $unk1   = u16($typeOff+8)
    # Find XX 00 50 00 for local unit ID
    $uid = -1
    $countA = 0; $countB = 0
    for ($k = $typeOff+12; $k -lt [Math]::Min($typeOff+0x30, $bytes.Length-3); $k++) {
        if ($bytes[$k+1] -eq 0x00 -and $bytes[$k+2] -eq 0x50 -and $bytes[$k+3] -eq 0x00 -and $bytes[$k] -lt 0xFF -and $bytes[$k] -gt 0) {
            $uid = $bytes[$k]
            # After nation, look for a count/type pattern: XX YY 00 00
            if ($k+5 -lt $bytes.Length) {
                $countA = u16($k+4)
                $countB = u16($k+6)
            }
            break
        }
    }
    Add ("  [0x{0:X4}] GlobalID=0x{1:X8}({1}) UType=0x{2:X4} Stat={3} Prov={4}/{5} LocalID={6} Count?={7}/{8}" -f $bb, $gid, $utype, $stat1, $prov, $prov2, $uid, $countA, $countB)
}

Add ""
Add "=== XOR-DECODED STRINGS (all readable strings) ==="
Add ""
# Full string scan
$i2 = 0
while ($i2 -lt $bytes.Length) {
    if ($bytes[$i2] -eq 0x4F) {
        $end2 = $i2
        $j2 = $i2 - 1
        $runlen = 0
        while ($j2 -ge 0 -and $j2 -ge ($i2-300)) {
            $decoded = $bytes[$j2] -bxor $KEY
            if ($decoded -ge 32 -and $decoded -le 126) { $j2--; $runlen++ } else { break }
        }
        $start2 = $j2 + 1
        if ($runlen -ge 6) {
            $str = xstr $start2 $end2
            $alphas = ($str.ToCharArray() | Where-Object { [char]::IsLetterOrDigit($_) -or $_ -eq ' ' }).Count
            if ($alphas -gt ($runlen * 0.55)) {
                Add ("  [0x{0:X4}] len={1}: `"{2}`"" -f $start2, $runlen, $str)
            }
        }
    }
    $i2++
}

Add ""
Add "=== RECRUITMENT ORDERS (0x2D50+ region - commander sections) ==="
Add ""
Add "This section contains named commanders/heroes with their assigned troops."
Add "Pattern: [global_unit_id: 4B] [flags?] [FF*10] [name_xor...0x4F] [unit_id: 4B] [DE 39 17 00?] ..."
Add ""

# At 0x2D54: FF FF FF FF  2B 01 00 00  08 3A 2B 23 2E 3A 28 4F
# 0x2B01 = 11009 (unit type? or global ID?)
# 0x08 = length prefix? 0x08 bytes follow until 0x4F
# Decode: 3A 2B 23 2E 3A 28 = "urding" -> XOR: 75 64 6C 61 75 67 = "udlaug" -- wait
# 0x3A^0x4F=0x75='u', 0x2B^0x4F=0x64='d', 0x23^0x4F=0x6C='l', 0x2E^0x4F=0x61='a', 0x3A^0x4F=0x75='u', 0x28^0x4F=0x67='g'
# So: "Gudlaug" (matches our earlier find!)

# Let me find all named entities
$nameRegions = @(
    @{off=0x2D54; label="Named Entity 1"},
    @{off=0x2E2D; label="Named Entity 2"},
    @{off=0x2F05; label="Named Entity 3"},
    @{off=0x2FE0; label="Named Entity 4"},
    @{off=0x30B8; label="Named Entity 5"}
)

foreach ($nr in $nameRegions) {
    $o = $nr.off
    if ($o + 0x30 -ge $bytes.Length) { continue }
    Add ("--- {0} at 0x{1:X4} ---" -f $nr.label, $o)
    # Find the 0x4F terminator for name
    $nameStart = -1
    $nameEnd = -1
    for ($k = $o; $k -lt [Math]::Min($o+0x30, $bytes.Length); $k++) {
        $dec = $bytes[$k] -bxor $KEY
        if ($dec -ge 32 -and $dec -le 126 -and $nameStart -lt 0) { $nameStart = $k }
        if ($bytes[$k] -eq 0x4F -and $nameStart -ge 0) { $nameEnd = $k; break }
    }
    if ($nameStart -ge 0 -and $nameEnd -gt $nameStart) {
        Add ("  Name: '{0}'" -f (xstr $nameStart $nameEnd))
    }
    Add ("  Raw: {0}" -f (hex $o 0x30))
    # Look for unit type: search for small uint16 after the name
    if ($nameEnd -gt 0 -and $nameEnd + 10 -lt $bytes.Length) {
        Add ("  Post-name bytes: {0}" -f (hex $nameEnd 0x14))
    }
    Add ""
}

Add ""
Add "=== ATTACK/MOVE ORDER SUMMARY ==="
Add ""
Add "Based on order code bytes preceding province IDs:"
Add ""
Add "  Prefix pattern: FF FF 00 00 FF [order_lo] [order_hi] 1A 02 [prov_lo] [prov_hi]"
Add "  (0x1A02 appears to be a fixed marker separating order code from target)"
Add ""
Add "  Order codes observed:"
Add "    0x002A = 42  (before prov 136 'Kingstomb Desert')"
Add "    0xFFF8 = -8  (before prov 157 'Stinging Swamp')"  
Add "    0x0007 = 7   (before prov 159 'Three Pine Grove')"
Add "    0xFFD9 = -39 (before prov 160 'The Great Mountains')"
Add "    0xFFDA = -38 (before prov 161 'Snowford')"
Add ""
Add "  Note: negative order codes might be relative province offsets"
Add "  or direction-based movement codes."
Add ""
Add "  For commander 2 (prov 72), we need to look at 0x0220-0x0260 region."

# Let's decode commander 2's order more carefully
Add ""
Add "--- Commander 2 full context (0x0220-0x0270) ---"
Add (hex 0x0220 0x60)
Add ""
Add "  Bytes[0x0244-0x0260]: {0}" -f (hex 0x0244 0x1C)
Add ("  Province at 0x0259 = {0}" -f (u16 0x0259))
Add ("  OrderCode at 0x0255 = 0x{0:X4} = {1}" -f (u16 0x0255), (i16 0x0255))

$outpath = 'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\deep_analysis.txt'
[System.IO.File]::WriteAllLines($outpath, $out, [System.Text.UTF8Encoding]::new($false))
Write-Host "Written to $outpath"
