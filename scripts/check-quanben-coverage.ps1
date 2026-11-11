<#
.SYNOPSIS
    Check whether quanben.html (full-book page) contains every chapter body.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu'
)

$ErrorActionPreference = 'Stop'
$qb = Join-Path $Root 'quanben.html'
$text = [IO.File]::ReadAllText($qb)

$out = New-Object System.Collections.Generic.List[string]
$out.Add("quanben.html : {0:N0} KB" -f ((Get-Item $qb).Length / 1KB))

# chapter anchors <div class="section" id="ciNNN">
$ids = [regex]::Matches($text, 'id="ci(\d+)"') | ForEach-Object { $_.Groups[1].Value }
$out.Add("chapter anchors (id=ciNNN) : $($ids.Count)")
$out.Add("first 3 : $($ids[0..2] -join ', ')")
$out.Add("last 3  : $($ids[-3..-1] -join ', ')")

# which chapter files are missing locally?
$missing = Import-Csv (Join-Path $Root '_missing_chapters.csv')
$out.Add("")
$out.Add("missing chapter files : $($missing.Count)")

# map: index.html has <li id="siNNN"><a href="...513-52-6.html" ...>
$index = [IO.File]::ReadAllText((Join-Path $Root 'index.html'))
$map = @{}
foreach ($m in [regex]::Matches($index, '<li id="si(\d+)"><a href="([^"]+)" title="([^"]*)">')) {
    $si = $m.Groups[1].Value
    $href = $m.Groups[2].Value
    $name = ($href -split '[?#]')[0].TrimEnd('/')
    $name = ($name -split '/')[-1]
    if ($name) { $map[$name] = @{ Si = $si; Title = $m.Groups[3].Value } }
}

$out.Add("")
$out.Add("file            si        inQuanben   title")
$out.Add("----            --        ---------   -----")
$found = 0
$notFound = @()
foreach ($row in $missing) {
    $f = $row.File
    $si = if ($map.ContainsKey($f)) { $map[$f].Si } else { '?' }
    $present = ($si -ne '?' -and $ids -contains $si)
    if ($present) { $found++ } else { $notFound += $f }
    $out.Add(("{0,-15} {1,-9} {2,-11} {3}" -f $f, $si, $present, $row.Title))
}

$out.Add("")
$out.Add("present in quanben : $found / $($missing.Count)")
if ($notFound.Count -gt 0) {
    $out.Add("NOT present : $($notFound -join ', ')")
}

$outFile = Join-Path $env:TEMP 'quanben-check.txt'
$out | Set-Content -Path $outFile -Encoding UTF8
Get-Content $outFile -Encoding UTF8
