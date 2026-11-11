<#
.SYNOPSIS
    End-to-end rebuild of the sishengxinyuan archive from the source EPUB.

.DESCRIPTION
    Runs the whole chain so the book can be reproduced from a single artifact:

        _source/sishengxinyuan.epub
              -> extract to a temp folder
              -> parse toc.ncx into _toc.json
              -> render chapter pages + index.html + static/js/catalog.js

    Requires sisheng-build.ps1 and epub-parse-ncx.ps1 next to this file.

    Dry-run by default; pass -Apply to write.
#>
param(
    [string]$Root = 'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\sishengxinyuan',
    [string]$Epub = '',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $Epub) { $Epub = Join-Path $Root '_source\sishengxinyuan.epub' }
if (-not (Test-Path -LiteralPath $Epub)) { throw "epub not found: $Epub" }

$work = Join-Path $env:TEMP 'sisheng_epub_work'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null
[System.IO.Compression.ZipFile]::ExtractToDirectory($Epub, $work)

"epub        : $Epub"
"extracted   : $work"
""

# 1. NCX -> _toc.json
$tocJson = Join-Path $Root '_toc.json'
& (Join-Path $here 'epub-parse-ncx.ps1') -WorkDir $work -OutJson $tocJson | Out-Null
if (-not (Test-Path -LiteralPath $tocJson)) { throw 'toc parse failed' }

# 2. build pages
$buildArgs = @{
    WorkDir = $work
    Root    = $Root
}
if ($Apply) { $buildArgs.Apply = $true }
& (Join-Path $here 'sisheng-build.ps1') @buildArgs

# 3. tidy
if ($Apply) {
    Remove-Item -LiteralPath $tocJson -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    ''
    'cleaned intermediate files'
}
