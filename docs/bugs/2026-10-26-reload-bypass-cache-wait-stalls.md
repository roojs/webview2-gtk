# Bug — `reload_bypass_cache` never returns

**Status:** ✅ fixed, Windows runtime smoke passed
**Date:** 2026-10-26
**Component:** `lib/host/win32-ui-webview2-capture.c`, `examples/add-cookie/main.vala`, `scripts/run-add-cookie-smoke-interactive.sh`
**Follows:** `docs/bugs/done/2026-10-26-reload-bypass-cache-is-plain-reload.md` (0.6.11 calls DevTools `Page.reload`)

---

## Symptom

`WebView.reload_bypass_cache()` does not return. The document stays as it was. The local proxy logs no new `CONNECT` for that host.

Calling `load_uri` with the same URL, including after `load_html`, also does not `CONNECT`. The previous response stays on screen. A first load of a URL that is not already in memory does `CONNECT` and shows the new document. `Navigate` is not a substitute for a cache-bypassing reload.

## Repro

1. Before the first `WebView`, set `NetworkProxyMode.CUSTOM` to `http://127.0.0.1` so the embedded proxy is listening.
2. `load_uri` a page. The proxy logs `CONNECT` for that host and the document finishes.
3. Optionally point that session at an upstream HTTP proxy.
4. Call `reload_bypass_cache()` while the view is still on that URL.

The call does not return. No second `CONNECT` for the page host is logged.

## Analysis

0.6.11 waits synchronously for the DevTools callback with `vala_webview2_com_sync_await`:

```628:634:lib/host/win32-ui-webview2-com-glue.c
void
vala_webview2_com_sync_await (volatile LONG *done)
{
	while (InterlockedCompareExchange (done, 0, 0) == 0) {
		vala_webview2_com_pump_messages ();
		Sleep (10);
	}
}
```

The wait has no timeout, so a missing or delayed callback blocks the GTK UI thread indefinitely. More importantly, this wait is unnecessary: `reload_bypass_cache()` returns `void`, and the `Page.reload` completion is only the DevTools command acknowledgement, not navigation completion.

The stall should not be attributed to the default GLib main context. The embedded proxy runs a private `GLib.MainContext` on its own thread, and WebView2's `BasicAuthenticationRequested` handler supplies the local-proxy credentials directly from its COM callback. Pumping the default context would therefore not address a demonstrated dependency.

## Fix

Applied.

Replace the synchronous reload handler in `lib/host/win32-ui-webview2-capture.c` with a heap-allocated COM completion handler and return as soon as WebView2 accepts the command:

```c
typedef struct {
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler handler;
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandlerVtbl vtbl;
	LONG ref_count;
	ICoreWebView2 *webview;
} ReloadHandler;

static HRESULT STDMETHODCALLTYPE
reload_qi (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This,
	REFIID riid,
	void **ppv)
{
	ReloadHandler *rh = CONTAINING_RECORD (
		This, ReloadHandler, handler);

	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2CallDevToolsProtocolMethodCompletedHandler)) {
		*ppv = This;
		InterlockedIncrement (&rh->ref_count);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
reload_addref (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This)
{
	ReloadHandler *rh = CONTAINING_RECORD (
		This, ReloadHandler, handler);
	return (ULONG) InterlockedIncrement (&rh->ref_count);
}

static ULONG STDMETHODCALLTYPE
reload_release (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This)
{
	ReloadHandler *rh = CONTAINING_RECORD (
		This, ReloadHandler, handler);
	LONG count = InterlockedDecrement (&rh->ref_count);

	if (count == 0) {
		ICoreWebView2_Release (rh->webview);
		CoTaskMemFree (rh);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE
reload_invoke (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This,
	HRESULT error_code,
	LPCWSTR return_object_as_json)
{
	ReloadHandler *rh = CONTAINING_RECORD (
		This, ReloadHandler, handler);

	(void) return_object_as_json;
	if (FAILED (error_code)) {
		ICoreWebView2_Reload (rh->webview);
	}
	return S_OK;
}

bool
vala_webview2_host_reload_bypass_cache (WebView2Host *host)
{
	ICoreWebView2 *webview;
	ReloadHandler *rh;
	HRESULT hr;

	webview = vala_webview2_com_get_webview_for (host);
	if (webview == NULL) {
		return false;
	}

	rh = (ReloadHandler *) CoTaskMemAlloc (sizeof (*rh));
	if (rh == NULL) {
		return SUCCEEDED (ICoreWebView2_Reload (webview));
	}
	ZeroMemory (rh, sizeof (*rh));
	rh->handler.lpVtbl = &rh->vtbl;
	rh->vtbl.QueryInterface = reload_qi;
	rh->vtbl.AddRef = reload_addref;
	rh->vtbl.Release = reload_release;
	rh->vtbl.Invoke = reload_invoke;
	rh->ref_count = 1;
	rh->webview = webview;
	ICoreWebView2_AddRef (rh->webview);

	hr = ICoreWebView2_CallDevToolsProtocolMethod (
		webview,
		L"Page.reload",
		L"{\"ignoreCache\":true}",
		&rh->handler);
	if (FAILED (hr)) {
		HRESULT reload_hr = ICoreWebView2_Reload (webview);
		reload_release (&rh->handler);
		return SUCCEEDED (reload_hr);
	}

	/* WebView2 owns its reference until completion. */
	reload_release (&rh->handler);
	return true;
}
```

Leave `DevToolsHandler`, `vala_webview2_host_capture_screenshot_sync`, and `vala_webview2_com_sync_await` unchanged. Navigation completion continues to be reported through the existing navigation events.

## Verification

`webview2gtk-add-cookie.exe --smoke-reload-bypass` reads the test page and upstream proxy from `WV2GTK_TEST_URI` and `WV2GTK_TEST_PROXY`; no site or proxy is stored in the repository.

```powershell
$env:WV2GTK_TEST_URI = Read-Host 'Test URI'
$env:WV2GTK_TEST_PROXY = Read-Host 'Upstream proxy URI'
& 'C:\msys64\tmp\webview2-gtk\portable-demos\webview2gtk-add-cookie.exe' --smoke-reload-bypass
```

Pass requires `FIRST_LOAD_FINISHED`, `RELOAD_RETURNED` within one second, `SECOND_LOAD_STARTED`, `SECOND_LOAD_FINISHED`, and `TEST_PASS`. Run the executable under an external timeout because the original synchronous bug blocks the GTK main context and therefore also blocks an in-process GLib timeout.

Windows runtime result through the embedded proxy's pass-through route:

```text
smoke-reload-bypass FIRST_LOAD_FINISHED
smoke-reload-bypass RELOAD_RETURNED elapsed_ms=0.1
smoke-reload-bypass SECOND_LOAD_STARTED
smoke-reload-bypass SECOND_LOAD_FINISHED
TEST_PASS
```

All existing add-cookie and proxy regression smokes also passed. The supplied external upstream could not be exercised because its hostname did not resolve on the Windows test machine; that attempt failed during the first navigation, before `reload_bypass_cache()`.

The changed C source compiles cleanly with the MinGW C11 compiler under `-Wall -Wextra -Werror`. The Vala smoke source compiles successfully; its one warning is a pre-existing unreachable catch at line 337.
