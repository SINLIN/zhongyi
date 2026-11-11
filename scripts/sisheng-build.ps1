<#
.SYNOPSIS
    Build the sishengxinyuan archive pages from the EPUB, matching the
    yixuezhongzhongcanxilu layout exactly.

.DESCRIPTION
    Reads _toc.json (produced by epub-parse-ncx.ps1) and the unpacked EPUB, then:
      1. builds an ordered list of unique chapter pages
      2. extracts each chapter body and wraps it in the local page template
      3. writes <book>/index.html with a nested catalog tree
      4. writes <book>/static/js/catalog.js (shared sidebar)
      5. writes quanben.html-free layout (this book has no full-book page)

    Dry-run by default; pass -Apply to write.
#>
param(
    [string]$WorkDir = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\_tmp_epub',
    [string]$Root    = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\sishengxinyuan',
    [string]$Template = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu\513-52-6.html',
    [string]$IndexTemplate = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu\index.html',

    [string]$BookTitle = '四圣心源',
    [string]$Author    = '黄元御',
    [string]$Dynasty   = '清',
    [string]$IdPrefix  = '1296',

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

function To-JsString([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '\') { [void]$sb.Append('\\') }
        elseif ($ch -eq '"') { [void]$sb.Append('\"') }
        elseif ($ch -eq "`r") { [void]$sb.Append('\r') }
        elseif ($ch -eq "`n") { [void]$sb.Append('\n') }
        elseif ($ch -eq "`t") { [void]$sb.Append('\t') }
        elseif ([int]$ch -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) }
        else { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# ------------------------------------------------------------------ 1. TOC
$toc = Get-Content (Join-Path $Root '_toc.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# file name for an epub href:  1296/13.htm  ->  1296-13.html
function Get-FileName([string]$href) {
    $m = [regex]::Match($href, '(\d+)\.html?$')
    if ($m.Success) { return $IdPrefix + '-' + $m.Groups[1].Value + '.html' }
    return $null
}
function Get-SourcePath([string]$href) {
    return (Join-Path $WorkDir ('OEBPS\' + ($href -replace '/', '\')))
}

# ordered unique page list, with volume context
$pages = New-Object System.Collections.Generic.List[object]
$seen = @{}
$curVolume = ''
foreach ($row in $toc) {
    if ($row.Depth -eq 1) { $curVolume = $row.Title }
    $file = Get-FileName $row.Href
    if (-not $file) { continue }
    if ($seen.ContainsKey($file)) { continue }
    $seen[$file] = $true
    $pages.Add([pscustomobject]@{
            File    = $file
            Title   = $row.Title
            Volume  = $curVolume
            Order   = $row.Order
            Href    = $row.Href
        })
}

"toc entries    : $($toc.Count)"
"unique pages   : $($pages.Count)"

# ------------------------------------------------------------------ 2. extraction
function Get-ChapterBody([string]$raw) {
    $m = [regex]::Match($raw, '(?s)<body[^>]*>(.*?)</body>')
    if (-not $m.Success) { return '' }
    $body = $m.Groups[1].Value

    # drop everything up to and including the </center> that closes the <h1> block
    $i = $body.IndexOf('</center>', [StringComparison]::Ordinal)
    if ($i -ge 0) { $body = $body.Substring($i + 9) }

    # stop before the closing of the outer layout table cell
    $j = $body.IndexOf('</td></tr></table>', [StringComparison]::Ordinal)
    if ($j -ge 0) { $body = $body.Substring(0, $j) }

    # strip the source note
    $body = [regex]::Replace($body, '(?is)<span class="font_gray">.*?</span>', '')
    $body = [regex]::Replace($body, '(?i)<hr\s*/?>', '')
    $body = [regex]::Replace($body, '(?is)<table[^>]*>|</table>', '')
    $body = [regex]::Replace($body, '(?is)<tr[^>]*>|</tr>', '')
    $body = [regex]::Replace($body, '(?is)<td[^>]*>|</td>', '')
    $body = [regex]::Replace($body, '(?is)<(?:center|tbody)>|</(?:center|tbody)>', '')

    # tidy whitespace
    $body = $body -replace "`r`n", "`n"
    $body = [regex]::Replace($body, '[ \t]+', ' ')
    $body = [regex]::Replace($body, '\n{3,}', "`n`n")
    $body = $body.Trim()
    return $body
}

function Split-Paragraphs([string]$html) {
    $t = $html -replace '</p>', "</p>`n"
    $t = $t -replace '</h1>', "</h1>`n"
    $t = $t -replace '</h2>', "</h2>`n"
    $t = $t -replace '</h3>', "</h3>`n"
    $t = $t -replace '</blockquote>', "</blockquote>`n"
    $lines = $t -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return ($lines -join "`n")
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

# ------------------------------------------------------------------ 3. template anchors
$tplData = Read-Text $Template
$tplBase = $tplData.Text

$titleRx = New-Object System.Text.RegularExpressions.Regex('(?s)<title>.*?</title>')
$kwRx = New-Object System.Text.RegularExpressions.Regex('<meta name="keywords" content="[^"]*">')
$descRx = New-Object System.Text.RegularExpressions.Regex('<meta name="description" content="[^"]*">')
$h1Rx = New-Object System.Text.RegularExpressions.Regex('<h1 id="ci\d+">[^<]*</h1>')
$crumbRx = New-Object System.Text.RegularExpressions.Regex('<li><span>[^<]*</span></li>')
$gatherRx = New-Object System.Text.RegularExpressions.Regex('<a id="gather-content"[^>]*>[^<]*</a>')
$contentRx = New-Object System.Text.RegularExpressions.Regex('(?s)<div id="content">.*?</div>\s*\n(?=<ul id="nav-prev-next">)')

foreach ($rx in @($titleRx, $kwRx, $descRx, $h1Rx, $crumbRx, $contentRx)) {
    if (-not $rx.IsMatch($tplBase)) { throw "template anchor missing: $($rx.ToString())" }
}

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
        if ($open -ge 0 -and $open -lt $close) { $depth++; $i = $open + 3 }
        else { $depth--; $i = $close + 5; if ($depth -eq 0) { return @{ Start = $start; Length = $i - $start } } }
    }
    return $null
}

function New-NavLink($item, [string]$rel) {
    if (-not $item) { return '' }
    return '<li class="' + $rel + '"><ul><li><sapan>' + $item.Volume + '</sapan></li><li><a rel="' + $rel +
           '" href="' + $item.File + '" title="' + $item.Title + '">' + $item.Title + '</a></li></ul></li>'
}

# ------------------------------------------------------------------ 4. build pages
$report = New-Object System.Collections.Generic.List[string]
$problems = New-Object System.Collections.Generic.List[string]
$total = $pages.Count
$made = 0

for ($i = 0; $i -lt $total; $i++) {
    $p = $pages[$i]
    $src = Get-SourcePath $p.Href
    if (-not (Test-Path -LiteralPath $src)) {
        $problems.Add("$($p.File) : source missing ($($p.Href))")
        continue
    }
    $rawData = Read-Text $src
    $raw = $rawData.Text

    $h1m = [regex]::Match($raw, '(?is)<h1[^>]*>(.*?)</h1>')
    $heading = if ($h1m.Success) { (ConvertTo-Plain $h1m.Groups[1].Value) } else { $p.Title }
    if (-not $heading) { $heading = $p.Title }

    $bodyHtml = Get-ChapterBody $raw
    $bodyHtml = Split-Paragraphs $bodyHtml
    if (-not $bodyHtml) { $problems.Add("$($p.File) : empty body") }

    $plain = ConvertTo-Plain $bodyHtml
    $desc = Get-Desc $plain

    $prev = if ($i -gt 0) { $pages[$i - 1] } else { $null }
    $next = if ($i -lt $total - 1) { $pages[$i + 1] } else { $null }
    $nav = "<ul id=`"nav-prev-next`">`n" + (New-NavLink $prev 'prev') + "`n" + (New-NavLink $next 'next') + "`n</ul>"

    $page = $tplBase
    # swap the book name carried over from the template (breadcrumb link, titles, etc.)
    $page = $page.Replace('医学衷中参西录', $BookTitle)
    # this book ships no index1/index2 pages: point the site-level breadcrumb links
    # back at the archive navigation page instead of leaving 404s
    $page = $page.Replace('href="index1.html"', 'href="../index.html"')
    $page = $page.Replace('href="index2.html"', 'href="../index.html"')
    $page = $titleRx.Replace($page, '<title>' + $heading + ' - 《' + $BookTitle + '》 - 中医世家</title>', 1)
    $page = $kwRx.Replace($page, '<meta name="keywords" content="' + $heading + ',《' + $BookTitle + '》">', 1)
    $page = $descRx.Replace($page, '<meta name="description" content="中医书籍《' + $BookTitle + '》“' + $heading + '”：' + $desc + '">', 1)
    $page = $crumbRx.Replace($page, '<li><span>' + $p.Volume + '</span></li>', 1)
    $page = $h1Rx.Replace($page, '<h1 id="ci' + $p.Order + '">' + $heading + '</h1>', 1)
    # this book has no full-book page: plain return-to-index link (no gather-content id,
    # otherwise css.css would append a misleading "（不分页）" suffix)
    $page = $gatherRx.Replace($page, '<a href="index.html" title="返回目录《' + $BookTitle + '》">返回目录</a>', 1)

    $page = $contentRx.Replace($page, '<div id="content">' + "`n" + $bodyHtml + "`n</div>" + "`n", 1)
    $nb = Get-NavBounds $page
    if (-not $nb) { $problems.Add("$($p.File) : nav block lost"); continue }
    $page = $page.Remove($nb.Start, $nb.Length).Insert($nb.Start, $nav)

    if ($Apply) { Write-Text (Join-Path $Root $p.File) $page $tplData.Bom }
    $made++
    $report.Add(('{0,-16} {1,6:N1}KB  {2}' -f $p.File, ($page.Length / 1KB), $heading))
}

''
'===== BUILD PAGES ====='
"mode           : $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' })"
"pages built    : $made / $total"
"problems       : $($problems.Count)"
''
if ($report.Count -le 12) { $report | ForEach-Object { '  ' + $_ } }
else {
    $report | Select-Object -First 6 | ForEach-Object { '  ' + $_ }
    '  ...'
    $report | Select-Object -Last 4 | ForEach-Object { '  ' + $_ }
}
if ($problems.Count -gt 0) {
    ''
    '===== PROBLEMS ====='
    $problems | Select-Object -First 20 | ForEach-Object { '  ' + $_ }
}

# ------------------------------------------------------------------ 5. catalog tree
function Get-DescendantFiles($node) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($c in $node.Children) {
        if ($c.File) { [void]$set.Add($c.File) }
        foreach ($f in (Get-DescendantFiles $c)) { [void]$set.Add($f) }
    }
    return $set
}

function New-TocHtml($node, [int]$depth) {
    $sb = New-Object System.Text.StringBuilder
    $hasKids = ($node.Children.Count -gt 0)

    if ($hasKids) {
        [void]$sb.Append('<li><span>' + $node.Title + '</span>' + "`n" + '<ul>' + "`n")

        # a volume node may own its own page; expose it as the first child link
        if ($node.File) {
            $desc = Get-DescendantFiles $node
            if (-not $desc.Contains($node.File)) {
                [void]$sb.Append('<li><a href="' + $node.File + '" title="' + $node.Title + '">' + $node.Title + '</a></li>' + "`n")
            }
        }

        foreach ($c in $node.Children) { [void]$sb.Append((New-TocHtml $c ($depth + 1)) + "`n") }
        [void]$sb.Append('</ul>' + "`n" + '</li>')
    }
    elseif ($node.File) {
        [void]$sb.Append('<li><a href="' + $node.File + '" title="' + $node.Title + '">' + $node.Title + '</a></li>')
    }
    return $sb.ToString()
}

# construct a tree from the depth-tagged TOC
$roots = New-Object System.Collections.Generic.List[object]
$stack = New-Object System.Collections.Generic.List[object]
foreach ($row in $toc) {
    $file = Get-FileName $row.Href
    $node = [pscustomobject]@{
        Title    = $row.Title
        File     = $file
        Depth    = $row.Depth
        Children = New-Object System.Collections.Generic.List[object]
    }
    while ($stack.Count -ge $row.Depth) { $stack.RemoveAt($stack.Count - 1) }
    if ($stack.Count -eq 0) { $roots.Add($node) }
    else { $stack[$stack.Count - 1].Children.Add($node) }
    $stack.Add($node)
}

$tocLines = New-Object System.Collections.Generic.List[string]
[void]$tocLines.Add('<li><span>作者：' + $Author + '  朝代：' + $Dynasty + '</span></li>')
foreach ($r in $roots) { [void]$tocLines.Add((New-TocHtml $r 1)) }
$tocHtml = ($tocLines -join "`n")

$catalogInner = '<div id="sidebar"><div class="section"><h2 class="title"><a href="index.html">《' + $BookTitle + '》</a></h2>' +
                '<ul id="guide" class="content" data-get="g">' + $tocHtml + '</ul></div></div>'

$catalogScript = '(function(){var p=document.getElementById("sidebar-ph");if(!p)return;var d=document.createElement("div");d.innerHTML=' +
    (To-JsString $catalogInner) + ';p.parentNode.replaceChild(d.firstElementChild,p);})();'

''
'===== CATALOG ====='
"root nodes     : $($roots.Count)"
"toc html chars : $($tocHtml.Length)"
"catalog.js KB  : $([math]::Round([System.Text.Encoding]::UTF8.GetByteCount($catalogScript) / 1KB, 1))"

# ------------------------------------------------------------------ 6. index.html
$idxData = Read-Text $IndexTemplate
$idx = $idxData.Text

$idxTitleRx = New-Object System.Text.RegularExpressions.Regex('(?s)<title>.*?</title>')
$idxKwRx = New-Object System.Text.RegularExpressions.Regex('<meta name="keywords" content="[^"]*">')
$idxDescRx = New-Object System.Text.RegularExpressions.Regex('<meta name="description" content="[^"]*">')
$idxH1Rx = New-Object System.Text.RegularExpressions.Regex('<h1>[^<]*</h1>')
$idxCatRx = New-Object System.Text.RegularExpressions.Regex('(?s)<div id="catalog-info">.*?</div>\s*\n<ul id="catalog-content"[^>]*>.*?</ul>\s*\n</div>')

$newCat = '<div id="catalog-info"></div>' + "`n" +
          '<ul id="catalog-content" data-m="3">' + "`n" + $tocHtml + "`n" + '</ul>' + "`n" + '</div>'

if (-not $idxCatRx.IsMatch($idx)) { throw 'index template catalog block not found' }

$idxNew = $idx
$idxNew = $idxNew.Replace('医学衷中参西录', $BookTitle)
$idxNew = $idxNew.Replace('href="index1.html"', 'href="../index.html"')
$idxNew = $idxNew.Replace('href="index2.html"', 'href="../index.html"')
$idxNew = $idxTitleRx.Replace($idxNew, '<title>《' + $BookTitle + '》 - 中医书籍 - 中医世家</title>', 1)
$idxNew = $idxKwRx.Replace($idxNew, '<meta name="keywords" content="' + $BookTitle + ',中医书籍">', 1)
$idxNew = $idxDescRx.Replace($idxNew, '<meta name="description" content="中医书籍《' + $BookTitle + '》。">', 1)
$idxNew = $idxH1Rx.Replace($idxNew, '<h1>《' + $BookTitle + '》</h1>', 1)
$idxNew = $idxCatRx.Replace($idxNew, $newCat, 1)

''
'===== INDEX ====='
"index.html KB  : $([math]::Round([System.Text.Encoding]::UTF8.GetByteCount($idxNew) / 1KB, 1))"

if ($Apply) {
    Write-Text (Join-Path $Root 'static\js\catalog.js') $catalogScript $false
    Write-Text (Join-Path $Root 'index.html') $idxNew $idxData.Bom
    ''
    'files written:'
    '  static/js/catalog.js'
    '  index.html'
}
