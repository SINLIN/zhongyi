<#
.SYNOPSIS
    Batch-verify the rebuilt chapter pages against their quanben.html source.

.DESCRIPTION
    For every rebuilt chapter (those flagged Remote in _chapters.json) this checks
        * <ul id="nav-prev-next"> appears exactly once
        * the <h1 id="ciNNNNN"> anchor matches the expected si number
        * the body paragraph text equals the corresponding section in quanben.html
        * prev/next links resolve to existing local files
    Reports any mismatch.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu'
)

$ErrorActionPreference = 'Stop'

$chs = Get-Content (Join-Path $Root '_chapters.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$remote = @($chs | Where-Object { $_.Remote })
$qb = [IO.File]::ReadAllText((Join-Path $Root 'quanben.html'))

function Normalize([string]$s) {
    $t = $s -replace '(?s)<[^>]+>', ''
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = $t -replace '\s+', ''
    return $t.Trim()
}

function Get-Section([string]$ci) {
    $open = '<div class="section" id="ci' + $ci + '">'
    $start = $qb.IndexOf($open)
    if ($start -lt 0) { return $null }
    $rest = $qb.Substring($start + $open.Length)
    $next = [regex]::Match($rest, '<div class="section" id="ci\d+">')
    $len = if ($next.Success) { $next.Index } else { $rest.IndexOf('</div>') }
    if ($len -lt 0) { $len = $rest.Length }
    return $rest.Substring(0, $len)
}

$ok = 0
$problems = New-Object System.Collections.Generic.List[string]

foreach ($c in $remote) {
    $path = Join-Path $Root $c.File
    if (-not (Test-Path -LiteralPath $path)) {
        $problems.Add("$($c.File) : FILE MISSING")
        continue
    }
    $page = [IO.File]::ReadAllText($path)
    $issues = New-Object System.Collections.Generic.List[string]

    # 1. single nav block
    $navCount = ([regex]::Matches($page, 'id="nav-prev-next"')).Count
    if ($navCount -ne 1) { $issues.Add("nav blocks = $navCount") }

    # 2. h1 anchor
    $h1 = [regex]::Match($page, '<h1 id="ci(\d+)">')
    if (-not $h1.Success) { $issues.Add('h1 anchor missing') }
    elseif ($h1.Groups[1].Value -ne $c.Si) { $issues.Add("h1 ci$(($h1.Groups[1].Value)) != si$($c.Si)") }

    # 3. content equals quanben section
    $srcSection = Get-Section $c.Si
    if (-not $srcSection) { $issues.Add('section not found in quanben') }
    else {
        $srcMatch = [regex]::Match($srcSection, '(?s)<h3 class="title">(.*?)</h3>')
        $srcBody = if ($srcMatch.Success) { $srcSection.Substring($srcMatch.Index + $srcMatch.Length) } else { $srcSection }
        $srcNorm = Normalize $srcBody

        $cMatch = [regex]::Match($page, '(?s)<div id="content">(.*?)</div>\s*<ul id="nav-prev-next">')
        $dstNorm = if ($cMatch.Success) { Normalize $cMatch.Groups[1].Value } else { '' }

        if ($srcNorm -ne $dstNorm) {
            $issues.Add("body differs (src $($srcNorm.Length) vs dst $($dstNorm.Length) chars)")
        }
    }

    # 4. prev / next targets exist
    foreach ($m in [regex]::Matches($page, '<a rel="(prev|next)" href="([^"]+)"')) {
        $href = $m.Groups[2].Value
        if ($href -match '^https?://') { $issues.Add("$($m.Groups[1].Value) still remote"); continue }
        if (-not (Test-Path -LiteralPath (Join-Path $Root $href))) { $issues.Add("$($m.Groups[1].Value) -> $href missing") }
    }

    if ($issues.Count -eq 0) { $ok++ }
    else { $problems.Add("$($c.File) : " + ($issues -join '; ')) }
}

'===== VERIFY REBUILT PAGES ====='
"rebuilt pages : $($remote.Count)"
"passed        : $ok"
"failed        : $($problems.Count)"
''
if ($problems.Count -gt 0) {
    '===== PROBLEMS ====='
    $problems | ForEach-Object { '  ' + $_ }
    exit 1
}
'All rebuilt pages match quanben.html content and have valid local navigation.'
exit 0
