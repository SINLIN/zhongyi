<#
.SYNOPSIS
    Verify every generated chapter page is reachable from the catalog.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\sishengxinyuan'
)

$out = New-Object System.Collections.Generic.List[string]

$pages = Get-ChildItem -LiteralPath $Root -File -Filter '*.html' |
    Where-Object { $_.Name -match '^\d+-\d+\.html$' } |
    Select-Object -ExpandProperty Name
$out.Add("chapter pages         : $($pages.Count)")

# links present in index.html catalog + catalog.js
$idx = [IO.File]::ReadAllText((Join-Path $Root 'index.html'))
$cat = [IO.File]::ReadAllText((Join-Path $Root 'static\js\catalog.js'))

$linked = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($m in [regex]::Matches($idx, 'href="(\d+-\d+\.html)"')) { [void]$linked.Add($m.Groups[1].Value) }
foreach ($m in [regex]::Matches($cat, 'href=\\"(\d+-\d+\.html)\\"')) { [void]$linked.Add($m.Groups[1].Value) }

$out.Add("unique links (index)  : $(([regex]::Matches($idx,'href=""(\d+-\d+\.html)""')).Count)")
$out.Add("unique links (catalog): $(([regex]::Matches($cat,'href=\\""(\d+-\d+\.html)\\""')).Count)")
$out.Add("unique link targets   : $($linked.Count)")

$orphans = @()
foreach ($p in $pages) { if (-not $linked.Contains($p)) { $orphans += $p } }

$broken = @()
foreach ($l in $linked) { if (-not (Test-Path -LiteralPath (Join-Path $Root $l))) { $broken += $l } }

$out.Add('')
$out.Add("orphaned pages        : $($orphans.Count)")
if ($orphans.Count -gt 0) { $out.Add('  ' + ($orphans -join ', ')) }
$out.Add("broken links          : $($broken.Count)")
if ($broken.Count -gt 0) { $out.Add('  ' + ($broken -join ', ')) }

# ---- full-book page ----
$out.Add('')
$qbPath = Join-Path $Root 'quanben.html'
if (-not (Test-Path -LiteralPath $qbPath)) {
    $out.Add('quanben.html          : MISSING')
}
else {
    $qb = [IO.File]::ReadAllText($qbPath)
    $secIds = [regex]::Matches($qb, '<div class="section" id="ci(\d+)">') | ForEach-Object { $_.Groups[1].Value }
    $siIds = [regex]::Matches($qb, 'id="si(\d+)"') | ForEach-Object { $_.Groups[1].Value }
    $out.Add("quanben.html sections : $($secIds.Count)")
    $out.Add("quanben.html si ids   : $($siIds.Count)")

    $noTarget = @()
    foreach ($s in $siIds) { if ($secIds -notcontains $s) { $noTarget += $s } }
    $out.Add("si without ci target  : $($noTarget.Count)")
    if ($noTarget.Count -gt 0) { $out.Add('  ' + ($noTarget -join ', ')) }

    $noLink = @()
    foreach ($s in $secIds) { if ($siIds -notcontains $s) { $noLink += $s } }
    $out.Add("ci without sidebar si : $($noLink.Count)")
    if ($noLink.Count -gt 0) { $out.Add('  ' + ($noLink -join ', ')) }

    $hasQ = $qb -match 'data-get="q"'
    $hasInlineSidebar = $qb -match '<div id="sidebar">'
    $hasCatalogJs = $qb -match 'catalog\.js'
    $out.Add("data-get=q            : $hasQ")
    $out.Add("inline sidebar        : $hasInlineSidebar")
    $out.Add("loads catalog.js      : $hasCatalogJs")

    $idx = [IO.File]::ReadAllText((Join-Path $Root 'index.html'))
    $out.Add("index -> quanben link : $($idx -match 'id="gather-content"[^>]*href="quanben\.html"')")

    $chap = [IO.File]::ReadAllText((Join-Path $Root '1296-13.html'))
    $out.Add("page -> quanben link  : $($chap -match 'id="gather-content"[^>]*href="quanben\.html"')")
}

$f = Join-Path $env:TEMP 'sisheng-verify.txt'
$out | Set-Content -Path $f -Encoding UTF8
Get-Content $f -Encoding UTF8
