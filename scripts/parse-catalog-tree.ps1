<#
.SYNOPSIS
    Parse the sidebar of index.html into an ordered chapter list with categories.

.DESCRIPTION
    The sidebar is a nested <li id="siNNN"> tree:
        <li><span>Category</span><ul> <li><a href="file.html">Title</a></li> ... </ul></li>
    This walks the markup with a depth counter and emits, for every chapter link,
    its si id, file name, title, and enclosing category.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu',
    [string]$OutJson = ''
)

$ErrorActionPreference = 'Stop'

$index = Join-Path $Root 'index.html'
$text = [IO.File]::ReadAllText($index)

# The full tree lives in <ul id="catalog-content"> ... </ul> (the sidebar div itself is empty).
$sb = [regex]::Match($text, '(?s)<ul id="catalog-content"[^>]*>(.*?)</ul>\s*</div>')
if (-not $sb.Success) {
    $sb = [regex]::Match($text, '(?s)<div id="sidebar">.*?(?=<div id="header">)')
}
if (-not $sb.Success) { throw 'catalog tree not found in index.html' }
$html = if ($sb.Groups.Count -gt 1 -and $sb.Groups[1].Success) { $sb.Groups[1].Value } else { $sb.Value }

# tokenise <li id="siNNN">, </li>, <ul>, </ul>, <span>..</span>, <a href=.. title=..>..</a>
$tokRx = New-Object System.Text.RegularExpressions.Regex(
    '<li id="si(\d+)">|<li>|</li>|<ul[^>]*>|</ul>|<span>([^<]*)</span>|<a href="([^"]*)" title="([^"]*)"([^>]*)>([^<]*)</a>')

$stack = New-Object System.Collections.Generic.List[string]   # category names
$pendingCat = $null
$pendingIsGroup = $false
$pendingSi = $null
$chapters = New-Object System.Collections.Generic.List[object]

foreach ($m in $tokRx.Matches($html)) {
    $v = $m.Value
    if ($m.Groups[1].Success) {
        $pendingSi = $m.Groups[1].Value
        $pendingIsGroup = $false
        continue
    }
    if ($v -eq '<ul' -or $v.StartsWith('<ul')) {
        if ($pendingCat) { $stack.Add($pendingCat); $pendingCat = $null }
        elseif ($pendingIsGroup) { $stack.Add($null) }
        continue
    }
    if ($v -eq '</ul>') {
        if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
        continue
    }
    if ($m.Groups[2].Success) {
        # <span>category</span>  -> marks the next <ul> as a category level
        $name = $m.Groups[2].Value.Trim()
        if ($name) { $pendingCat = $name }
        continue
    }
    if ($m.Groups[3].Success) {
        $href = $m.Groups[3].Value
        $title = $m.Groups[4].Value
        $attrs = $m.Groups[5].Value
        $linkText = $m.Groups[6].Value

        # skip the "节" helper links that point at *_group.html
        if ($attrs -match 'catalog_group') { continue }
        if ($linkText.Trim() -eq '节') { continue }
        if (-not $href) { continue }

        $name = ($href -split '[?#]')[0].TrimEnd('/')
        $name = ($name -split '/')[-1]
        if (-not $name) { continue }

        $category = $null
        for ($k = $stack.Count - 1; $k -ge 0; $k--) {
            if ($stack[$k]) { $category = $stack[$k]; break }
        }

        $chapters.Add([pscustomobject]@{
                Si       = $pendingSi
                File     = $name
                Title    = $title
                Category = $category
                Remote   = ($href -match '^(https?:)?//')
                Href     = $href
            })
        $pendingSi = $null
        $pendingIsGroup = $true
        continue
    }
}

"chapters parsed : $($chapters.Count)"
"remote chapters : $(($chapters | Where-Object { $_.Remote }).Count)"
"categories seen : $((($chapters | Where-Object { $_.Category } | Select-Object -ExpandProperty Category -Unique)).Count)"

if ($OutJson) {
    $chapters | ConvertTo-Json -Depth 4 | Set-Content -Path $OutJson -Encoding UTF8
    "written: $OutJson"
}

''
'first 5 :'
$chapters | Select-Object -First 5 | ForEach-Object { '  si{0,-7} {1,-16} {2,-22} {3}' -f $_.Si, $_.File, $_.Category, $_.Title }
''
'last 5 :'
$chapters | Select-Object -Last 5 | ForEach-Object { '  si{0,-7} {1,-16} {2,-22} {3}' -f $_.Si, $_.File, $_.Category, $_.Title }
