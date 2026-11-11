<#
.SYNOPSIS
    批量清理 HTML 文件中的统计/埋点脚本，并把旧站点域名替换为新域名。

.DESCRIPTION
    1. 删除包含统计特征的 <script>...</script> 整块（user_set、百度统计、头条 ttzz 等）。
    2. 将旧域名（含 http/https/协议相对、带不带 www）替换为新域名。
    3. 保持原文件编码（UTF-8 有无 BOM 均可；非 UTF-8 时按 GBK 回退）。

.PARAMETER Root
    要处理的目录，默认当前目录。会递归处理所有 *.html。

.PARAMETER Domains
    需要替换的旧域名列表，默认 zysj.com.cn。

.PARAMETER NewHost
    新域名（不含协议），默认 zysjonline.com。

.PARAMETER DryRun
    只统计不写盘。

.EXAMPLE
    .\clean-html-tracking.ps1 -Root .\zysj\yixuezhongzhongcanxilu -DryRun
#>
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path,
    [string[]]$Domains = @('zysj.com.cn'),
    [string]$NewHost = 'zysjonline.com',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# 统计脚本特征（全部为 ASCII，避免编码问题）
$markers = 'user_set|hm\.baidu\.com|bytegoofy|//\s*头条|_hmt|cnzz\.com|google-analytics\.com|googletagmanager\.com'

$scriptBlockRegex = [regex]::new(
    '(?is)[ \t]*<script\b[^>]*>(?:(?!</script>)[\s\S])*?(?:' + $markers + ')(?:(?!</script>)[\s\S])*?</script>[ \t]*\r?\n?'
)

$hostPattern = ($Domains | ForEach-Object { [regex]::Escape($_) }) -join '|'
$domainRegex = [regex]::new('(?i)(?:https?:)?//(?:[\w-]+\.)*(?:' + $hostPattern + ')')
$newBase = 'https://' + $NewHost

$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$gbk = [System.Text.Encoding]::GetEncoding(936)

$files = Get-ChildItem -Path $Root -Recurse -File -Filter *.html
$scanned = 0
$scriptFiles = 0
$domainFiles = 0
$blocksRemoved = 0
$domainReplaced = 0
$residual = @()

foreach ($file in $files) {
    $scanned++
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

    if ($hasBom) {
        $text = $utf8Strict.GetString($bytes, 3, $bytes.Length - 3)
        $encoding = [System.Text.UTF8Encoding]::new($true)
    }
    else {
        try {
            $text = $utf8Strict.GetString($bytes)
            $encoding = [System.Text.UTF8Encoding]::new($false)
        }
        catch {
            $text = $gbk.GetString($bytes)
            $encoding = $gbk
        }
    }

    $original = $text

    $blockMatches = $scriptBlockRegex.Matches($text)
    if ($blockMatches.Count -gt 0) {
        $blocksRemoved += $blockMatches.Count
        $scriptFiles++
        $text = $scriptBlockRegex.Replace($text, '')
    }

    $domainMatches = $domainRegex.Matches($text)
    if ($domainMatches.Count -gt 0) {
        $domainReplaced += $domainMatches.Count
        $domainFiles++
        $text = $domainRegex.Replace($text, $newBase)
    }

    if ($text -ne $original) {
        if (-not $DryRun) {
            [System.IO.File]::WriteAllText($file.FullName, $text, $encoding)
        }
    }

    # 复查是否仍有残留特征
    $left = $scriptBlockRegex.Matches($text)
    if ($left.Count -gt 0) {
        $residual += $file.FullName
    }
}

$mode = if ($DryRun) { 'DRY-RUN（未写盘）' } else { '已写入' }
[pscustomobject]@{
    Mode             = $mode
    Root             = (Resolve-Path $Root).Path
    HtmlScanned      = $scanned
    FilesScriptClean = $scriptFiles
    BlocksRemoved    = $blocksRemoved
    FilesDomainFixed = $domainFiles
    DomainReplaced   = $domainReplaced
    ResidualFiles    = $residual.Count
} | Format-List

if ($residual.Count -gt 0) {
    '残留脚本特征的文件：'
    $residual
}
