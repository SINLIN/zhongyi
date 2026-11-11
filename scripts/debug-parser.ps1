<#
.SYNOPSIS
    Debug the sidebar parser.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu'
)

$out = New-Object System.Collections.Generic.List[string]
$index = Join-Path $Root 'index.html'
$text = [IO.File]::ReadAllText($index)

$out.Add("file bytes: $($text.Length)")
$out.Add("contains '<div id=`"sidebar`">' : " + ($text.Contains('<div id="sidebar">')))
$out.Add("contains '<div id=' + quote + 'sidebar' : " + ($text -match 'id="sidebar"'))
$out.Add("contains '<div id=`"header`">' : " + ($text.Contains('<div id="header">')))

$sb = [regex]::Match($text, '(?s)<div id="sidebar">.*?(?=<div id="header">)')
$out.Add("sidebar regex success : $($sb.Success)  len=$($sb.Length)")

# count raw occurrences
$out.Add("raw <li id='si' count : $(([regex]::Matches($text,'<li id=\"si')).Count)")
$out.Add("raw <a href count      : $(([regex]::Matches($text,'<a href=')).Count)")

# try match on whole document
$tokRx = New-Object System.Text.RegularExpressions.Regex(
    '<li id="si(\d+)">|<li>|</li>|<ul[^>]*>|</ul>|<span>([^<]*)</span>|<a href="([^"]*)" title="([^"]*)"([^>]*)>([^<]*)</a>')
$all = $tokRx.Matches($text)
$out.Add("token matches (whole doc) : $($all.Count)")
$out.Add("")
$out.Add('first 12 tokens:')
for ($k = 0; $k -lt [Math]::Min(12, $all.Count); $k++) {
    $mm = $all[$k]
    $tag = 'other'
    if ($mm.Groups[1].Success) { $tag = 'LI-si=' + $mm.Groups[1].Value }
    elseif ($mm.Groups[2].Success) { $tag = 'SPAN=' + $mm.Groups[2].Value }
    elseif ($mm.Groups[3].Success) { $tag = 'A=' + $mm.Groups[3].Value + ' | ' + $mm.Groups[4].Value }
    else { $tag = $mm.Value.Substring(0, [Math]::Min(20, $mm.Value.Length)) }
    $out.Add("  [$k] $tag")
}

$f = Join-Path $env:TEMP 'dbg.txt'
$out | Set-Content -Path $f -Encoding UTF8
Get-Content $f -Encoding UTF8
