<#
.SYNOPSIS
    Static-archive page optimizer: externalize sidebar catalog, clean broken links/icon refs.

.DESCRIPTION
    1. Builds one shared catalog (sidebar HTML) and writes it to static/js/catalog.js
    2. Replaces the inline sidebar in every content page with a placeholder + script tag
    3. Rewrites absolute root-relative hrefs (/xxx) to the online site
    4. Collapses the 8 /logo/* icon references into a single local favicon

    Dry-run by default; pass -Apply to write files.
#>
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path,
    [string]$NewHost = 'zysjonline.com',
    [string]$BookPath = '/lilunshuji/yixuezhongzhongcanxilu/',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$utf8Bom = [System.Text.UTF8Encoding]::new($true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)

$sidebarRx = [regex]'(?s)<div id="sidebar">.*?(?=<div id="header">)'
$absHrefRx = [regex]'href="/(?!/)[^"]*"'
$siIdRx = [regex]'\s+id="si\d+"'
$titleRx = [regex]'<a\s([^>]*?)title="([^"]*)"([^>]*)>([^<]*)</a>'
$iconRx = [regex]'(?m)^[ \t]*<link rel="(?:apple-touch-icon|icon|manifest|mask-icon|shortcut icon)"[^>]*>\s*\r?\n'
$msConfigRx = [regex]'(?m)^[ \t]*<meta name="msapplication-config"[^>]*>\s*\r?\n'

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

# ---------- 1. build canonical catalog ----------
$rep = Join-Path $Root '513-4-1.html'
$repData = Read-Text $rep
$m = $sidebarRx.Match($repData.Text)
if (-not $m.Success) { throw "cannot locate sidebar in $rep" }
$catalog = $m.Value

# fill the current-chapter empty href with its real filename
$dq = [char]34
$catalog = $catalog.Replace('<a href=' + $dq + $dq, '<a href=' + $dq + '513-4-1.html' + $dq)

# rewrite links to locally missing chapters -> online site (avoids dead links)
$deadCount = 0
$linkRx = [regex]('href=' + $dq + [regex]::Escape($BookPath) + '([^' + $dq + ']+)' + $dq)
$catalog = $linkRx.Replace($catalog, {
        param($mm)
        $name = $mm.Groups[1].Value
        $local = Join-Path $Root $name
        if (Test-Path -LiteralPath $local) { return $mm.Value }
        $script:deadCount++
        return 'href=' + [char]34 + 'https://' + $script:NewHost + $script:BookPath + $name + [char]34
    })

# drop unused si* ids (only the original js.js used them)
$catalog = $siIdRx.Replace($catalog, '')

# drop redundant title attributes (title text identical to the link text)
$catalog = $titleRx.Replace($catalog, {
        param($mm)
        if ($mm.Groups[2].Value -eq $mm.Groups[4].Value) {
            return '<a ' + ($mm.Groups[1].Value + $mm.Groups[3].Value).Trim() + '>' + $mm.Groups[4].Value + '</a>'
        }
        return $mm.Value
    })

# collapse newline + indentation between tags (keeps single spaces between inline links)
$catalog = $catalog -replace '>\r?\n[ \t]*<', '><'
$catalog = $catalog.Trim()

$jsDir = Join-Path $Root 'static\js'
$catalogJs = Join-Path $jsDir 'catalog.js'
$json = To-JsString $catalog
$catalogScript = '(function(){var p=document.getElementById("sidebar-ph");if(!p)return;var d=document.createElement("div");d.innerHTML=' + $json + ';p.parentNode.replaceChild(d.firstElementChild,p);})();'

# ---------- 2/3/4. rewrite pages ----------
$files = Get-ChildItem -Path $Root -Recurse -File -Filter *.html |
    Where-Object { $_.DirectoryName -eq (Resolve-Path $Root).Path }

$skipSidebar = @('index.html', 'index1.html', 'index2.html', 'quanben.html')
$pageChanged = 0
$sideReplaced = 0
$absFixed = 0
$iconFixed = 0
$bytesBefore = 0
$bytesAfter = 0

foreach ($f in $files) {
    $data = Read-Text $f.FullName
    $t = $data.Text
    $orig = $t
    $bytesBefore += [System.Text.Encoding]::UTF8.GetByteCount($t)

    # sidebar -> placeholder + external catalog
    if ($skipSidebar -notcontains $f.Name) {
        $sm = $sidebarRx.Match($t)
        if ($sm.Success -and $sm.Length -gt 5000) {
            $ph = '<div id="sidebar-ph"></div>' + "`n" + '<script type="text/javascript" src="static/js/catalog.js"></script>'
            $t = $t.Remove($sm.Index, $sm.Length).Insert($sm.Index, $ph)
            $sideReplaced++
        }
    }

    # icon refs -> single local favicon
    $iconHits = $iconRx.Matches($t).Count + $msConfigRx.Matches($t).Count
    if ($iconHits -gt 0) {
        $t = $iconRx.Replace($t, '')
        $t = $msConfigRx.Replace($t, '')
        $t = $t.Replace('<link rel="stylesheet" type="text/css" href="static/css/css.css">',
            '<link rel="icon" type="image/png" href="static/picture/logo.png">' + "`n" + '    <link rel="stylesheet" type="text/css" href="static/css/css.css">')
        $iconFixed++
    }

    # remaining root-relative hrefs -> online site
    $abs = $absHrefRx.Matches($t)
    if ($abs.Count -gt 0) {
        $t = $absHrefRx.Replace($t, {
                param($mm)
                $script:absFixed++
                return $mm.Value.Replace('href="' + '/', 'href="https://' + $script:NewHost + '/')
            })
    }

    $bytesAfter += [System.Text.Encoding]::UTF8.GetByteCount($t)

    if ($t -ne $orig) {
        $pageChanged++
        if ($Apply) { Write-Text $f.FullName $t $data.Bom }
    }
}

[pscustomobject]@{
    Mode                = $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' })
    HtmlFiles           = $files.Count
    PagesChanged        = $pageChanged
    SidebarsExternalized = $sideReplaced
    DeadLinksToOnline   = $deadCount
    AbsoluteHrefsFixed  = $absFixed
    IconBlocksCollapsed = $iconFixed
    CatalogKB           = [math]::Round([System.Text.Encoding]::UTF8.GetByteCount($catalog) / 1KB, 1)
    CatalogJsKB         = [math]::Round([System.Text.Encoding]::UTF8.GetByteCount($catalogScript) / 1KB, 1)
    HtmlTotalBeforeMB   = [math]::Round($bytesBefore / 1MB, 2)
    HtmlTotalAfterMB    = [math]::Round($bytesAfter / 1MB, 2)
} | Format-List

if ($Apply) {
    Write-Text $catalogJs $catalogScript $false
    "catalog.js written: $catalogJs"
}
