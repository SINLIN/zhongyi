<#
.SYNOPSIS
    Check EPUB chapter files that are NOT referenced by the NCX.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\sishengxinyuan'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$epub = Join-Path $Root '_source\sishengxinyuan.epub'
$work = Join-Path $env:TEMP 'sisheng_gap_check'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
[System.IO.Compression.ZipFile]::ExtractToDirectory($epub, $work)

$htmlFiles = Get-ChildItem -LiteralPath (Join-Path $work 'OEBPS\1296') -File -Filter '*.htm' |
    Sort-Object { [int]($_.BaseName) }

# files already rendered
$built = @{}
Get-ChildItem -LiteralPath $Root -File -Filter '*.html' |
    Where-Object { $_.Name -match '^\d+-(\d+)\.html$' } |
    ForEach-Object { $built[$Matches[1]] = $true }

$out = New-Object System.Collections.Generic.List[string]
$out.Add("epub chapter files : $($htmlFiles.Count)")
$out.Add("rendered pages     : $($built.Count)")
$out.Add('')

$gaps = @()
foreach ($f in $htmlFiles) {
    $n = $f.BaseName
    if ($built.ContainsKey($n)) { continue }
    $raw = [IO.File]::ReadAllText($f.FullName)
    $h1 = [regex]::Match($raw, '(?is)<h1[^>]*>(.*?)</h1>').Groups[1].Value.Trim()
    $plain = [regex]::Replace([regex]::Match($raw, '(?s)<body[^>]*>(.*?)</body>').Groups[1].Value, '(?s)<[^>]+>', ' ')
    $plain = ([System.Net.WebUtility]::HtmlDecode($plain)) -replace '\s+', ' '
    $plain = $plain.Trim()
    # remove the boilerplate note
    $plain = $plain -replace '原始资料来源互联网，中医世家网站整理。', ''
    $plain = $plain.Trim()
    $gaps += [pscustomobject]@{ Num = [int]$n; H1 = $h1; Chars = $plain.Length; Text = $plain }
}

$out.Add("not in NCX : $($gaps.Count)")
$out.Add('')
foreach ($g in $gaps) {
    $out.Add(('  {0,4}.htm  h1=[{1}]  bodyChars={2}' -f $g.Num, $g.H1, $g.Chars))
    if ($g.Chars -gt 0) { $out.Add('        ' + $g.Text.Substring(0, [Math]::Min(140, $g.Text.Length))) }
}

Remove-Item -LiteralPath $work -Recurse -Force

$f2 = Join-Path $env:TEMP 'sisheng-gaps.txt'
$out | Set-Content -Path $f2 -Encoding UTF8
Get-Content $f2 -Encoding UTF8
