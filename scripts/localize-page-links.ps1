<#
.SYNOPSIS
    Rewrite remaining absolute chapter links inside existing pages (prev/next nav etc).

.DESCRIPTION
    Rebuilt pages already point at local files. Pages that existed before the
    rebuild still carry absolute prev/next links to chapters that did not exist
    locally at the time. Now that every chapter file is present, rewrite any
    absolute link whose target existed only remotely.

    Only links whose target file exists on disk are rewritten.

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

$linkRx = New-Object System.Text.RegularExpressions.Regex(
    'https://zysjonline\.com/(?:lilunshuji/yixuezhongzhongcanxilu|books/yixuezhongzhongcanxilu(?:/\d+)?)/([A-Za-z0-9_\-.]+\.html)')

# skip files that are already linked locally
$files = Get-ChildItem -Path $Root -File -Filter *.html | Sort-Object Name

$script:total = 0
$script:left = New-Object System.Collections.Generic.List[string]

function Convert-Links([string]$text) {
    return $linkRx.Replace($text, {
            param($m)
            $name = $m.Groups[1].Value
            if (Test-Path -LiteralPath (Join-Path $Root $name)) {
                $script:total++
                return $name
            }
            $script:left.Add($name)
            return $m.Value
        })
}

$changed = 0
$details = New-Object System.Collections.Generic.List[string]

foreach ($f in $files) {
    $data = Read-Text $f.FullName
    if ($data.Text.IndexOf('zysjonline.com', [StringComparison]::Ordinal) -lt 0) { continue }
    if ($data.Text.IndexOf('/yixuezhongzhongcanxilu/', [StringComparison]::Ordinal) -lt 0) { continue }

    $before = $script:total
    $new = Convert-Links $data.Text
    if ($new -eq $data.Text) { continue }

    $changed++
    if ($Apply) { Write-Text $f.FullName $new $data.Bom }
    $details.Add(('{0,-20} rewritten={1,3}' -f $f.Name, ($script:total - $before)))
}

'===== LOCALIZE EXISTING PAGE LINKS ====='
"mode            : $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' })"
"html files      : $($files.Count)"
"pages changed   : $changed"
"links rewritten : $($script:total)"
''
if ($details.Count -le 20) { $details | ForEach-Object { '  ' + $_ } }
else { $details | Select-Object -First 20 | ForEach-Object { '  ' + $_ }; "  ... ($($details.Count) total)" }

if ($script:left.Count -gt 0) {
    ''
    "===== LEFT AS REMOTE ($($script:left.Count)) ====="
    $script:left | Select-Object -Unique | ForEach-Object { '  ' + $_ }
}
