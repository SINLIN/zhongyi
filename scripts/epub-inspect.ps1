<#
.SYNOPSIS
    Unpack an EPUB and report its structure (opf manifest/spine, chapter count).
#>
param(
    [string]$Epub = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\sishengxinyuan\《四圣心源》.epub',
    [string]$WorkDir = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\_tmp_epub'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$out = New-Object System.Collections.Generic.List[string]

if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

[System.IO.Compression.ZipFile]::ExtractToDirectory($Epub, $WorkDir)
$out.Add("extracted to : $WorkDir")

$files = Get-ChildItem -LiteralPath $WorkDir -Recurse -File
$out.Add("files        : $($files.Count)")

$out.Add('')
$out.Add('--- by extension ---')
$files | Group-Object Extension | Sort-Object Count -Descending |
    ForEach-Object { $out.Add(('{0,-8} {1,4}  {2,9:N0} KB' -f $_.Name, $_.Count, (($_.Group | Measure-Object Length -Sum).Sum / 1KB))) }

# container -> opf
$containerPath = Join-Path $WorkDir 'META-INF\container.xml'
$out.Add('')
$out.Add("container.xml exists : $(Test-Path -LiteralPath $containerPath)")

$opfRel = $null
if (Test-Path -LiteralPath $containerPath) {
    $c = [IO.File]::ReadAllText($containerPath)
    $m = [regex]::Match($c, 'full-path="([^"]+)"')
    if ($m.Success) { $opfRel = $m.Groups[1].Value }
}
$out.Add("opf path             : $opfRel")

if ($opfRel) {
    $opfPath = Join-Path $WorkDir $opfRel
    $opf = [IO.File]::ReadAllText($opfPath)
    $out.Add("opf bytes            : $($opf.Length)")

    # metadata
    foreach ($tag in 'title', 'creator', 'publisher', 'language', 'identifier') {
        $mm = [regex]::Match($opf, "(?is)<dc:$tag[^>]*>(.*?)</dc:$tag>")
        if ($mm.Success) { $out.Add(('  {0,-10} : {1}' -f $tag, $mm.Groups[1].Value.Trim())) }
    }

    $items = [regex]::Matches($opf, '<item\b[^>]*>')
    $out.Add("manifest items       : $($items.Count)")

    $spine = [regex]::Matches($opf, '<itemref\b[^>]*idref="([^"]+)"')
    $out.Add("spine itemrefs       : $($spine.Count)")

    # map id -> href for the first few spine entries
    $idMap = @{}
    foreach ($it in $items) {
        $id = [regex]::Match($it.Value, 'id="([^"]+)"')
        $href = [regex]::Match($it.Value, 'href="([^"]+)"')
        $mt = [regex]::Match($it.Value, 'media-type="([^"]+)"')
        if ($id.Success -and $href.Success) {
            $idMap[$id.Groups[1].Value] = @{
                Href = $href.Groups[1].Value
                Type = if ($mt.Success) { $mt.Groups[1].Value } else { '' }
            }
        }
    }

    $out.Add('')
    $out.Add('--- first 8 spine entries ---')
    $opfDir = Split-Path $opfPath -Parent
    for ($i = 0; $i -lt [Math]::Min(8, $spine.Count); $i++) {
        $idref = $spine[$i].Groups[1].Value
        if ($idMap.ContainsKey($idref)) {
            $h = $idMap[$idref].Href
            $full = Join-Path $opfDir $h
            $size = if (Test-Path -LiteralPath $full) { (Get-Item -LiteralPath $full).Length } else { -1 }
            $out.Add(('  [{0}] {1,-28} {2,8:N0} B  {3}' -f $i, $idref, $size, $h))
        }
    }

    $out.Add('')
    $out.Add('--- last 3 spine entries ---')
    for ($i = [Math]::Max(0, $spine.Count - 3); $i -lt $spine.Count; $i++) {
        $idref = $spine[$i].Groups[1].Value
        if ($idMap.ContainsKey($idref)) {
            $out.Add(('  [{0}] {1,-28} {2}' -f $i, $idref, $idMap[$idref].Href))
        }
    }
}

$f = Join-Path $env:TEMP 'epub-info.txt'
$out | Set-Content -Path $f -Encoding UTF8
Get-Content $f -Encoding UTF8
