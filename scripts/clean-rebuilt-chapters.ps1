<#
.SYNOPSIS
    Delete rebuilt chapter files so they can be regenerated cleanly.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu'
)

$chs = Get-Content (Join-Path $Root '_chapters.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$remote = @($chs | Where-Object { $_.Remote })
$n = 0
foreach ($c in $remote) {
    $f = Join-Path $Root $c.File
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force; $n++ }
}
"deleted : $n / $($remote.Count)"
"html now: $((Get-ChildItem -Path $Root -File -Filter *.html).Count)"
