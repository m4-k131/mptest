# Decode .trn files for magic sites and random events
# Also cross-reference order codes
$KEY = 0x4F

function xdec($bytes, $start, $end) {
    $s = ""
    for ($k = $start; $k -lt $end -and $k -lt $bytes.Length; $k++) {
        $c = $bytes[$k] -bxor $KEY
        if ($c -ge 32 -and $c -le 126) { $s += [char]$c } else { $s += "." }
    }
    return $s
}
function hex2($bytes, $start, $len) {
    $s = ""
    for ($k = $start; $k -lt ($start+$len) -and $k -lt $bytes.Length; $k++) { $s += "{0:X2} " -f $bytes[$k] }
    return $s.TrimEnd()
}
function u16($bytes, $off) { [BitConverter]::ToUInt16($bytes, $off) }
function u32($bytes, $off) { [BitConverter]::ToUInt32($bytes, $off) }

$out = [System.Collections.Generic.List[string]]::new()
function Add($s) { $out.Add($s) }

# ---- Decode all XOR strings from JOTUNHEIM .TRN (much larger = more data) ----
Add "================================================================"
Add "ALL XOR-DECODED STRINGS FROM mid_jotunheim.trn"
Add "(Province names, event text, magic site descriptions, hero names)"
Add "================================================================"
Add ""

$trnPath = 'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\mid_jotunheim.trn'
$tb = [System.IO.File]::ReadAllBytes($trnPath)

Add ("TRN size: {0} bytes" -f $tb.Length)
Add ""

# Scan for all XOR strings terminated by 0x4F
$seen = [System.Collections.Generic.HashSet[string]]::new()
$i = 0
while ($i -lt $tb.Length) {
    if ($tb[$i] -eq 0x4F) {
        $j = $i - 1
        while ($j -ge 0 -and $j -ge ($i - 512)) {
            $dec = $tb[$j] -bxor $KEY
            if ($dec -ge 32 -and $dec -le 126) { $j-- } else { break }
        }
        $start = $j + 1
        $len = $i - $start
        if ($len -ge 5) {
            $str = xdec $tb $start $i
            $alphas = ($str.ToCharArray() | Where-Object { [char]::IsLetterOrDigit($_) -or $_ -eq ' ' -or $_ -eq '-' -or $_ -eq "'" }).Count
            if ($alphas -gt ($len * 0.5) -and -not $seen.Contains($str)) {
                $seen.Add($str) | Out-Null
                Add ("  [0x{0:X5}] len={1,3}: `"{2}`"" -f $start, $len, $str)
            }
        }
    }
    $i++
}

Add ""
Add "================================================================"
Add "ALL XOR-DECODED STRINGS FROM mid_ermor.trn"
Add "================================================================"
Add ""

$ePath = 'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\mid_ermor.trn'
$eb = [System.IO.File]::ReadAllBytes($ePath)
Add ("Ermor TRN size: {0} bytes" -f $eb.Length)
Add ""

$seen2 = [System.Collections.Generic.HashSet[string]]::new()
$i = 0
while ($i -lt $eb.Length) {
    if ($eb[$i] -eq 0x4F) {
        $j = $i - 1
        while ($j -ge 0 -and $j -ge ($i - 512)) {
            $dec = $eb[$j] -bxor $KEY
            if ($dec -ge 32 -and $dec -le 126) { $j-- } else { break }
        }
        $start = $j + 1
        $len = $i - $start
        if ($len -ge 5) {
            $str = xdec $eb $start $i
            $alphas = ($str.ToCharArray() | Where-Object { [char]::IsLetterOrDigit($_) -or $_ -eq ' ' -or $_ -eq '-' -or $_ -eq "'" }).Count
            if ($alphas -gt ($len * 0.5) -and -not $seen2.Contains($str)) {
                $seen2.Add($str) | Out-Null
                Add ("  [0x{0:X5}] len={1,3}: `"{2}`"" -f $start, $len, $str)
            }
        }
    }
    $i++
}

# Also scan ftherlnd for magic sites / global events
Add ""
Add "================================================================"
Add "STRINGS FROM ftherlnd (global gamestate)"
Add "================================================================"
Add ""

$fPath = 'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\ftherlnd'
$fb = [System.IO.File]::ReadAllBytes($fPath)
Add ("ftherlnd size: {0} bytes" -f $fb.Length)
Add ""

$seen3 = [System.Collections.Generic.HashSet[string]]::new()
$i = 0
while ($i -lt $fb.Length) {
    if ($fb[$i] -eq 0x4F) {
        $j = $i - 1
        while ($j -ge 0 -and $j -ge ($i - 512)) {
            $dec = $fb[$j] -bxor $KEY
            if ($dec -ge 32 -and $dec -le 126) { $j-- } else { break }
        }
        $start = $j + 1
        $len = $i - $start
        if ($len -ge 6) {
            $str = xdec $fb $start $i
            $alphas = ($str.ToCharArray() | Where-Object { [char]::IsLetterOrDigit($_) -or $_ -eq ' ' -or $_ -eq '-' -or $_ -eq "'" }).Count
            if ($alphas -gt ($len * 0.55) -and -not $seen3.Contains($str)) {
                $seen3.Add($str) | Out-Null
                Add ("  [0x{0:X5}] len={1,3}: `"{2}`"" -f $start, $len, $str)
            }
        }
    }
    $i++
}

$outpath = 'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\strings_all.txt'
[System.IO.File]::WriteAllLines($outpath, $out, [System.Text.UTF8Encoding]::new($false))
Write-Host "Written to $outpath ($(($out.Count)) lines)"
