<#
.SYNOPSIS
    Verify every generated chapter page is reachable from the catalog.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\sishengxinyuan'
)

$out = New-Object System.Collections.Generic.List[string]

$pages = Get-ChildItem -LiteralPath $Root -File -Filter '*.html' |
    Where-Object { $_.Name -match '^\d+-\d+\.html$' } |
    Select-Object -ExpandProperty Name
$out.Add("chapter pages         : $($pages.Count)")

# links present in index.html catalog + catalog.js
$idx = [IO.File]::ReadAllText((Join-Path $Root 'index.html'))
$cat = [IO.File]::ReadAllText((Join-Path $Root 'static\js\catalog.js'))

$linked = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($m in [regex]::Matches($idx, 'href="(\d+-\d+\.html)"')) { [void]$linked.Add($m.Groups[1].Value) }
foreach ($m in [regex]::Matches($cat, 'href=\\"(\d+-\d+\.html)\\"')) { [void]$linked.Add($m.Groups[1].Value) }

$out.Add("unique links (index)  : $(([regex]::Matches($idx,'href=""(\d+-\d+\.html)""')).Count)")
$out.Add("unique links (catalog): $(([regex]::Matches($cat,'href=\\""(\d+-\d+\.html)\\""')).Count)")
$out.Add("unique link targets   : $($linked.Count)")

$orphans = @()
foreach ($p in $pages) { if (-not $linked.Contains($p)) { $orphans += $p } }

$broken = @()
foreach ($l in $linked) { if (-not (Test-Path -LiteralPath (Join-Path $Root $l))) { $broken += $l } }

$out.Add('')
$out.Add("orphaned pages        : $($orphans.Count)")
if ($orphans.Count -gt 0) { $out.Add('  ' + ($orphans -join ', ')) }
$out.Add("broken links          : $($broken.Count)")
if ($broken.Count -gt 0) { $out.Add('  ' + ($broken -join ', ')) }

$f = Join-Path $env:TEMP 'sisheng-verify.txt'
$out | Set-Content -Path $f -Encoding UTF8
Get-Content $f -Encoding UTF8
