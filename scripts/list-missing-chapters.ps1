<#
.SYNOPSIS
    List chapter links in the index page whose target file is missing locally.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu'
)

$ErrorActionPreference = 'Stop'
$index = Join-Path $Root 'index.html'
$text = [IO.File]::ReadAllText($index)

# every <li id="siNNN"><a href="..." title="...">
$rx = New-Object System.Text.RegularExpressions.Regex('<li id="si\d+"><a href="([^"]+)" title="([^"]*)">')
$rows = @()
foreach ($m in $rx.Matches($text)) {
    $href = $m.Groups[1].Value
    $title = $m.Groups[2].Value
    if ($href -match '^(https?:)?//') {
        $name = ($href -split '[?#]')[0].TrimEnd('/')
        $name = ($name -split '/')[-1]
        $kind = 'REMOTE'
    }
    elseif ($href -eq '') { continue }
    else {
        $name = ($href -split '[?#]')[0]
        $kind = 'LOCAL'
    }
    if (-not $name) { continue }
    $exists = Test-Path -LiteralPath (Join-Path $Root $name)
    $rows += [pscustomobject]@{
        File   = $name
        Kind   = $kind
        Exists = $exists
        Title  = $title
        Href   = $href
    }
}

$missing = $rows | Where-Object { -not $_.Exists }
"total chapter links : $($rows.Count)"
"missing locally     : $($missing.Count)"
"  of which remote   : $(($missing | Where-Object { $_.Kind -eq 'REMOTE' }).Count)"
"  of which local    : $(($missing | Where-Object { $_.Kind -eq 'LOCAL'  }).Count)"
''
'===== MISSING ====='
$missing | ForEach-Object { '{0,-16} {1,-7} {2}' -f $_.File, $_.Kind, $_.Title }

$outCsv = Join-Path $Root '_missing_chapters.csv'
$missing | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8
"`nwritten: $outCsv"
