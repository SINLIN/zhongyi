<#
.SYNOPSIS
    Rebuild locally-missing chapter pages from the full-book page (quanben.html).

.DESCRIPTION
    The archive is missing 65 chapter files whose sidebar links were rewritten to
    the live site. Those chapters still exist verbatim inside quanben.html, which
    ships the same markup as the per-chapter pages.

    For every chapter in _chapters.json marked Remote:
        * locate <div class="section" id="ciNNNNN"> ... </div> inside quanben.html
        * convert <h3 class="title">T</h3> into <h1 id="ciNNNNN">T</h1>
        * wrap the remaining body in <div id="content">
        * fill in <title>, keywords, description, breadcrumb category, prev/next
        * write <file name>.html using a real existing chapter page as template

    Dry-run by default; pass -Apply to write files.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu',

    # existing chapter page used purely as a skeleton
    [string]$Template = '513-52-5.html',

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

# ---------------------------------------------------------------- inputs
$chapters = Get-Content (Join-Path $Root '_chapters.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$tplData = Read-Text (Join-Path $Root $Template)
$tpl = $tplData.Text

$qb = Read-Text (Join-Path $Root 'quanben.html')
$qbText = $qb.Text

$total = $chapters.Count
$remote = @($chapters | Where-Object { $_.Remote })
$bomLabel = if ($tplData.Bom) { 'BOM' } else { 'no BOM' }
"template            : $Template ($bomLabel, $($tpl.Length) chars)"
"chapters total      : $total"
"remote (missing)    : $($remote.Count)"
''

# ---------------------------------------------------------------- template anchors
$titleRx = New-Object System.Text.RegularExpressions.Regex('(?s)<title>.*?</title>')
$kwRx = New-Object System.Text.RegularExpressions.Regex('<meta name="keywords" content="[^"]*">')
$descRx = New-Object System.Text.RegularExpressions.Regex('<meta name="description" content="[^"]*">')
$h1Rx = New-Object System.Text.RegularExpressions.Regex('<h1 id="ci\d+">[^<]*</h1>')
$contentRx = New-Object System.Text.RegularExpressions.Regex('(?s)<div id="content">.*?</div>\s*\r?\n(?=<ul id="nav-prev-next">)')
$crumbRx = New-Object System.Text.RegularExpressions.Regex('<li><span>[^<]*</span></li>')

foreach ($rx in @($titleRx, $kwRx, $descRx, $h1Rx, $contentRx, $crumbRx)) {
    if (-not $rx.IsMatch($tpl)) { throw "template anchor not found: $($rx.ToString())" }
}

# <ul id="nav-prev-next"> nests <ul> inside <li>, so a non-greedy regex would stop
# at the first inner </ul>. Walk the markup and match the closing tag by depth.
function Get-NavBounds([string]$text) {
    $head = '<ul id="nav-prev-next">'
    $start = $text.IndexOf($head, [StringComparison]::Ordinal)
    if ($start -lt 0) { return $null }
    $depth = 0
    $i = $start
    while ($i -lt $text.Length) {
        $open = $text.IndexOf('<ul', $i, [StringComparison]::Ordinal)
        $close = $text.IndexOf('</ul>', $i, [StringComparison]::Ordinal)
        if ($close -lt 0) { return $null }
        if ($open -ge 0 -and $open -lt $close) {
            $depth++
            $i = $open + 3
        }
        else {
            $depth--
            $i = $close + 5
            if ($depth -eq 0) {
                return @{ Start = $start; Length = $i - $start }
            }
        }
    }
    return $null
}

$navBounds = Get-NavBounds $tpl
if (-not $navBounds) { throw 'nav-prev-next block not found in template' }

function Get-SectionMarkup([string]$text, [string]$ci) {
    $open = '<div class="section" id="ci' + $ci + '">'
    $start = $text.IndexOf($open)
    if ($start -lt 0) { return $null }
    $next = [regex]::Match($text.Substring($start + $open.Length), '<div class="section" id="ci\d+">')
    $end = if ($next.Success) { $start + $open.Length + $next.Index } else { -1 }
    if ($end -lt 0) {
        $tail = $text.IndexOf('</div>', $start)
        $end = if ($tail -gt 0) { $tail + 6 } else { $text.Length }
    }
    return $text.Substring($start, $end - $start)
}

function ConvertTo-Plain([string]$html) {
    $t = $html -replace '(?s)<[^>]+>', ' '
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Get-Desc([string]$plain, [int]$max = 160) {
    if ($plain.Length -le $max) { return $plain }
    return $plain.Substring(0, $max) + '……'
}

function New-NavLink($item, [string]$rel) {
    if (-not $item) { return '' }
    return '<li class="' + $rel + '"><ul><li><sapan>' + $item.Category + '</sapan></li><li><a rel="' + $rel +
           '" href="' + $item.File + '" title="' + $item.Title + '">' + $item.Title + '</a></li></ul></li>'
}

$made = 0
$skipped = New-Object System.Collections.Generic.List[string]
$report = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $total; $i++) {
    $ch = $chapters[$i]
    if (-not $ch.Remote) { continue }

    $target = Join-Path $Root $ch.File
    if (Test-Path -LiteralPath $target) {
        $skipped.Add("$($ch.File) (already exists)")
        continue
    }

    $sec = Get-SectionMarkup $qbText $ch.Si
    if (-not $sec) {
        $skipped.Add("$($ch.File) (ci$($ch.Si) not found in quanben)")
        continue
    }

    # split section into heading + body
    $h3 = [regex]::Match($sec, '(?s)<h3 class="title">(.*?)</h3>')
    if (-not $h3.Success) {
        $skipped.Add("$($ch.File) (no <h3 class=title> in section)")
        continue
    }
    $heading = $h3.Groups[1].Value.Trim()
    $bodyHtml = $sec.Substring($h3.Index + $h3.Length)
    $bodyHtml = $bodyHtml -replace '(?s)^\s*', ''
    $bodyHtml = $bodyHtml -replace '(?s)\s*</div>\s*$', ''
    $bodyHtml = ($bodyHtml -split "`n" | ForEach-Object { $_.TrimEnd() }) -join "`n"
    $bodyHtml = $bodyHtml.Trim()

    $plain = ConvertTo-Plain $bodyHtml
    $desc = Get-Desc $plain

    # prev / next within the ordered chapter list
    $prev = if ($i -gt 0) { $chapters[$i - 1] } else { $null }
    $next = if ($i -lt $total - 1) { $chapters[$i + 1] } else { $null }

    $nav = "<ul id=`"nav-prev-next`">`n" + (New-NavLink $prev 'prev') + "`n" + (New-NavLink $next 'next') + "`n</ul>"

    # ---- build page
    $page = $tpl
    $page = $titleRx.Replace($page, '<title>' + $heading + ' - 《医学衷中参西录》 - 中医世家</title>', 1)
    $page = $kwRx.Replace($page, '<meta name="keywords" content="' + $heading + ',《医学衷中参西录》">', 1)
    $page = $descRx.Replace($page, '<meta name="description" content="中医书籍《医学衷中参西录》“' + $heading + '”：' + $desc + '">', 1)
    $page = $crumbRx.Replace($page, '<li><span>' + $ch.Category + '</span></li>', 1)
    $page = $h1Rx.Replace($page, '<h1 id="ci' + $ch.Si + '">' + $heading + '</h1>', 1)
    $page = $contentRx.Replace($page, '<div id="content">' + "`n" + $bodyHtml + "`n</div>" + "`n", 1)

    # recompute bounds: the content replacement above changed the text length
    $navBounds = Get-NavBounds $page
    if (-not $navBounds) { throw "nav-prev-next block not found after content rewrite ($($ch.File))" }
    $page = $page.Remove($navBounds.Start, $navBounds.Length).Insert($navBounds.Start, $nav)

    if ($Apply) { Write-Text $target $page $tplData.Bom }
    $made++
    $report.Add(('{0,-16} ci{1} {2,6:N1}KB  {3}' -f $ch.File, $ch.Si, ($page.Length / 1KB), $heading))
}

'===== REBUILD MISSING CHAPTERS ====='
"mode            : $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' })"
"root            : $Root"
"pages built     : $made"
"skipped         : $($skipped.Count)"
''
if ($report.Count -le 70) { $report | ForEach-Object { $_ } }
else { $report | Select-Object -First 10 | ForEach-Object { $_ }; "  ... ($($report.Count) total)" }

if ($skipped.Count -gt 0) {
    ''
    '===== SKIPPED ====='
    $skipped | ForEach-Object { '  ' + $_ }
}
