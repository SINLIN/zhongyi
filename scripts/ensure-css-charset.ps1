<#
.SYNOPSIS
    Ensure a stylesheet starts with @charset "UTF-8";

.DESCRIPTION
    css.css contains Chinese text inside CSS content: values (e.g. the
    「（不分页）」 suffix on #gather-content). Without a @charset rule the
    browser falls back to the referring document's encoding and may decode the
    file as windows-1252, turning those strings into mojibake.

    @charset must be the very first bytes of the file (no BOM, no leading
    whitespace), so the rule is prepended to the raw bytes.

    Dry-run by default; pass -Apply to write.
#>
param(
    [string[]]$Files = @(
        'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\sishengxinyuan\static\css\css.css',
        'e:\04_WorkPlace\WorkSapce-Git\zhongyi\zysj\yixuezhongzhongcanxilu\static\css\css.css'
    ),
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$rule = [System.Text.Encoding]::ASCII.GetBytes('@charset "UTF-8";')

foreach ($f in $Files) {
    if (-not (Test-Path -LiteralPath $f)) { "missing : $f"; continue }
    $b = [System.IO.File]::ReadAllBytes($f)
    $head = [System.Text.Encoding]::ASCII.GetString($b, 0, [Math]::Min(32, $b.Length))

    if ($head.StartsWith('@charset')) {
        "ok      : $f  (already declared)"
        continue
    }

    "prepend : $f  ($($b.Length) bytes)"
    if ($Apply) {
        $out = New-Object byte[] ($rule.Length + $b.Length)
        [Array]::Copy($rule, 0, $out, 0, $rule.Length)
        [Array]::Copy($b, 0, $out, $rule.Length, $b.Length)
        [System.IO.File]::WriteAllBytes($f, $out)
        "  -> $($out.Length) bytes"
    }
}
