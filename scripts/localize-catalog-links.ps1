<#
.SYNOPSIS
    Point the 65 formerly-remote chapter links back at the newly rebuilt local files.

.DESCRIPTION
    catalog.js and index.html still carry absolute links such as
        https://zysjonline.com/lilunshuji/yixuezhongzhongcanxilu/513-52-6.html
    for the chapters that used to be missing. Now that those files exist locally,
    rewrite every such link to the plain file name.

    Only links whose target file exists on disk are rewritten; anything else is
    left untouched and reported.

    Dry-run by default; pass -Apply to write.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$utf8Bom = [System.Text.UTF8Encoding]::new($true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)

function Read-Text([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        return @{ Text = $utf8Strict.GetString($b, 3, $b.Length - 3); Bom = $true }
    }
    return @{ Text = $utf8Strict.GetString($b); Bom = $false }
}

function Write-Text([string]$path, [string]$text, [bool]$bom) {
    [System.IO.File]::WriteAllText($path, $text, $(if ($bom) { $utf8Bom } else { $utf8NoBom }))
}

# absolute chapter links that may be rewritten: two known live-site path shapes
$linkRx = New-Object System.Text.RegularExpressions.Regex(
    'https://zysjonline\.com/(?:lilunshuji/yixuezhongzhongcanxilu|books/yixuezhongzhongcanxilu(?:/\d+)?)/([A-Za-z0-9_\-.]+\.html)')

$script:rewritten = 0
$script:left = New-Object System.Collections.Generic.List[string]

function Convert-Links([string]$text) {
    return $linkRx.Replace($text, {
            param($m)
            $name = $m.Groups[1].Value
            if (Test-Path -LiteralPath (Join-Path $Root $name)) {
                $script:rewritten++
                return $name
            }
            $script:left.Add($name)
            return $m.Value
        })
}

$targets = @(
    @{ Path = (Join-Path $Root 'static\js\catalog.js'); Label = 'static/js/catalog.js' },
    @{ Path = (Join-Path $Root 'index.html'); Label = 'index.html' }
)

$results = @()
foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t.Path)) { continue }
    $before = $script:rewritten
    $data = Read-Text $t.Path
    $orig = $data.Text
    $new = Convert-Links $orig
    $changed = ($new -ne $orig)
    if ($changed -and $Apply) { Write-Text $t.Path $new $data.Bom }
    $results += [pscustomobject]@{
        File      = $t.Label
        Changed   = $changed
        Rewritten = ($script:rewritten - $before)
        BytesOld  = [System.Text.Encoding]::UTF8.GetByteCount($orig)
        BytesNew  = [System.Text.Encoding]::UTF8.GetByteCount($new)
    }
}

'===== LOCALIZE SIDEBAR LINKS ====='
"mode            : $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' })"
"links rewritten : $($script:rewritten)"
''
$results | ForEach-Object {
    '{0,-24} changed={1,-6} rewritten={2,3}  {3:N0} -> {4:N0} bytes' -f $_.File, $_.Changed, $_.Rewritten, $_.BytesOld, $_.BytesNew
}

if ($script:left.Count -gt 0) {
    ''
    "===== LEFT AS REMOTE ($($script:left.Count)) ====="
    $script:left | Select-Object -Unique | ForEach-Object { '  ' + $_ }
}
