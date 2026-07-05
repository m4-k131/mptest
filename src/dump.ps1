$path = 'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\mid_jotunheim.2h'
$outpath = 'C:\Users\malte\AppData\Roaming\Dominions6\savedgames\mptest\jotun2h_dump.txt'
$bytes = [System.IO.File]::ReadAllBytes($path)
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('Size: {0} bytes' -f $bytes.Length)
$lines.Add('')
$lines.Add('=== Full hex dump ===')
for ($i = 0; $i -lt $bytes.Length; $i += 16) {
    $end = [Math]::Min($i+15, $bytes.Length-1)
    $chunk = $bytes[$i..$end]
    $hex = ($chunk | ForEach-Object { $_.ToString('X2') }) -join ' '
    $ascii = ($chunk | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' } }) -join ''
    $lines.Add(('{0:X4}: {1,-47}  {2}' -f $i, $hex, $ascii))
}
[System.IO.File]::WriteAllLines($outpath, $lines, [System.Text.Encoding]::UTF8)
