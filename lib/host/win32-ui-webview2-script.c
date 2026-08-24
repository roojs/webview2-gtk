/* Sync ICoreWebView2::ExecuteScript — used by evaluate_javascript. */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

typedef struct {
	volatile LONG done;
	char *result;
	ICoreWebView2ExecuteScriptCompletedHandler handler;
	ICoreWebView2ExecuteScriptCompletedHandlerVtbl vtbl;
} ScriptHandler;

static HRESULT STDMETHODCALLTYPE script_qi (void *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2ExecuteScriptCompletedHandler)) {
		*ppv = This;
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE script_addref (void *This)
{
	(void) This;
	return 2;
}

static ULONG STDMETHODCALLTYPE script_release (void *This)
{
	(void) This;
	return 1;
}

static HRESULT STDMETHODCALLTYPE script_invoke (
	ICoreWebView2ExecuteScriptCompletedHandler *This,
	HRESULT error_code,
	LPCWSTR result_object_as_json)
{
	ScriptHandler *sh = CONTAINING_RECORD (This, ScriptHandler, handler);
	if (SUCCEEDED (error_code) && result_object_as_json != NULL) {
		int len = 0;
		while (result_object_as_json[len] != L'\0') {
			len++;
		}
		sh->result = win32_ui_utf16_to_utf8 (
			(uint16_t *) result_object_as_json, len + 1);
	}
	InterlockedExchange (&sh->done, 1);
	return S_OK;
}

bool
vala_webview2_host_execute_script_sync (WebView2Host *host, const char *script_utf8, char **result_json_out)
{
	ICoreWebView2 *webview;
	uint16_t *script_wide;
	ScriptHandler sh;
	HRESULT hr;

	if (result_json_out != NULL) {
		*result_json_out = NULL;
	}
	webview = vala_webview2_com_get_webview_for (host);
	if (webview == NULL || script_utf8 == NULL || script_utf8[0] == '\0') {
		return false;
	}
	script_wide = win32_ui_utf8_to_utf16 (script_utf8, NULL);
	if (script_wide == NULL) {
		return false;
	}

	ZeroMemory (&sh, sizeof (sh));
	sh.handler.lpVtbl = &sh.vtbl;
	sh.vtbl.QueryInterface = script_qi;
	sh.vtbl.AddRef = script_addref;
	sh.vtbl.Release = script_release;
	sh.vtbl.Invoke = script_invoke;

	hr = ICoreWebView2_ExecuteScript (webview, (LPCWSTR) script_wide, &sh.handler);
	free (script_wide);
	if (FAILED (hr)) {
		return false;
	}

	vala_webview2_com_sync_await (&sh.done);

	if (result_json_out != NULL && sh.result != NULL) {
		*result_json_out = sh.result;
	} else if (sh.result != NULL) {
		free (sh.result);
	}
	return sh.result != NULL;
}
