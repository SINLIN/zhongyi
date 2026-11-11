<#
.SYNOPSIS
    Normalize text file encoding to UTF-8 (no BOM) and line endings to LF.

.DESCRIPTION
    - Transcodes non-UTF-8 text (GBK/ANSI) to UTF-8
    - Strips UTF-8 BOM from web assets
    - Converts CRLF / CR to LF
    - Normalizes HTML <meta charset> and CSS @charset values to utf-8
    - Keeps BOM for *.ps1 (Windows PowerShell 5.1 requires it for non-ASCII)
    - Skips binaries by extension, NUL-byte sniffing and *.z (gzip) files

    Dry-run by default. Pass -Apply to write.
#>
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$binaryExt = @(
    '.z', '.zip', '.gz', '.7z', '.rar',
    '.png', '.jpg', '.jpeg', '.gif', '.ico', '.bmp', '.tif', '.tiff', '.webp', '.avif',
    '.woff', '.woff2', '.ttf', '.eot', '.otf',
    '.pdf', '.exe', '.dll'
)
# Windows PowerShell 5.1 decodes BOM-less UTF-8 as ANSI -> keep BOM for scripts
$bomExt = @('.ps1')
# files where <meta charset> / @charset may be normalized
$markupExt = @('.html', '.htm', '.xhtml', '.svg', '.xml', '.css')

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$utf8Bom = [System.Text.UTF8Encoding]::new($true)
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$gbk = [System.Text.Encoding]::GetEncoding(936)

$rootFull = (Resolve-Path $Root).Path
$gitDir = Join-Path $rootFull '.git'

$files = Get-ChildItem -Path $rootFull -Recurse -File -Force |
    Where-Object { -not $_.FullName.StartsWith($gitDir, [StringComparison]::OrdinalIgnoreCase) }

$stat = @{
    Scanned   = 0
    Binary    = 0
    Unchanged = 0
    BOM       = 0
    EOL       = 0
    Transcoded = 0
    Charset   = 0
    Written   = 0
    Errors    = @()
}

$details = New-Object System.Collections.Generic.List[string]

foreach ($f in $files) {
    $stat.Scanned++
    $ext = $f.Extension.ToLowerInvariant()

    if ($binaryExt -contains $ext) { $stat.Binary++; continue }

    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -eq 0) { $stat.Unchanged++; continue }

    # NUL byte sniffing -> binary
    $probe = [Math]::Min(8192, $bytes.Length)
    $isBinary = $false
    for ($i = 0; $i -lt $probe; $i++) { if ($bytes[$i] -eq 0) { $isBinary = $true; break } }
    if ($isBinary) { $stat.Binary++; continue }

    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $offset = if ($hasBom) { 3 } else { 0 }

    $transcoded = $false
    $text = $null
    try {
        $text = $utf8Strict.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        $text = $gbk.GetString($bytes)
        $transcoded = $true
    }

    $orig = $text

    # 1) line endings -> LF
    if ($text.IndexOf("`r") -ge 0) {
        $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    }

    $eolTouched = ($text -ne $orig)
    $beforeCharset = $text

    # 2) charset declarations -> utf-8 (markup/stylesheet only, never source code)
    if ($markupExt -contains $ext) {
        $text = [regex]::Replace($text, '(?is)<meta\b[^>]*>', {
                param($m)
                return [regex]::Replace($m.Value, '(?i)(charset\s*=\s*)(["'']?)([A-Za-z0-9_\-]+)',
                    { param($x) $x.Groups[1].Value + $x.Groups[2].Value + 'utf-8' })
            })
        $text = [regex]::Replace($text, '(?i)(@charset\s+["''])[^"'']*(["''])', '$1utf-8$2')
    }

    $charsetTouched = ($text -ne $beforeCharset)

    # 3) BOM decision
    $wantBom = ($bomExt -contains $ext)
    $bomChange = ($hasBom -ne $wantBom)

    $changed = $transcoded -or $bomChange -or $charsetTouched -or $eolTouched
    if (-not $changed) { $stat.Unchanged++; continue }

    if ($hasBom -and -not $wantBom) { $stat.BOM++ }
    if ($transcoded) { $stat.Transcoded++ }
    if ($charsetTouched) { $stat.Charset++ }
    if ($eolTouched) { $stat.EOL++ }

    $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\')
    $flags = @()
    if ($hasBom -and -not $wantBom) { $flags += 'stripBOM' }
    if (-not $hasBom -and $wantBom) { $flags += 'addBOM' }
    if ($transcoded) { $flags += 'GBK->UTF8' }
    if ($charsetTouched) { $flags += 'charset' }
    if ($eolTouched) { $flags += 'EOL->LF' }
    $details.Add(('{0,-62} {1}' -f $rel, ($flags -join ',')))

    if ($Apply) {
        try {
            $enc = if ($wantBom) { $utf8Bom } else { $utf8NoBom }
            [System.IO.File]::WriteAllText($f.FullName, $text, $enc)
            $stat.Written++
        }
        catch {
            $stat.Errors += "$rel : $($_.Exception.Message)"
        }
    }
}

'===== NORMALIZE ====='
"mode            : $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' })"
"root            : $rootFull"
"scanned         : $($stat.Scanned)"
"binary skipped  : $($stat.Binary)"
"already clean   : $($stat.Unchanged)"
"BOM stripped    : $($stat.BOM)"
"GBK transcoded  : $($stat.Transcoded)"
"charset fixed   : $($stat.Charset)"
"EOL converted   : $($stat.EOL)"
"files written   : $($stat.Written)"

if ($stat.Errors.Count -gt 0) {
    ''
    '===== ERRORS ====='
    $stat.Errors | ForEach-Object { $_ }
}

if ($details.Count -gt 0 -and $details.Count -le 60) {
    ''
    '===== DETAIL ====='
    $details | ForEach-Object { $_ }
}
elseif ($details.Count -gt 60) {
    ''
    "===== DETAIL: $($details.Count) files (showing first 40) ====="
    $details | Select-Object -First 40 | ForEach-Object { $_ }
}
