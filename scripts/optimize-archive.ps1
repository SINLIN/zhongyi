<#
.SYNOPSIS
    Optimize an archived book directory: externalize catalog sidebar, collapse
    head icon links, slim js.js, add render hints to full-book pages.

.DESCRIPTION
    Works on the "HTTrack mirror" layout shared by the remaining books:

        <Root>/web/html/*.html      content pages
        <Root>/web/js/js.js         shared script
        <Root>/web/css/css.css      shared stylesheet

    Steps
      1. Externalize the byte-identical <div id="sidebar"> into web/js/catalog.js
         and replace it with a placeholder + <script> tag on each page.
      2. Collapse the 7 head icon/manifest references into one local favicon.
      3. Replace the obfuscated js.js with a small reader script
         (copied from another already-optimized book via -SlimJsSource).
      4. Inject content-visibility into quanben.html only (other pages that also
         contain div.section would get wrong height estimates).

    Dry-run by default. Pass -Apply to write.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    # Already-optimized js.js to reuse (optional)
    [string]$SlimJsSource = '',

    # Insert content-visibility into this page (relative to web/html)
    [string]$FullBookPage = 'quanben.html',

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$utf8Bom = [System.Text.UTF8Encoding]::new($true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)

$rootFull = (Resolve-Path $Root).Path.TrimEnd('\')
$htmlDir = Join-Path $rootFull 'web\html'
$jsDir = Join-Path $rootFull 'web\js'

if (-not (Test-Path $htmlDir)) { throw "missing $htmlDir" }

$dq = [char]34
$sidebarRx = [regex]'(?s)<div id="sidebar">.*?(?=<div id="header">)'
$iconRx = [regex]('(?m)^[ \t]*<link rel="(?:apple-touch-icon|icon|manifest|mask-icon|shortcut icon)"[^>]*>[ \t]*\r?\n')
$msConfigRx = [regex]('(?m)^[ \t]*<meta name="msapplication-config"[^>]*>[ \t]*\r?\n')
$styleRx = [regex]('<link\s+rel="stylesheet"[^>]*>')
$siIdRx = [regex]'\s+id="si\d+"'
$titleRx = [regex]'<a\s([^>]*?)title="([^"]*)"([^>]*)>([^<]*)</a>'

function Read-Text([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return @{ Text = $utf8Strict.GetString($bytes, 3, $bytes.Length - 3); Bom = $true }
    }
    return @{ Text = $utf8Strict.GetString($bytes); Bom = $false }
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

# ---------------------------------------------------------------- 1. canonical sidebar
$pages = Get-ChildItem -Path $htmlDir -File -Filter *.html | Sort-Object Name

$groups = @{}
foreach ($p in $pages) {
    $data = Read-Text $p.FullName
    $m = $sidebarRx.Match($data.Text)
    if (-not $m.Success -or $m.Length -lt 4000) { continue }
    $key = [System.BitConverter]::ToString(
        [System.Security.Cryptography.MD5]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($m.Value))).Replace('-', '')
    if (-not $groups.ContainsKey($key)) {
        $groups[$key] = [pscustomobject]@{ Count = 0; Sample = $p.Name; Value = $m.Value }
    }
    $groups[$key].Count++
}

if ($groups.Count -eq 0) { throw 'no reusable sidebar found' }
$canonical = ($groups.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending | Select-Object -First 1).Value

# trim the canonical copy: drop si* ids and duplicated title attrs, squeeze whitespace
$catalogOut = $siIdRx.Replace($canonical.Value, '')
$catalogOut = $titleRx.Replace($catalogOut, {
        param($m)
        if ($m.Groups[2].Value -eq $m.Groups[4].Value) {
            return '<a ' + ($m.Groups[1].Value + $m.Groups[3].Value).Trim() + '>' + $m.Groups[4].Value + '</a>'
        }
        return $m.Value
    })
$catalogOut = $catalogOut -replace '>\r?\n[ \t]*<', '><'
$catalogOut = $catalogOut.Trim()

$catalogScript = '(function(){var p=document.getElementById("sidebar-ph");if(!p)return;var d=document.createElement("div");d.innerHTML=' +
    (To-JsString $catalogOut) + ';p.parentNode.replaceChild(d.firstElementChild,p);})();'

# ---------------------------------------------------------------- rewrite pages
$stats = [ordered]@{
    HtmlPages       = $pages.Count
    PagesChanged    = 0
    SidebarReplaced = 0
    SidebarKept     = 0
    IconCollapsed   = 0
    FullBookCv      = 'n/a'
    BytesBefore     = 0
    BytesAfter      = 0
}

$keptInline = New-Object System.Collections.Generic.List[string]
$faviconHref = '../png/favicon-32x32.png'

foreach ($p in $pages) {
    $data = Read-Text $p.FullName
    $t = $data.Text
    $orig = $t
    $stats.BytesBefore += [System.Text.Encoding]::UTF8.GetByteCount($t)

    # 1. sidebar -> placeholder
    $m = $sidebarRx.Match($t)
    if ($m.Success -and $m.Length -ge 4000) {
        if ($m.Value -ceq $canonical.Value) {
            $ph = '<div id="sidebar-ph"></div>' + "`n" +
                  '<script type="text/javascript" src="../js/catalog.js" charset="UTF-8"></script>'
            $t = $t.Remove($m.Index, $m.Length).Insert($m.Index, $ph)
            $stats.SidebarReplaced++
        }
        else {
            $stats.SidebarKept++
            $keptInline.Add(('{0} ({1:N1} KB)' -f $p.Name, ($m.Length / 1KB)))
        }
    }

    # 2. collapse icon references
    $iconHits = $iconRx.Matches($t).Count + $msConfigRx.Matches($t).Count
    if ($iconHits -gt 0) {
        $fav = $null
        $favM = [regex]::Match($t, 'href="([^"]*favicon-32x32\.png)"')
        if ($favM.Success) { $fav = $favM.Groups[1].Value } else { $fav = $faviconHref }
        $t = $iconRx.Replace($t, '')
        $t = $msConfigRx.Replace($t, '')
        $t = $styleRx.Replace($t, ('<link rel="icon" type="image/png" href="' + $fav + '">' + "`n" + '$0'), 1)
        $stats.IconCollapsed++
    }

    # 3. content-visibility (full-book page only)
    if ($p.Name -eq $FullBookPage -and $t -notmatch 'content-visibility') {
        $cv = '<style>/* 全书页渲染优化：视口外章节跳过布局/绘制（章节平均高约 700px） */' + "`n" +
              '#content>div.section{content-visibility:auto;contain-intrinsic-size:auto 700px;}' + "`n" +
              '@media print{#content>div.section{content-visibility:visible;}}</style>' + "`n"
        $sm = $styleRx.Match($t)
        if ($sm.Success) {
            $t = $t.Insert($sm.Index + $sm.Length, "`n" + $cv)
            $stats.FullBookCv = 'added'
        }
        else { $stats.FullBookCv = 'stylesheet not found' }
    }
    elseif ($p.Name -eq $FullBookPage) { $stats.FullBookCv = 'already present' }

    $stats.BytesAfter += [System.Text.Encoding]::UTF8.GetByteCount($t)

    if ($t -ne $orig) {
        $stats.PagesChanged++
        if ($Apply) { Write-Text $p.FullName $t $data.Bom }
    }
}

