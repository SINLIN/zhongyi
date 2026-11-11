<#
.SYNOPSIS
    Optimize the jingyuequanshu archive: externalize catalog, fix links, slim JS, add render hints.

.DESCRIPTION
    P0  1. Externalize the repeated <div id="sidebar"> into web/js/catalog.js
        2. Collapse the 7 head icon/manifest references into one local favicon
        3. Replace the 44 KB obfuscated js.js with a 3.4 KB reader script
        4. Add content-visibility to chapter containers (only affects quanben.html)
    P1  5. Rewrite ../../external.html?link=https://zysj.imoneso.cn/... to local files
           or https://zysjonline.com/... (4797 occurrences)
    P2  6. Repair the dead index-18.html footer link

    Dry-run by default. Pass -Apply to write.
#>
[CmdletBinding()]
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\jingyuequanshu',
    [string]$NewHost = 'zysjonline.com',
    [string]$BookPath = '/lilunshuji/jingyuequanshu/',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$utf8Bom = [System.Text.UTF8Encoding]::new($true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)

$htmlDir = Join-Path $Root 'web\html'
$jsDir = Join-Path $Root 'web\js'
$cssFile = Join-Path $Root 'web\css\css.css'

$dq = [char]34
$iconRx = [regex]('(?m)^[ \t]*<link rel="(?:apple-touch-icon|icon|manifest|mask-icon|shortcut icon)"[^>]*>[ \t]*\r?\n')
$msConfigRx = [regex]('(?m)^[ \t]*<meta name="msapplication-config"[^>]*>[ \t]*\r?\n')
$externalRx = [regex]('(?:[\w./]*/)?external\.html\?link=([^"' + $dq + '\s]+)')
$siIdRx = [regex]'\s+id="si\d+"'
$titleRx = [regex]'<a\s([^>]*?)title="([^"]*)"([^>]*)>([^<]*)</a>'
# hosts that belong to the archived mirror and must be remapped
$mirrorHostRx = [regex]'^https?://(?:[\w-]+\.)*(?:imoneso\.cn|zysj\.com\.cn|zysjonline\.com)'

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

# ------------------------------------------------------------------ sidebar helpers
function Get-SidebarExact([string]$text) {
    $start = $text.IndexOf('<div id="sidebar">')
    if ($start -lt 0) { return $null }
    $depth = 0
    foreach ($m in [regex]::Matches($text.Substring($start), '</?div\b[^>]*>')) {
        if ($m.Value.StartsWith('</')) {
            $depth--
            if ($depth -eq 0) {
                return @{ Start = $start; Length = $m.Index + $m.Length }
            }
        }
        else { $depth++ }
    }
    return $null
}

# ------------------------------------------------------------------ link rewriting
$script:extUnwrapped = 0
$script:extLocal = 0
$script:extRemapped = 0

function Convert-Links([string]$text) {
    if ($text.IndexOf('external.html?link=') -lt 0) { return $text }
    return $externalRx.Replace($text, {
            param($m)
            $target = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
            $script:extUnwrapped++
            if ($mirrorHostRx.IsMatch($target)) {
                $path = [regex]::Replace($target, '^https?://[^/]+', '')
                if ($path.StartsWith($script:BookPath)) {
                    $local = $path.Substring($script:BookPath.Length)
                    if ($local -and (Test-Path -LiteralPath (Join-Path $script:htmlDir $local))) {
                        $script:extLocal++
                        return $local
                    }
                }
                if (-not $path) { $path = '/' }
                $script:extRemapped++
                return 'https://' + $script:NewHost + $path
            }
            # non-mirror host: just drop the HTTrack redirect layer
            return $target
        })
}

# ------------------------------------------------------------------ canonical catalog
$repFile = Join-Path $htmlDir '124-10-1.html'
$rep = Read-Text $repFile
$bound = Get-SidebarExact $rep.Text
if (-not $bound) { throw "cannot locate sidebar in $repFile" }
$catalog = $rep.Text.Substring($bound.Start, $bound.Length)
$catalogOriginalBytes = [System.Text.Encoding]::UTF8.GetByteCount($catalog)

# strip si* ids (only the removed js.js used them)
$catalogOut = $siIdRx.Replace($catalog, '')
# strip redundant title attributes where title == link text
$catalogOut = $titleRx.Replace($catalogOut, {
        param($m)
        if ($m.Groups[2].Value -eq $m.Groups[4].Value) {
            return '<a ' + ($m.Groups[1].Value + $m.Groups[3].Value).Trim() + '>' + $m.Groups[4].Value + '</a>'
        }
        return $m.Value
    })
# collapse whitespace between tags
$catalogOut = $catalogOut -replace '>\r?\n[ \t]*<', '><'
$catalogOut = Convert-Links $catalogOut.Trim()

