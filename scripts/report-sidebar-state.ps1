<#
.SYNOPSIS
    Report sidebar / catalog link state for the yixue book.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu'
)

$out = New-Object System.Collections.Generic.List[string]

$idx = Join-Path $Root 'index.html'
$i = [IO.File]::ReadAllText($idx)
$out.Add("index.html bytes           : $((Get-Item $idx).Length)")
$out.Add("index.html has id=sidebar  : $($i -match 'id=\"sidebar\"')")
$out.Add("index.html has sidebar-ph  : $($i -match 'sidebar-ph')")
$out.Add("index.html has guide list  : $($i -match 'id=\"guide\"')")
$out.Add("index.html si count        : $(([regex]::Matches($i,'id=\"si\d+\"')).Count)")
$out.Add("index.html remote zysj link: $(([regex]::Matches($i,'zysjonline\.com')).Count)")
$out.Add("")

$cat = Join-Path $Root 'static\js\catalog.js'
$c = [IO.File]::ReadAllText($cat)
$out.Add("catalog.js bytes           : $((Get-Item $cat).Length)")
$out.Add("catalog.js zysjonline links: $(([regex]::Matches($c,'zysjonline\.com')).Count)")
$out.Add("catalog.js 513-52-6 hits   : $(([regex]::Matches($c,'513-52-6')).Count)")
$out.Add("catalog.js si ids          : $(([regex]::Matches($c,'id=\\\"si\d+')).Count)")
$out.Add("")

# sample of the remote link inside catalog.js
$m = [regex]::Match($c, '.{60}513-52-6\.html.{20}')
if ($m.Success) { $out.Add("catalog sample: ...$($m.Value)...") }

# does catalog still carry category <span> headers?
$spans = [regex]::Matches($c, '<span>([^<]{2,40})</span>')
$out.Add("")
$out.Add("catalog category spans     : $($spans.Count)")
for ($k = 0; $k -lt [Math]::Min(6, $spans.Count); $k++) {
    $out.Add("  - $($spans[$k].Groups[1].Value)")
}

$f = Join-Path $env:TEMP 'sidebar-state.txt'
$out | Set-Content -Path $f -Encoding UTF8
Get-Content $f -Encoding UTF8
