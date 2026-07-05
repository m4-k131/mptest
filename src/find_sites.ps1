# Search for magic site records and event text in .trn files
# Magic sites in Dominions appear as named structures with an associated province
# The .trn contains province data including site IDs
# XOR key = 0x4F

$KEY = 0x4F
$path = 'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\mid_jotunheim.trn'
$bytes = [System.IO.File]::ReadAllBytes($path)
$out = [System.Collections.Generic.List[string]]::new()

function xdec($s,$e) {
    $r=""
    for($k=$s;$k -lt $e -and $k -lt $bytes.Length;$k++){
        $c=$bytes[$k] -bxor $KEY
        if($c -ge 32 -and $c -le 126){$r+=[char]$c}else{$r+="."}
    }
    return $r
}
function hex2($s,$l){
    $r=""
    for($k=$s;$k -lt ($s+$l) -and $k -lt $bytes.Length;$k++){$r+="{0:X2} " -f $bytes[$k]}
    return $r.TrimEnd()
}
function u16($o){[BitConverter]::ToUInt16($bytes,$o)}
function u32($o){[BitConverter]::ToUInt32($bytes,$o)}
function Add($s){$out.Add($s)}

Add "==================================================================="
Add "MAGIC SITES + EVENTS ANALYSIS - mid_jotunheim.trn"
Add "==================================================================="
Add ""
Add "File size: $($bytes.Length) bytes"
Add ""

# The .trn has ALL province data for the player's visibility
# Province records include: province_id, owner, terrain, sites[], units[], events[]
#
# Known site name strings found in jotunheim.trn string scan:
# "Wise Spring Grove" [0x080A7]
# "D3-Dracolich" [0x0E11] and [0x231E2]
# "Black Riders" [0x30EB6]
# "Burelk's City Guard" [0x30EF8]
#
# Now let's find the SITE RECORD structures around these names.
# Pattern: site name is XOR-encoded, preceded by site_id (uint16 or uint32) and prov_id

# Find "Wise Spring Grove" bytes XOR encoded
$target = "Wise Spring Grove"
$targetBytes = $target.ToCharArray() | ForEach-Object { [byte]([byte][char]$_ -bxor $KEY) }
# Find it in file
$found = [System.Collections.Generic.List[int]]::new()
for($i=0;$i -lt $bytes.Length - $targetBytes.Length;$i++){
    $match=$true
    for($j=0;$j -lt $targetBytes.Length;$j++){
        if($bytes[$i+$j] -ne $targetBytes[$j]){$match=$false;break}
    }
    if($match){$found.Add($i)}
}
Add "--- 'Wise Spring Grove' locations ---"
foreach($f in $found){
    Add ("  At 0x{0:X5}: pre=[ {1}] post=[ {2}]" -f $f, (hex2 ([Math]::Max(0,$f-16)) 16), (hex2 ($f+$targetBytes.Length) 16))
}
Add ""

# Find "D3-Dracolich"
$target2 = "D3-Dracolich"
$t2b = $target2.ToCharArray() | ForEach-Object { [byte]([byte][char]$_ -bxor $KEY) }
$found2 = [System.Collections.Generic.List[int]]::new()
for($i=0;$i -lt $bytes.Length - $t2b.Length;$i++){
    $match=$true
    for($j=0;$j -lt $t2b.Length;$j++){
        if($bytes[$i+$j] -ne $t2b[$j]){$match=$false;break}
    }
    if($match){$found2.Add($i)}
}
Add "--- 'D3-Dracolich' locations ---"
foreach($f in $found2){
    Add ("  At 0x{0:X5}: pre=[ {1}] post=[ {2}]" -f $f, (hex2 ([Math]::Max(0,$f-16)) 16), (hex2 ($f+$t2b.Length) 16))
}
Add ""

# Also search for "Black Riders" and "Burelk's City Guard" (army names / events)
foreach($tname in @("Black Riders", "Burelk's City Guard", "Gudlaug", "Greip", "Sigtryg", "Elle", "Ratchis")) {
    $tb = $tname.ToCharArray() | ForEach-Object { [byte]([byte][char]$_ -bxor $KEY) }
    $fl = [System.Collections.Generic.List[int]]::new()
    for($i=0;$i -lt $bytes.Length - $tb.Length;$i++){
        $m=$true
        for($j=0;$j -lt $tb.Length;$j++){if($bytes[$i+$j] -ne $tb[$j]){$m=$false;break}}
        if($m){$fl.Add($i)}
    }
    Add ("--- '$tname' locations ---")
    foreach($f in $fl){
        Add ("  At 0x{0:X5}: pre=[ {1}] post=[ {2}]" -f $f, (hex2 ([Math]::Max(0,$f-16)) 16), (hex2 ($f+$tb.Length) 16))
    }
    Add ""
}

# Now look at 0x080A7 region (Wise Spring Grove) more carefully
# According to the string scan this site appears at 0x080A7 in jotunheim.trn
Add "--- Detailed region around 'Wise Spring Grove' at 0x080A7 ---"
Add (hex2 0x07F80 0x80)
Add ""
Add "Decoded: $(xdec 0x07F80 (0x07F80+0x80))"
Add ""

