<#
.SYNOPSIS
    Verify a rebuilt chapter page: paragraph count and key markers.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu',
    [string]$File = '513-52-6.html'
)

$t = [IO.File]::ReadAllText((Join-Path $Root $File))
$m = [regex]::Match($t, '(?s)<div id="content">(.*?)</div>')
$c = $m.Groups[1].Value

"file            : $File"
"page bytes      : $((Get-Item (Join-Path $Root $File)).Length)"
"content chars   : $($c.Length)"
"<p> count       : $(([regex]::Matches($c,'<p>')).Count)"
"<strong> count  : $(([regex]::Matches($c,'<strong>')).Count)"
''
'key markers:'
foreach ($k in '方解', '复诊', '三诊', '效果', '甘遂', '朱砂', '石菖蒲') {
    '  {0,-8} : {1}' -f $k, ($c -match $k)
}
''
'first 200 chars of body:'
$c.Substring(0, [Math]::Min(200, $c.Length))
''
'last 200 chars of body:'
$c.Substring([Math]::Max(0, $c.Length - 200))
