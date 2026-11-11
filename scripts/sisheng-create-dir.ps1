<#
.SYNOPSIS
    Create the sishengxinyuan archive directory skeleton by copying static assets
    from yixuezhongzhongcanxilu (same layout).
#>
param(
    [string]$Src = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu',
    [string]$Dst = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\sishengxinyuan',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$out = New-Object System.Collections.Generic.List[string]

$out.Add("source : $Src")
$out.Add("target : $Dst")
$out.Add('')

# directories to mirror
$dirs = @('static', 'static\css', 'static\js', 'static\picture', 'static\image')
foreach ($d in $dirs) {
    $p = Join-Path $Dst $d
    $out.Add(('{0,-24} {1}' -f $d, $(if (Test-Path -LiteralPath $p) { 'exists' } else { 'create' })))
    if ($Apply -and -not (Test-Path -LiteralPath $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}

$out.Add('')
$out.Add('--- static files to copy ---')

$staticSrc = Join-Path $Src 'static'
$files = Get-ChildItem -LiteralPath $staticSrc -Recurse -File -ErrorAction SilentlyContinue
foreach ($f in $files) {
    $rel = $f.FullName.Substring($staticSrc.Length).TrimStart('\')
    # catalog.js is book-specific, regenerate later
    $skip = ($f.Name -eq 'catalog.js')
    $out.Add(('{0,-34} {1,9:N0} bytes  {2}' -f $rel, $f.Length, $(if ($skip) { 'skip (book-specific)' } else { 'copy' })))
    if ($Apply -and -not $skip) {
        $t = Join-Path $Dst ('static\' + $rel)
        $td = Split-Path $t -Parent
        if (-not (Test-Path -LiteralPath $td)) { New-Item -ItemType Directory -Path $td -Force | Out-Null }
        Copy-Item -LiteralPath $f.FullName -Destination $t -Force
    }
}

$out.Add('')
$out.Add("static files: $($files.Count)")

$f2 = Join-Path $env:TEMP 'mk-dir.txt'
$out | Set-Content -Path $f2 -Encoding UTF8
Get-Content $f2 -Encoding UTF8
