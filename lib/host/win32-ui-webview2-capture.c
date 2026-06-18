/* Sync Page.captureScreenshot via DevTools protocol — used by get_snapshot. */

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
	char *json;
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandler handler;
	ICoreWebView2CallDevToolsProtocolMethodCompletedHandlerVtbl vtbl;
} DevToolsHandler;

static HRESULT STDMETHODCALLTYPE devtools_qi (void *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2CallDevToolsProtocolMethodCompletedHandler)) {
		*ppv = This;
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE devtools_addref (void *This)
{
	(void) This;
	return 2;
}

static ULONG STDMETHODCALLTYPE devtools_release (void *This)
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

bool
vala_webview2_host_capture_screenshot_sync (bool full_document, char **devtools_json_out)
{
	ICoreWebView2 *webview;
	DevToolsHandler dh;
	const wchar_t *params;
	HRESULT hr;

	if (devtools_json_out != NULL) {
		*devtools_json_out = NULL;
	}
	webview = vala_webview2_com_get_webview ();
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