# ---------------------------------------------------------------- write assets
if ($Apply) {
    Write-Text (Join-Path $jsDir 'catalog.js') $catalogScript $false

    if ($SlimJsSource -and (Test-Path -LiteralPath $SlimJsSource)) {
        $slim = Read-Text $SlimJsSource
        $jsPath = Join-Path $jsDir 'js.js'
        $before = (Get-Item $jsPath).Length
        Write-Text $jsPath $slim.Text $slim.Bom
        $stats | Add-Member -NotePropertyName 'JsBefore' -NotePropertyValue $before -Force
        $stats | Add-Member -NotePropertyName 'JsAfter' -NotePropertyValue (Get-Item $jsPath).Length -Force
    }
}

'===== ARCHIVE OPTIMIZE ====='
"mode                : $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' })"
"root                : $rootFull"
"html pages          : $($stats.HtmlPages)"
"pages changed       : $($stats.PagesChanged)"
"sidebar replaced    : $($stats.SidebarReplaced)"
"sidebar kept inline : $($stats.SidebarKept)"
"canonical sidebar   : $($canonical.Sample)  used by $($canonical.Count) pages"
"icon blocks         : $($stats.IconCollapsed)"
"full-book page      : $FullBookPage -> $($stats.FullBookCv)"
"catalog.js KB       : $([math]::Round([System.Text.Encoding]::UTF8.GetByteCount($catalogScript) / 1KB, 1))"
"html before MB      : $([math]::Round($stats.BytesBefore / 1MB, 2))"
"html after  MB      : $([math]::Round($stats.BytesAfter / 1MB, 2))"

if ($stats.Contains('JsBefore')) {
    "js.js bytes         : $($stats.JsBefore) -> $($stats.JsAfter)"
}

if ($keptInline.Count -gt 0) {
    ''
    '===== SIDEBAR KEPT INLINE ====='
    $keptInline | ForEach-Object { '  ' + $_ }
}
