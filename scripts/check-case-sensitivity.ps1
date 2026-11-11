<#
.SYNOPSIS
    Verify that local asset references in HTML match on-disk file names with exact case.

.DESCRIPTION
    Windows/macOS filesystems are case-insensitive but Cloudflare Workers (Linux) is
    case-sensitive, so a link like "124-10-1.HTML" would 404 after deployment even
    though it works locally.

    Builds a case-sensitive index of every file under -Root once, then resolves each
    href/src reference against it.

    Read-only. Exit code 1 if any mismatch is found.
#>
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path,
    [int]$MaxReport = 40
)

$ErrorActionPreference = 'Stop'

$rootFull = (Resolve-Path $Root).Path.TrimEnd('\')
$prefixLen = $rootFull.Length + 1

# ---------- build case-sensitive index ----------
$files = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$dirs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)

Get-ChildItem -Path $rootFull -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '\\\.git\\' } |
    ForEach-Object { [void]$files.Add($_.FullName.Substring($prefixLen)) }

Get-ChildItem -Path $rootFull -Recurse -Directory -Force |
    Where-Object { $_.FullName -notmatch '\\\.git' } |
    ForEach-Object { [void]$dirs.Add($_.FullName.Substring($prefixLen)) }

# case-insensitive map for diagnosis: lower -> actual casing
$ciMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($f in $files) { if (-not $ciMap.ContainsKey($f)) { $ciMap[$f] = $f } }

$refRx = [regex]'(?:href|src)\s*=\s*"([^"]+)"'
$skipRx = [regex]'^(?:https?:)?//|^(?:mailto|javascript|data|tel):|^#'

$stats = @{
    Pages     = 0
    Refs      = 0
    Local     = 0
    Ok        = 0
    Missing   = 0
    CaseWrong = 0
    Escaped   = 0
}

$missing = New-Object System.Collections.Generic.List[string]
$caseWrong = New-Object System.Collections.Generic.List[string]

$htmlFiles = Get-ChildItem -Path $rootFull -Recurse -File -Filter *.html -Force |
    Where-Object { $_.FullName -notmatch '\\\.git\\' }

foreach ($page in $htmlFiles) {
    $stats.Pages++
    $text = [System.IO.File]::ReadAllText($page.FullName)
    $pageRel = $page.FullName.Substring($prefixLen)

    foreach ($m in $refRx.Matches($text)) {
        $stats.Refs++
        $ref = $m.Groups[1].Value.Trim()
        if (-not $ref) { continue }
        if ($skipRx.IsMatch($ref)) { continue }

        # strip query / fragment / URL-decode
        $clean = ($ref -split '[?#]')[0]
        if (-not $clean) { continue }
        if ($clean -match '%') {
            try { $clean = [System.Uri]::UnescapeDataString($clean) } catch { }
        }
        # a bare directory reference ("./dir/") resolves to a directory, not a file
        $isDirRef = $clean.EndsWith('/')
        $stats.Local++

        $resolved = [System.IO.Path]::GetFullPath((Join-Path $page.DirectoryName $clean))
        if (-not $resolved.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
            $stats.Escaped++
            continue
        }
        $rel = $resolved.Substring($prefixLen).TrimEnd('\')
        if (-not $rel) {
            # reference to the site root itself
            $stats.Ok++
            continue
        }

        if ($files.Contains($rel) -or $dirs.Contains($rel)) {
            $stats.Ok++
            continue
        }
        # directory refs may lack a trailing index.html
        if ($isDirRef -and $dirs.Contains($rel)) {
            $stats.Ok++
            continue
        }

        # does it exist only when ignoring case?
        if ($ciMap.ContainsKey($rel)) {
            $stats.CaseWrong++
            if ($caseWrong.Count -lt $MaxReport) {
                $caseWrong.Add(('{0}  ->  {1}   (disk: {2})' -f $pageRel, $clean, $ciMap[$rel]))
            }
        }
        else {
            $stats.Missing++
            if ($missing.Count -lt $MaxReport) {
                $missing.Add(('{0}  ->  {1}' -f $pageRel, $clean))
            }
        }
    }
}

'===== LOCAL REFERENCE CHECK ====='
"root            : $rootFull"
"html pages      : $($stats.Pages)"
"refs total      : $($stats.Refs)"
"local refs      : $($stats.Local)"
"resolved ok     : $($stats.Ok)"
"case mismatch   : $($stats.CaseWrong)"
"missing         : $($stats.Missing)"
"outside root    : $($stats.Escaped)"

if ($caseWrong.Count -gt 0) {
    ''
    '===== CASE MISMATCH (breaks on Linux / Cloudflare) ====='
    $caseWrong | ForEach-Object { '  ' + $_ }
    if ($stats.CaseWrong -gt $caseWrong.Count) { "  ... and $($stats.CaseWrong - $caseWrong.Count) more" }
}

if ($missing.Count -gt 0) {
    ''
    '===== MISSING TARGETS ====='
    $missing | ForEach-Object { '  ' + $_ }
    if ($stats.Missing -gt $missing.Count) { "  ... and $($stats.Missing - $missing.Count) more" }
}

if ($stats.CaseWrong -gt 0 -or $stats.Missing -gt 0) { exit 1 }
exit 0
