# Bug — `reload_bypass_cache` is a plain reload

**Status:** ✅ fixed in **0.6.11**
**Date:** 2026-10-26
**Component:** `lib/webview2gtk/webview.vala`, `lib/host/win32-ui-webview2-capture.c`, `lib/host/webview2gtk-host-api.h`
**API parity:** WebKitGTK `WebKit.WebView.reload_bypass_cache`

---

## Symptom

`WebView.reload_bypass_cache()` calls `ICoreWebView2::Reload`. A page that is already showing can come back from the HTTP cache, including an error response, with no new request.

WebKit’s `reload_bypass_cache` ignores the cache (shift-reload). Callers use that method when the same URL must be fetched again after the session proxy changes.

```375:378:lib/webview2gtk/webview.vala
	public void reload_bypass_cache() {
		/* WebView2 has no WebKit-style cache bypass; reload is the closest match. */
		wv2_host_reload(host_handle);
	}
```

`vala_webview2_host_reload` is `ICoreWebView2_Reload`. `reload()` should stay that. `reload_bypass_cache()` should not.

## Proposal

Applied in 0.6.11.

DevTools `Page.reload` with `ignoreCache: true` is the shift-reload. `Page.captureScreenshot` in `lib/host/win32-ui-webview2-capture.c` already calls `ICoreWebView2_CallDevToolsProtocolMethod` and waits with `vala_webview2_com_sync_await`. Same pattern, method `Page.reload`, params `{"ignoreCache":true}`.

- Add `vala_webview2_host_reload_bypass_cache` next to `vala_webview2_host_reload` in `lib/host/webview2gtk-host-api.h`.
- Implement it beside the screenshot call. If the DevTools call fails, fall back to `ICoreWebView2_Reload`.
- `reload_bypass_cache()` calls that host function. `reload()` stays `ICoreWebView2_Reload`.
