<#
.SYNOPSIS
    Inspect page structure of a normal chapter page and of a quanben section.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu'
)

$out = New-Object System.Collections.Generic.List[string]

# ---- 1. normal page skeleton (no body text) ----
$page = Join-Path $Root '513-52-5.html'
$t = [IO.File]::ReadAllText($page)
$out.Add('===== NORMAL PAGE 513-52-5.html =====')
$out.Add(("size {0:N0} bytes" -f (Get-Item $page).Length))
$out.Add('')
$out.Add('--- head (first 1200 chars) ---')
$out.Add($t.Substring(0, [Math]::Min(1200, $t.Length)))
$out.Add('')
$out.Add('--- body until #content ---')
$i = $t.IndexOf('<body')
$j = $t.IndexOf('<div id="content">')
$out.Add($t.Substring($i, [Math]::Min(1400, $j - $i)))
$out.Add('')
$out.Add('--- from #content end to sidebar-ph ---')
$k = $t.IndexOf('</div>', $j + 2500)
$m = $t.IndexOf('sidebar-ph')
if ($m -lt 0) { $m = $t.IndexOf('<script') }
$seg = $t.Substring([Math]::Max($j, $t.Length - 2600), 2600)
$out.Add($seg)
$out.Add('')

# ---- 2. quanben section for 513-52-6 (si75061) ----
$qb = [IO.File]::ReadAllText((Join-Path $Root 'quanben.html'))
$out.Add('===== QUANBEN section id=ci75061 =====')
$s = $qb.IndexOf('<div class="section" id="ci75061">')
if ($s -lt 0) { $out.Add('NOT FOUND'); }
else {
    $e = $qb.IndexOf('<div class="section" id="ci75062">')
    $out.Add("range $s .. $e  (len $($e - $s))")
    $out.Add('')
    $out.Add($qb.Substring($s, [Math]::Min(1800, $e - $s)))
}

$f = Join-Path $env:TEMP 'struct.txt'
$out | Set-Content -Path $f -Encoding UTF8
Get-Content $f -Encoding UTF8
