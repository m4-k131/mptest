# Dominions 6 .2h file analysis script
# XOR key appears to be 0x4F based on "4F 4F" sentinel and the pattern where
# text-like bytes appear. Let's try several XOR keys.

param([string]$file = "mid_jotunheim.2h")

$path = "C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\$file"
$bytes = [System.IO.File]::ReadAllBytes($path)
$outlines = [System.Collections.Generic.List[string]]::new()

function Add($s) { $outlines.Add($s) }

# ---- 1. Find all XOR-decodable strings ----
# The pattern seems to be: length byte, then XOR-encoded chars, terminated by 0x4F (which XORs to 0x00? No...)
# Let's check: "4F 4F" appears as separator/sentinel between text blocks
# The ASCII-ish sequences: e.g. at 0x166: "2E 3B 2A 6F 1C 3F 3D 26 21 28 6F..."
# 0x6F = 'o' in ASCII. If XOR key = 0x4F: 0x6F ^ 0x4F = 0x20 (space). That's promising!
# 0x2E ^ 0x4F = 0x61 = 'a', 0x3B ^ 0x4F = 0x74 = 't', 0x2A ^ 0x4F = 0x65 = 'e'
# So 0x2E 0x3B 0x2A = "ate" -- makes sense!
# Let's decode with XOR 0x4F

$KEY = 0x4F

Add "=== XOR-0x4F string scan of $file ==="
Add ""

