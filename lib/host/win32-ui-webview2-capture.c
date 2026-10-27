/* DevTools calls: synchronous Page.captureScreenshot and asynchronous Page.reload. */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

typedef struct {
	volatile LONG done;
	HRESULT error;
	char *json;
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler handler;
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandlerVtbl vtbl;
} DevToolsHandler;

typedef struct {
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler handler;
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandlerVtbl vtbl;
	LONG ref_count;
	ICoreWebView2 *webview;
} ReloadHandler;

static HRESULT STDMETHODCALLTYPE devtools_qi (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This,
	REFIID riid,
	void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2CallDevToolsProtocolMethodCompletedHandler)) {
		*ppv = This;
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE devtools_addref (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This)
{
	(void) This;
	return 2;
}

static ULONG STDMETHODCALLTYPE devtools_release (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This)
{
	(void) This;
	return 1;
}

static HRESULT STDMETHODCALLTYPE devtools_invoke (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This,
	HRESULT error_code,
	LPCWSTR return_object_as_json)
{
	DevToolsHandler *dh = CONTAINING_RECORD (This, DevToolsHandler, handler);
	dh->error = error_code;
	if (SUCCEEDED (error_code) && return_object_as_json != NULL) {
		int len = 0;
		while (return_object_as_json[len] != L'\0') {
			len++;
		}
		dh->json = win32_ui_utf16_to_utf8 (
			(uint16_t *) return_object_as_json, len + 1);
	}
	InterlockedExchange (&dh->done, 1);
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE reload_qi (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This,
	REFIID riid,
	void **ppv)
{
	ReloadHandler *rh = CONTAINING_RECORD (This, ReloadHandler, handler);

	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2CallDevToolsProtocolMethodCompletedHandler)) {
		*ppv = This;
		InterlockedIncrement (&rh->ref_count);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE reload_addref (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This)
{
	ReloadHandler *rh = CONTAINING_RECORD (This, ReloadHandler, handler);
	return (ULONG) InterlockedIncrement (&rh->ref_count);
}

static ULONG STDMETHODCALLTYPE reload_release (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This)
{
	ReloadHandler *rh = CONTAINING_RECORD (This, ReloadHandler, handler);
	LONG count = InterlockedDecrement (&rh->ref_count);

	if (count == 0) {
		ICoreWebView2_Release (rh->webview);
		CoTaskMemFree (rh);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE reload_invoke (
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler *This,
	HRESULT error_code,
	LPCWSTR return_object_as_json)
{
	ReloadHandler *rh = CONTAINING_RECORD (This, ReloadHandler, handler);

	(void) return_object_as_json;
	if (FAILED (error_code)) {
		ICoreWebView2_Reload (rh->webview);
	}
	return S_OK;
}

bool
vala_webview2_host_capture_screenshot_sync (WebView2Host *host, bool full_document, char **devtools_json_out)
{
	ICoreWebView2 *webview;
	DevToolsHandler dh;
	const wchar_t *params;
	HRESULT hr;

	if (devtools_json_out != NULL) {
		*devtools_json_out = NULL;
	}
	webview = vala_webview2_com_get_webview_for (host);
	if (webview == NULL) {
		return false;
	}

	ZeroMemory (&dh, sizeof (dh));
	dh.handler.lpVtbl = &dh.vtbl;
	dh.vtbl.QueryInterface = devtools_qi;
	dh.vtbl.AddRef = devtools_addref;
	dh.vtbl.Release = devtools_release;
	dh.vtbl.Invoke = devtools_invoke;

	params = full_document
	             ? L"{\"format\":\"png\",\"fromSurface\":true,\"captureBeyondViewport\":true}"
	             : L"{\"format\":\"png\",\"fromSurface\":true}";

	hr = ICoreWebView2_CallDevToolsProtocolMethod (
		webview, L"Page.captureScreenshot", params, &dh.handler);
	if (FAILED (hr)) {
		fprintf (stderr,
			"Page.captureScreenshot failed HRESULT=0x%08lx\n",
			(unsigned long) hr);
		return false;
	}

	vala_webview2_com_sync_await (&dh.done);

	if (dh.json == NULL) {
		fprintf (stderr, "Page.captureScreenshot: empty DevTools response\n");
		return false;
	}
	if (devtools_json_out != NULL) {
		*devtools_json_out = dh.json;
	} else {
		free (dh.json);
	}
	return true;
}

/* Shift-reload. Page.reload's completion is the CDP ack, not load-finished. */
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
		webview, L"Page.reload", L"{\"ignoreCache\":true}", &rh->handler);
	if (FAILED (hr)) {
		HRESULT reload_hr = ICoreWebView2_Reload (webview);
		reload_release (&rh->handler);
		return SUCCEEDED (reload_hr);
	}

	/* WebView2 owns its reference until completion. */
	reload_release (&rh->handler);
	return true;
}
