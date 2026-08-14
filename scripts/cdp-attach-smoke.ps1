# CDP attach + fill smoke for webview2gtk-automation (plan 3.0 / 3.3).
# Requires the automation browser already running with WEBKIT_INSPECTOR_SERVER /
# --inspector-port (default 19222).
#
#   Terminal 1:
#     & 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-automation.exe' --inspector-port 19222
#   Terminal 2:
#     & 'C:\msys64\tmp\webview2-gtk\scripts\cdp-attach-smoke.ps1'

param(
	[int] $Port = 19222,
	[string] $FillText = "webview2gtk-cdp-fill"
)

$ErrorActionPreference = "Stop"
$base = "http://127.0.0.1:$Port"

Write-Host "CDP /json/version ..."
try {
	$ver = Invoke-RestMethod -Uri "$base/json/version" -TimeoutSec 3
} catch {
	Write-Error "Cannot reach $base/json/version — is webview2gtk-automation.exe running with --inspector-port $Port ?"
	exit 1
}
Write-Host "  Browser = $($ver.Browser)"
Write-Host "  webSocketDebuggerUrl (browser) = $($ver.webSocketDebuggerUrl)"

Write-Host "CDP /json/list ..."
$pages = Invoke-RestMethod -Uri "$base/json/list" -TimeoutSec 3
if (-not $pages -or $pages.Count -lt 1) {
	Write-Error "No pages in /json/list"
	exit 1
}
$page = $pages | Where-Object { $_.type -eq "page" } | Select-Object -First 1
if (-not $page) { $page = $pages[0] }
$wsUrl = $page.webSocketDebuggerUrl
if (-not $wsUrl) {
	Write-Error "Page has no webSocketDebuggerUrl"
	exit 1
}
Write-Host "  page url = $($page.url)"
Write-Host "  ws = $wsUrl"

function Send-Cdp {
	param($Client, [hashtable]$Msg)
	$json = ($Msg | ConvertTo-Json -Compress -Depth 8)
	$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
	$seg = [ArraySegment[byte]]::new($bytes)
	$Client.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
}

function Recv-Cdp {
	param($Client, [int]$ExpectId, [int]$TimeoutMs = 8000)
	$buf = New-Object byte[] 1024*256
	$deadline = [datetime]::UtcNow.AddMilliseconds($TimeoutMs)
	while ([datetime]::UtcNow -lt $deadline) {
		$seg = [ArraySegment[byte]]::new($buf)
		$task = $Client.ReceiveAsync($seg, [Threading.CancellationToken]::None)
		if (-not $task.Wait($TimeoutMs)) { break }
		$result = $task.Result
		$text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $result.Count)
		# May be fragmented; for smoke assume single frame JSON
		$obj = $text | ConvertFrom-Json
		if ($null -ne $obj.id -and [int]$obj.id -eq $ExpectId) {
			return $obj
		}
		# ignore events
	}
	return $null
}

Write-Host "WebSocket CDP attach ..."
$ws = [System.Net.WebSockets.ClientWebSocket]::new()
$ws.ConnectAsync([Uri]$wsUrl, [Threading.CancellationToken]::None).Wait()
if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
	Write-Error "WebSocket not open: $($ws.State)"
	exit 1
}
Write-Host "  attached"

# Focus + set value via Runtime.evaluate (driver-equivalent fill for smoke)
$expr = @"
(() => {
  const q = document.querySelector('#q');
  if (!q) return { ok: false, err: 'no #q' };
  q.focus();
  q.value = '';
  q.value = $($FillText | ConvertTo-Json);
  q.dispatchEvent(new Event('input', { bubbles: true }));
  return { ok: true, value: q.value };
})()
"@

$id = 1
Send-Cdp $ws @{
	id = $id
	method = "Runtime.evaluate"
	params = @{
		expression = $expr
		returnByValue = $true
	}
}
$resp = Recv-Cdp $ws $id
$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", [Threading.CancellationToken]::None).Wait() | Out-Null

if (-not $resp) {
	Write-Error "No CDP response for Runtime.evaluate"
	exit 1
}
if ($resp.error) {
	Write-Error "CDP error: $($resp.error | ConvertTo-Json -Compress)"
	exit 1
}

$result = $resp.result.result
# result.value may be nested under result.result.value for object return
$val = $null
if ($result.value) { $val = $result.value }
elseif ($result.result.value) { $val = $result.result.value }

Write-Host "evaluate => $($val | ConvertTo-Json -Compress)"

if ($val.ok -eq $true -and $val.value -eq $FillText) {
	Write-Host "ATTACH_FILL_PASS"
	exit 0
}

Write-Error "Fill did not stick (expected value=$FillText)"
exit 1