# Scan for length-prefixed XOR strings
# Pattern: small length byte (1-2 bytes?) followed by XOR-encoded printable text
# terminated by 0x4F (which decodes to 0x00 = null terminator)
Add "--- Searching for XOR-encoded text strings (key=0x4F, terminated by 0x4F) ---"
$i = 0
while ($i -lt $bytes.Length - 4) {
    # Look for 0x4F as string terminator - scan backwards to find start
    if ($bytes[$i] -eq 0x4F) {
        # Look back to find a run of "printable" XOR bytes (0x20-0x7E when XORed with 0x4F)
        $end = $i
        $j = $i - 1
        while ($j -ge 0 -and $j -ge ($i - 200)) {
            $decoded = $bytes[$j] -bxor $KEY
            if ($decoded -ge 32 -and $decoded -le 126) { $j-- } else { break }
        }
        $start = $j + 1
        $len = $end - $start
        if ($len -ge 8) {
            $str = ""
            for ($k = $start; $k -lt $end; $k++) {
                $str += [char]($bytes[$k] -bxor $KEY)
            }
            # Check if it looks like real text (many spaces/alphanumeric)
            $spaces = ($str.ToCharArray() | Where-Object { $_ -eq ' ' }).Count
            $alphas = ($str.ToCharArray() | Where-Object { [char]::IsLetterOrDigit($_) }).Count
            if ($alphas -gt ($len * 0.5)) {
                Add ("  [0x{0:X4}..0x{1:X4}] len={2}: `"{3}`"" -f $start, $end, $len, $str)
            }
        }
    }
    $i++
}

Add ""
Add "--- Structured record analysis ---"
Add ""

# Known values:
# Nation ID Jotunheim = 0x50 = 80
# Nation ID Ermor = 0x36 = 54
# Province IDs from map: 1-169 surface, plus underground
# Commander/unit records seem ~0xE0 bytes long based on repeating pattern

# Look for province IDs appearing with 0x50 (Jotunheim nation byte)
Add "-- Occurrences of nation byte 0x50 (Jotunheim) --"
for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 0x50) {
        $ctx = ""
        $start = [Math]::Max(0, $i-8)
        $end2 = [Math]::Min($bytes.Length-1, $i+8)
        for ($k = $start; $k -le $end2; $k++) {
            if ($k -eq $i) { $ctx += "[{0:X2}]" -f $bytes[$k] }
            else { $ctx += "{0:X2} " -f $bytes[$k] }
        }
        Add ("  0x{0:X4}: {1}" -f $i, $ctx)
    }
}

Add ""
Add "-- Looking for order opcodes / attack commands --"
Add "-- Recurring structure: 0x4F 0x4F (unit separator?), then ~0xE0 bytes per unit --"

# Find all 0x4F 0x4F occurrences
Add ""
Add "-- 0x4F 0x4F sentinel positions --"
for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
    if ($bytes[$i] -eq 0x4F -and $bytes[$i+1] -eq 0x4F) {
        # Show context around it
        $before = ""
        $after = ""
        $bs = [Math]::Max(0, $i-16)
        for ($k = $bs; $k -lt $i; $k++) { $before += "{0:X2} " -f $bytes[$k] }
        $ae = [Math]::Min($bytes.Length-1, $i+17)
        for ($k = $i+2; $k -le $ae; $k++) { $after += "{0:X2} " -f $bytes[$k] }
        Add ("  0x{0:X4}: ...{1} [4F 4F] {2}..." -f $i, $before.TrimEnd(), $after.TrimEnd())
    }
}

Add ""
Add "-- Recurring byte pattern analysis (find unit record size) --"
# The pattern: big blocks of 0xFF (fog/unknown), then a unit header
# Let's find where 0xFF runs end and data resumes
$inFF = $false
$ffStart = 0
$runs = [System.Collections.Generic.List[object]]::new()
for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 0xFF -and -not $inFF) {
        $inFF = $true; $ffStart = $i
    } elseif ($bytes[$i] -ne 0xFF -and $inFF) {
        $inFF = $false
        $runLen = $i - $ffStart
        if ($runLen -ge 8) {
            $runs.Add([PSCustomObject]@{ Start=$ffStart; Len=$runLen; End=$i })
        }
    }
}
Add ("  FF-runs of >=8 bytes: {0}" -f $runs.Count)
foreach ($r in $runs) {
    Add ("    0x{0:X4}-0x{1:X4} len={2}" -f $r.Start, $r.End, $r.Len)
}

Add ""
Add "-- Bytes immediately before each FF-run (potential order type bytes) --"
foreach ($r in $runs) {
    if ($r.Start -ge 4) {
        $ctx = ""
        for ($k = [Math]::Max(0,$r.Start-8); $k -lt $r.Start; $k++) {
            $ctx += "{0:X2} " -f $bytes[$k]
        }
        $after = ""
        for ($k = $r.End; $k -lt [Math]::Min($bytes.Length, $r.End+8); $k++) {
            $after += "{0:X2} " -f $bytes[$k]
        }
        Add ("  Before 0x{0:X4}: [{1}]  After end: [{2}]" -f $r.Start, $ctx.TrimEnd(), $after.TrimEnd())
    }
}

Add ""
Add "-- Province IDs near attack-like structures --"
Add "-- Provinces 1-169 = 0x01-0xA9. Look for small uint16 values paired with order type --"
# Look for the pattern: small province ID (1-169 as uint16 LE) near specific command bytes
for ($i = 4; $i -lt $bytes.Length - 4; $i++) {
    $prov = [BitConverter]::ToUInt16($bytes, $i)
    if ($prov -ge 1 -and $prov -le 169 -and $bytes[$i+2] -eq 0x00 -and $bytes[$i+3] -eq 0x00) {
        # Check if surrounded by interesting context
        $prev2 = [BitConverter]::ToUInt16($bytes, $i-2)
        if ($prev2 -ge 0x0100 -and $prev2 -le 0x0500) {
            # Possibly an order code followed by province
            $ctx = ""
            for ($k = [Math]::Max(0,$i-4); $k -lt [Math]::Min($bytes.Length,$i+8); $k++) {
                if ($k -eq $i) { $ctx += "[" }
                $ctx += "{0:X2}" -f $bytes[$k]
                if ($k -eq $i+1) { $ctx += "]" }
                $ctx += " "
            }
            Add ("  0x{0:X4}: prov={1} ctx={2}" -f $i, $prov, $ctx.TrimEnd())
        }
    }
}

$outpath = "C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\analysis_out.txt"
[System.IO.File]::WriteAllLines($outpath, $outlines, [System.Text.UTF8Encoding]::new($false))
Write-Host "Written to $outpath"
