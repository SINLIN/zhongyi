<#
.SYNOPSIS
    Probe remote URLs through a local HTTP proxy.
#>
param(
    [string]$Proxy = 'http://127.0.0.1:2080'
)

$ErrorActionPreference = 'Continue'

$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$headers = @{
    'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    'Accept-Language' = 'zh-CN,zh;q=0.9,en;q=0.8'
    'Cache-Control'   = 'no-cache'
}

$urls = @(
    'https://zysjonline.com/books/yixuezhongzhongcanxilu/',
    'https://zysjonline.com/books/yixuezhongzhongcanxilu/513-52-6.html',
    'https://zysjonline.com/lilunshuji/yixuezhongzhongcanxilu/513-52-6.html'
)

foreach ($u in $urls) {
    try {
        $r = Invoke-WebRequest -Uri $u -UserAgent $ua -Headers $headers -Proxy $Proxy -TimeoutSec 30 -MaximumRedirection 5 -UseBasicParsing
        $title = ''
        if ($r.Content -match '(?is)<title>(.*?)</title>') { $title = $Matches[1].Trim() }
        "[OK]   $($r.StatusCode)  bytes=$($r.Content.Length)  title=$title"
        "       $u"
    }
    catch {
        $code = 'n/a'
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        "[FAIL] $code  $u"
        "       $($_.Exception.Message)"
    }
    ''
}