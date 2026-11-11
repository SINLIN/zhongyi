<#
.SYNOPSIS
    Validate the links embedded inside generated catalog.js files.

.DESCRIPTION
    catalog.js stores the sidebar HTML as a JS string, so href/src values appear
    escaped as \"...\"  A normal HTML link checker will not see them, but they are
    real navigation targets after the sidebar is injected.

    Resolves each link against the directory that will contain the injected
    sidebar (the page directory) and reports any target that does not exist.
#>
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path,
    [int]$MaxReport = 30
)

$ErrorActionPreference = 'Stop'
$rootFull = (Resolve-Path $Root).Path.TrimEnd('\')

$catalogs = Get-ChildItem -Path $rootFull -Recurse -File -Filter 'catalog.js' |
    Where-Object { $_.FullName -notmatch '\\\.git\\' }

if (-not $catalogs) { 'no catalog.js found'; exit 0 }

$totalLinks = 0
$totalMissing = 0
$report = New-Object System.Collections.Generic.List[string]

foreach ($c in $catalogs) {
    # catalog.js lives in <book>/web/js, <book>/static/js or <book>/js.
    # The injected sidebar resolves links relative to the HTML page directory,
    # so pick the nearest ancestor directory that actually contains *.html.
    $jsDir = $c.Directory.FullName
    $pageDir = $null
    $probe = $jsDir
    for ($i = 0; $i -lt 4 -and $probe; $i++) {
        $candidate = Join-Path (Split-Path $probe -Parent) 'html'
        if (Test-Path -LiteralPath $candidate) {
            if (Get-ChildItem -LiteralPath $candidate -File -Filter *.html -ErrorAction SilentlyContinue) {
                $pageDir = $candidate
                break
            }
        }
        $candidate2 = Split-Path $probe -Parent
        if ($candidate2 -and (Get-ChildItem -LiteralPath $candidate2 -File -Filter *.html -ErrorAction SilentlyContinue)) {
            $pageDir = $candidate2
            break
        }
        $probe = $candidate2
    }
    if (-not $pageDir) { $pageDir = $jsDir }

    $text = [System.IO.File]::ReadAllText($c.FullName)

    # href=\"target\"  ->  target
    $rx = [regex]('href=\\"([^"\\]+)\\"')
    $links = $rx.Matches($text) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

    $checked = 0
    $missing = 0
    foreach ($l in $links) {
        if ($l -match '^(?:https?:)?//' -or $l -match '^(?:mailto|javascript|data|tel):' -or $l.StartsWith('#')) { continue }
        $clean = ($l -split '[?#]')[0]
        if (-not $clean) { continue }
        $checked++
        $full = [System.IO.Path]::GetFullPath((Join-Path $pageDir $clean))
        if (-not (Test-Path -LiteralPath $full)) {
            $missing++
            if ($report.Count -lt $MaxReport) {
                $report.Add(('{0}  ->  {1}' -f $c.FullName.Substring($rootFull.Length + 1), $l))
            }
        }
    }

    $totalLinks += $checked
    $totalMissing += $missing
    '{0,-52} pageDir={1,-12} links={2,4} missing={3}' -f `
        $c.FullName.Substring($rootFull.Length + 1), (Split-Path $pageDir -Leaf), $checked, $missing
}

''
"catalog.js files : $($catalogs.Count)"
"links checked    : $totalLinks"
"missing targets  : $totalMissing"

if ($report.Count -gt 0) {
    ''
    '===== MISSING ====='
    $report | ForEach-Object { '  ' + $_ }
    exit 1
}
exit 0
