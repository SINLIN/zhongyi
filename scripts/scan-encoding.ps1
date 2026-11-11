<#
.SYNOPSIS
    Scan text files for encoding / BOM / line-ending problems.

.DESCRIPTION
    For every text file under -Root it reports:
      - whether the byte stream is valid UTF-8
      - BOM presence
      - line-ending style (CRLF / LF / mixed / none)
      - declared charset in HTML <meta> / CSS @charset (if any)
      - a sample of the decoded text so mojibake is visible

    Exit code is 0; findings are printed as a table.
#>
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path,
    [string[]]$Include = @('*.html', '*.htm', '*.css', '*.js', '*.txt', '*.md', '*.json', '*.xml')
)

$ErrorActionPreference = 'Stop'
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$gbk = [System.Text.Encoding]::GetEncoding(936)

$files = foreach ($pat in $Include) {
    Get-ChildItem -Path $Root -Recurse -File -Filter $pat -ErrorAction SilentlyContinue
}
$files = $files | Sort-Object FullName -Unique

$rows = foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -eq 0) { continue }

    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $offset = if ($hasBom) { 3 } else { 0 }

    $isUtf8 = $true
    $text = $null
    try { $text = $utf8Strict.GetString($bytes, $offset, $bytes.Length - $offset) }
    catch { $isUtf8 = $false }

    if (-not $isUtf8) { $text = $gbk.GetString($bytes) }

    # line endings
    $crlf = 0; $lf = 0
    for ($i = 0; $i -lt $text.Length; $i++) {
        if ($text[$i] -eq "`n") {
            if ($i -gt 0 -and $text[$i - 1] -eq "`r") { $crlf++ } else { $lf++ }
        }
    }
    $style = if ($crlf -gt 0 -and $lf -gt 0) { 'MIXED' }
             elseif ($crlf -gt 0) { 'CRLF' }
             elseif ($lf -gt 0) { 'LF' }
             else { 'none' }

    # declared charset
    $decl = ''
    $m = [regex]::Match($text, '(?i)<meta[^>]+charset\s*=\s*["'']?([\w\-]+)')
    if ($m.Success) { $decl = 'meta:' + $m.Groups[1].Value }
    else {
        $m = [regex]::Match($text, '(?i)@charset\s+["'']([\w\-]+)')
        if ($m.Success) { $decl = 'css:' + $m.Groups[1].Value }
    }

    # mojibake heuristic: typical GBK-as-UTF8 / UTF8-as-GBK signature chars
    $moji = 0
    foreach ($ch in @([char]0xFFFD, [char]0xE5, [char]0x00)) { }
    $moji = ([regex]::Matches($text, '[\uFFFD]')).Count
    if ($text -match '[\u9510-\u952F]{2,}') { $moji += 1 }   # 锟斤拷 style
    if ($text -match '(?i)charset=gb') { }

    [pscustomobject]@{
        File    = $f.FullName.Substring((Resolve-Path $Root).Path.Length).TrimStart('\')
        Bytes   = $bytes.Length
        Valid   = if ($isUtf8) { 'UTF8' } else { 'NOT-UTF8' }
        BOM     = if ($hasBom) { 'BOM' } else { '-' }
        EOL     = $style
        Declared = $decl
        BadChar = $moji
    }
}

'===== SUMMARY ====='
"files scanned : $($rows.Count)"
"not UTF-8     : $(($rows | Where-Object { $_.Valid -ne 'UTF8' }).Count)"
"with BOM      : $(($rows | Where-Object { $_.BOM -eq 'BOM' }).Count)"
"CRLF          : $(($rows | Where-Object { $_.EOL -eq 'CRLF' }).Count)"
"LF            : $(($rows | Where-Object { $_.EOL -eq 'LF' }).Count)"
"MIXED EOL     : $(($rows | Where-Object { $_.EOL -eq 'MIXED' }).Count)"
"with U+FFFD   : $(($rows | Where-Object { $_.BadChar -gt 0 }).Count)"

''
'===== FILE LIST (non-conforming only) ====='
$rows | Where-Object { $_.Valid -ne 'UTF8' -or $_.BOM -eq 'BOM' -or $_.EOL -eq 'MIXED' -or $_.BadChar -gt 0 } |
    Sort-Object File |
    ForEach-Object { '{0,-42} {1,-9} {2,-4} {3,-6} {4,-12} bad={5}' -f $_.File, $_.Valid, $_.BOM, $_.EOL, $_.Declared, $_.BadChar }

''
'===== DECLARED CHARSET COUNTS ====='
$rows | Group-Object Declared | Sort-Object Count -Descending | ForEach-Object { '{0,-16} {1}' -f ($_.Name -replace '^$', '(none)'), $_.Count }