# Let's look at the province record structure around the site area
# Jotunheim .trn province records: each province block is characterized by
# the XOR-encoded province name followed by large areas of province data
# The big blocks of "OOOOO...OOO" (0x4F bytes) are terrain/fog bitmasks (75-91 bytes = ~8-10 bytes real data)
# Decoding the OOOOO pattern: 0x4F ^ 0x4F = 0x00 -> those are all-zero fields!

# Let's look at what's between province records to find site data
# Province record structure (estimated):
# [prov_id: 2B][owner: 2B][capital_flag: 2B][terrain: 4B][resources: ?][sites: list][units: list][events: list]
# The "OOOO...OOO" runs are the site/feature bitmask arrays (all zeros = no magic sites)
# Provinces WITH sites will have non-zero bytes in those arrays!

Add "--- Scanning for non-zero site bitmask bytes in province records ---"
Add "(Province records have 75-91 byte bitmask arrays; non-zero = feature present)"
Add ""

# The province records in the .trn seem to start around 0x01AD (province 1 = Amiridon)
# and be ~0x140 bytes each based on the regular occurrence of province names
# Let's find all province name occurrences and check the bitmask between them

# Known province name -> XOR bytes pattern: find the "OOO" + name occurrences (3 leading 0x4F bytes = terminators)
# Then look back 75-91 bytes before name for the bitmask

# Let me find province blocks by looking for the double-name pattern
# Each province: [bitmask ~89 bytes][OOO+name][name][next_bitmask]
# The bitmask bytes XOR 0x4F: if non-0x4F -> non-zero feature

# Scan each bitmask block for non-zero values
Add "Province bitmask scan (non-zero bytes indicate magic sites or special features):"
Add ""

# Province names and their bitmask offset from string scan:
# Province 1 Amiridon: bitmask at 0x0022C (89 bytes), name starts 0x002F5
# Province 2 Belmar: bitmask at 0x0036E (89 bytes), name at 0x00436
# ...each ~0x140 bytes apart

# Strategy: find all 75-91 byte runs where bytes differ from 0x4F
$provBitmasks = [System.Collections.Generic.List[object]]::new()

# Find all "OOO" prefixed province names by scanning for runs of 0x4F terminated strings
$i2 = 0
while($i2 -lt $bytes.Length - 6) {
    # Look for a run of 0x4F bytes (bitmask = all zeros after XOR)
    if($bytes[$i2] -eq 0x4F) {
        # Count run
        $runStart = $i2
        $runLen = 0
        while($i2 + $runLen -lt $bytes.Length -and $bytes[$i2+$runLen] -eq 0x4F) { $runLen++ }
        if($runLen -ge 67 -and $runLen -le 132) {
            # This is a province bitmask! Check if any bytes differ from 0x4F in the same region
            $nonzero = [System.Collections.Generic.List[string]]::new()
            for($k=$runStart; $k -lt $runStart+$runLen; $k++) {
                if($bytes[$k] -ne 0x4F) {
                    $nonzero.Add(("off+{0}=0x{1:X2}" -f ($k-$runStart), $bytes[$k]))
                }
            }
            if($nonzero.Count -gt 0) {
                $provBitmasks.Add([PSCustomObject]@{
                    Start=$runStart; Len=$runLen; NonZero=$nonzero
                })
            }
        }
        $i2 += [Math]::Max(1, $runLen)
    } else {
        $i2++
    }
}

foreach($pb in $provBitmasks) {
    # Find province name before/after this block
    $nameAfterStart = $pb.Start + $pb.Len
    $nameEnd = $nameAfterStart
    while($nameEnd -lt $bytes.Length -and $bytes[$nameEnd] -ne 0x4F) { $nameEnd++ }
    $pname = xdec $nameAfterStart $nameEnd
    # Find 2-byte province ID (look back a bit before the bitmask for the first XOR-encoded name = "OOO"+name pattern)
    Add ("  [0x{0:X5}] Len={1} Province~'{2}'" -f $pb.Start, $pb.Len, $pname)
    Add ("    Non-zero bytes: {0}" -f ($pb.NonZero -join ", "))
    # Try to decode what the non-zero bytes mean:
    # Bitmask positions in Dominions province bitmasks:
    # Bytes 0-3: terrain (already know from .map file)
    # Bytes 4-7: nation/owner related?
    # Bytes 8+: site flags, event flags
    foreach($nz in $pb.NonZero) {
        $parts = $nz -split "="
        $off = [int]($parts[0].Replace("off+",""))
        $val = [Convert]::ToInt32($parts[1], 16)
        $decoded = $val -bxor $KEY
        Add ("      Byte[+$off]: raw=0x{0:X2} decoded=0x{1:X2} ({1})" -f $val, $decoded)
    }
    Add ""
}

$outpath = 'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\sites_events.txt'
[System.IO.File]::WriteAllLines($outpath, $out, [System.Text.UTF8Encoding]::new($false))
Write-Host "Written $($out.Count) lines to $outpath"
