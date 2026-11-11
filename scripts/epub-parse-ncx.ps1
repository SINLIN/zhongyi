<#
.SYNOPSIS
    Parse the EPUB NCX into an ordered chapter list with nesting levels.

.DESCRIPTION
    Emits JSON: [{ index, title, href, depth }] where depth 1 = volume heading,
    depth 2 = chapter under that volume.  Uses a proper navPoint nesting walk.
#>
param(
    [string]$WorkDir = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\_tmp_epub',
    [string]$OutJson = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\sishengxinyuan\_toc.json'
)

$ErrorActionPreference = 'Stop'

$ncx = Get-ChildItem -LiteralPath (Join-Path $WorkDir 'OEBPS') -Recurse -File -Filter '*.ncx' | Select-Object -First 1
if (-not $ncx) { throw 'no ncx' }
$xmlText = [IO.File]::ReadAllText($ncx.FullName)

[xml]$doc = $xmlText
$ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
$ns.AddNamespace('ncx', 'http://www.daidle.com/z3986/2005/ncx/')
# namespace-agnostic fallback: select by local-name
$navMap = $doc.SelectSingleNode("//*[local-name()='navMap']")
if (-not $navMap) { throw 'no navMap' }

$rows = New-Object System.Collections.Generic.List[object]
$counter = 0

function Walk($node, [int]$depth) {
    foreach ($child in $node.ChildNodes) {
        if ($child.NodeType -ne 'Element') { continue }
        if ($child.LocalName -ne 'navPoint') { continue }

        $script:counter++
        $label = $child.SelectSingleNode(".//*[local-name()='navLabel']/*[local-name()='text']")
        $content = $child.SelectSingleNode("./*[local-name()='content']")
        if ($content -eq $null) {
            $content = $child.SelectSingleNode(".//*[local-name()='content']")
        }

        $title = if ($label) { $label.InnerText.Trim() } else { '' }
        $src = if ($content) { $content.GetAttribute('src') } else { '' }

        # normalise src: strip fragment, keep path
        $href = ($src -split '#')[0]

        $script:rows.Add([pscustomobject]@{
                Order = $script:counter
                Depth = $depth
                Title = $title
                Href  = $href
            })

        Walk $child ($depth + 1)
    }
}

Walk $navMap 1

"navPoints parsed : $($rows.Count)"
"depth 1 (volumes): $(($rows | Where-Object { $_.Depth -eq 1 }).Count)"
"depth 2 (chapters): $(($rows | Where-Object { $_.Depth -eq 2 }).Count)"
"depth 3+         : $(($rows | Where-Object { $_.Depth -ge 3 }).Count)"
''

'--- depth 1 entries ---'
$rows | Where-Object { $_.Depth -eq 1 } | ForEach-Object { '  ' + $_.Title + '  ->  ' + $_.Href }

'' 
'--- first 8 of depth 2 ---'
$rows | Where-Object { $_.Depth -eq 2 } | Select-Object -First 8 | ForEach-Object { '  ' + $_.Title + '  ->  ' + $_.Href }

$rows | ConvertTo-Json -Depth 4 | Set-Content -Path $OutJson -Encoding UTF8
''
"written: $OutJson"