$catalogScript = '(function(){var p=document.getElementById("sidebar-ph");if(!p)return;var d=document.createElement("div");d.innerHTML=' + (To-JsString $catalogOut) + ';p.parentNode.replaceChild(d.firstElementChild,p);})();'

# ------------------------------------------------------------------ scan pages
$files = Get-ChildItem -Path $htmlDir -File -Filter *.html | Sort-Object Name

$pageTotal = 0
$sideExternalized = 0
$sideSkipped = 0
$iconFixed = 0
$deadFixed = 0
$pagesChanged = 0
$before = 0
$after = 0
$skippedNames = New-Object System.Collections.Generic.List[string]

foreach ($f in $files) {
    $pageTotal++
    $data = Read-Text $f.FullName
    $t = $data.Text
    $orig = $t
    $before += [System.Text.Encoding]::UTF8.GetByteCount($t)

    # --- 1. externalize sidebar (only the byte-identical canonical one)
    $b = Get-SidebarExact $t
    if ($b) {
        $side = $t.Substring($b.Start, $b.Length)
        if ($side -ceq $catalog) {
            $ph = '<div id="sidebar-ph"></div>' + "`n" + '<script type="text/javascript" src="../js/catalog.js" charset="UTF-8"></script>'
            $t = $t.Remove($b.Start, $b.Length).Insert($b.Start, $ph)
            $sideExternalized++
        }
        else {
            $sideSkipped++
            $skippedNames.Add(('{0} ({1:N1} KB)' -f $f.Name, ($side.Length / 1KB)))
        }
    }

    # --- 2. collapse icon references
    $iconHits = $iconRx.Matches($t).Count + $msConfigRx.Matches($t).Count
    if ($iconHits -gt 0) {
        $t = $iconRx.Replace($t, '')
        $t = $msConfigRx.Replace($t, '')
        $t = $t.Replace('<link rel="stylesheet" type="text/css" href="../css/css.css" charset="UTF-8" />',
            '<link rel="icon" type="image/png" href="../png/favicon-32x32.png">' + "`n" + '    <link rel="stylesheet" type="text/css" href="../css/css.css" charset="UTF-8" />')
        $iconFixed++
    }

    # --- 3. unwrap external.html?link=<url> and remap mirror hosts
    if ($t.IndexOf('external.html?link=') -ge 0) {
        $t = Convert-Links $t
    }

    # --- 4. repair dead index-18.html footer link (ICP filing link)
    if ($t.IndexOf('index-18.html') -ge 0) {
        $t = $t.Replace('href="index-18.html"', 'href="https://beian.miit.gov.cn"')
        $deadFixed++
    }

    $after += [System.Text.Encoding]::UTF8.GetByteCount($t)

    if ($t -ne $orig) {
        $pagesChanged++
        if ($Apply) { Write-Text $f.FullName $t $data.Bom }
    }
}

# ------------------------------------------------------------------ catalog.js
$catalogJs = Join-Path $jsDir 'catalog.js'
if ($Apply) { Write-Text $catalogJs $catalogScript $false }

# ------------------------------------------------------------------ css content-visibility
$cssData = Read-Text $cssFile
$cvMarker = 'content-visibility'
if ($cssData.Text -notmatch $cvMarker) {
    $add = "`n" + '/* 全书不分页页面的渲染优化：视口外章节跳过布局/绘制（章节平均高约 700px） */' + "`n" +
           '#content>div.section{content-visibility:auto;contain-intrinsic-size:auto 700px;}' + "`n" +
           '@media print{#content>div.section{content-visibility:visible;}}' + "`n"
    if ($Apply) { Write-Text $cssFile ($cssData.Text.TrimEnd() + $add) $cssData.Bom }
}

# ------------------------------------------------------------------ summary
'===== JINGYUEQUANSHU OPTIMIZE ====='
"mode                  : $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' })"
"root                  : $Root"
"html pages            : $pageTotal"
"pages changed         : $pagesChanged"
"sidebar externalized  : $sideExternalized"
"sidebar kept inline   : $sideSkipped"
"mirror links unwrapped: $extUnwrapped  (local: $extLocal, remapped: $extRemapped)"
"icon blocks collapsed : $iconFixed"
"dead link fixed       : $deadFixed"
"catalog source KB     : $([math]::Round($catalogOriginalBytes / 1KB, 1))"
"catalog.js KB         : $([math]::Round([System.Text.Encoding]::UTF8.GetByteCount($catalogScript) / 1KB, 1))"
"html total before MB  : $([math]::Round($before / 1MB, 2))"
"html total after  MB  : $([math]::Round($after / 1MB, 2))"
"css content-visibility: $(if ($cssData.Text -match $cvMarker) { 'already present' } else { $(if ($Apply) { 'added' } else { 'would add' }) })"

if ($skippedNames.Count -gt 0) {
    ''
    '===== SIDEBAR KEPT INLINE (variant / empty) ====='
    $skippedNames | ForEach-Object { '  ' + $_ }
}
