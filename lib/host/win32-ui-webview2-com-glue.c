/* Async COM completed handlers; host logic continues in Vala (Phase 7i). */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-loader.h"
#include "win32-ui-webview2-sdk.h"

void vala_webview2_host_finish_setup (
	ICoreWebView2Controller *controller,
	ICoreWebView2 *webview,
	HWND parent); /* WebView2.h included above */

typedef struct WebView2GlueState {
	HWND parent;
	wchar_t url[2048];
	BOOL use_client_bounds;
	RECT bounds;
	ICoreWebView2Environment *environment;
	ICoreWebView2Controller *controller;
	ICoreWebView2 *webview;
} WebView2GlueState;

static WebView2GlueState g_glue;

static void
ensure_parent_clip_styles (HWND parent)
{
	LONG style;

	if (parent == NULL) {
		return;
	}
	style = GetWindowLongW (parent, GWL_STYLE);
	if (style != 0) {
		SetWindowLongW (parent, GWL_STYLE,
		                style | WS_CLIPCHILDREN | WS_CLIPSIBLINGS);
	}
}

static BOOL CALLBACK
raise_webview_child_proc (HWND hwnd, LPARAM lparam)
{
	wchar_t cls[64];

	(void) lparam;
	if (GetClassNameW (hwnd, cls, 64) <= 0) {
		return TRUE;
	}
	if (wcsstr (cls, L"Chrome") != NULL || wcsstr (cls, L"WebView") != NULL) {
		SetWindowPos (hwnd, HWND_TOP, 0, 0, 0, 0,
		              SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
	}
	return TRUE;
}

void
vala_webview2_com_present_webview (HWND parent)
{
	if (parent == NULL) {
		return;
	}
	EnumChildWindows (parent, raise_webview_child_proc, 0);
}

typedef struct EnvCompletedHandler {
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler iface;
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl vtbl;
	LONG ref_count;
} EnvCompletedHandler;

typedef struct ControllerCompletedHandler {
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandler iface;
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl vtbl;
	LONG ref_count;
} ControllerCompletedHandler;

static HRESULT STDMETHODCALLTYPE env_handler_qi (
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This,
	REFIID riid,
	void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)) {
		*ppv = This;
		ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE env_handler_addref (
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This)
{
	EnvCompletedHandler *self = (EnvCompletedHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE env_handler_release (
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This)
{
	EnvCompletedHandler *self = (EnvCompletedHandler *) This;
	LONG count = InterlockedDecrement (&self->ref_count);
	if (count == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE controller_handler_qi (
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This,
	REFIID riid,
	void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2CreateCoreWebView2ControllerCompletedHandler)) {
		*ppv = This;
		ICoreWebView2CreateCoreWebView2ControllerCompletedHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE controller_handler_addref (
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This)
{
	ControllerCompletedHandler *self = (ControllerCompletedHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE controller_handler_release (
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This)
{
	ControllerCompletedHandler *self = (ControllerCompletedHandler *) This;
	LONG count = InterlockedDecrement (&self->ref_count);
	if (count == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE controller_handler_invoke (
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This,
	HRESULT error_code,
	ICoreWebView2Controller *controller)
{
	HRESULT hr;

	(void) This;
	if (FAILED (error_code) || controller == NULL) {
		fprintf (stderr, "WebView2 controller failed: 0x%08lx\n", (unsigned long) error_code);
		return error_code;
	}

	g_glue.controller = controller;
	ICoreWebView2Controller_AddRef (g_glue.controller);
	hr = ICoreWebView2Controller_get_CoreWebView2 (g_glue.controller, &g_glue.webview);
	if (FAILED (hr) || g_glue.webview == NULL) {
		fprintf (stderr, "get_CoreWebView2 failed: 0x%08lx\n", (unsigned long) hr);
		return hr;
	}

	{
		RECT bounds;
		if (g_glue.use_client_bounds) {
			GetClientRect (g_glue.parent, &bounds);
		} else {
			bounds = g_glue.bounds;
		}
		hr = ICoreWebView2Controller_put_Bounds (g_glue.controller, bounds);
		if (FAILED (hr)) {
			fprintf (stderr, "WebView2 put_Bounds failed: 0x%08lx\n", (unsigned long) hr);
		}
		vala_webview2_com_present_webview (g_glue.parent);
	}
	if (g_glue.url[0] != L'\0') {
		hr = ICoreWebView2_Navigate (g_glue.webview, g_glue.url);
		if (FAILED (hr)) {
			fprintf (stderr, "WebView2 Navigate failed: 0x%08lx (url=%ls)\n",
			         (unsigned long) hr, g_glue.url);
		}
	}
	vala_webview2_host_finish_setup (g_glue.controller, g_glue.webview, g_glue.parent);
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE env_handler_invoke (
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This,
	HRESULT error_code,
	ICoreWebView2Environment *environment)
{
	EnvCompletedHandler *self = (EnvCompletedHandler *) This;
	ControllerCompletedHandler *controller_handler;
	HRESULT hr;

	(void) self;
	if (FAILED (error_code) || environment == NULL) {
		fprintf (stderr, "WebView2 environment failed: 0x%08lx\n", (unsigned long) error_code);
		return error_code;
	}

	g_glue.environment = environment;
	ICoreWebView2Environment_AddRef (g_glue.environment);

	controller_handler = (ControllerCompletedHandler *) CoTaskMemAlloc (sizeof (ControllerCompletedHandler));
	if (controller_handler == NULL) {
		return E_OUTOFMEMORY;
	}
	ZeroMemory (controller_handler, sizeof (*controller_handler));
	controller_handler->iface.lpVtbl = &controller_handler->vtbl;
	controller_handler->vtbl.QueryInterface = controller_handler_qi;
	controller_handler->vtbl.AddRef = controller_handler_addref;
	controller_handler->vtbl.Release = controller_handler_release;
	controller_handler->vtbl.Invoke = controller_handler_invoke;
	controller_handler->ref_count = 1;

	hr = ICoreWebView2Environment_CreateCoreWebView2Controller (
		environment,
		g_glue.parent,
		&controller_handler->iface);
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandler_Release (&controller_handler->iface);
	return hr;
}

BOOL vala_webview2_com_begin_host (HWND parent, LPCWSTR url, const RECT *bounds)
{
	EnvCompletedHandler *env_handler;
	HRESULT hr;

	if (parent == NULL) {
		return FALSE;
	}

	ensure_parent_clip_styles (parent);

	ZeroMemory (&g_glue, sizeof (g_glue));
	g_glue.parent = parent;
	g_glue.use_client_bounds = (bounds == NULL);
	if (bounds != NULL) {
		g_glue.bounds = *bounds;
	}
	if (url != NULL) {
		wcsncpy (g_glue.url, url, (sizeof (g_glue.url) / sizeof (g_glue.url[0])) - 1);
		g_glue.url[(sizeof (g_glue.url) / sizeof (g_glue.url[0])) - 1] = L'\0';
	}

	if (!vala_webview2_loader_init ()) {
		return FALSE;
	}

	env_handler = (EnvCompletedHandler *) CoTaskMemAlloc (sizeof (EnvCompletedHandler));
	if (env_handler == NULL) {
		return FALSE;
	}
	ZeroMemory (env_handler, sizeof (*env_handler));
	env_handler->iface.lpVtbl = &env_handler->vtbl;
	env_handler->vtbl.QueryInterface = env_handler_qi;
	env_handler->vtbl.AddRef = env_handler_addref;
	env_handler->vtbl.Release = env_handler_release;
	env_handler->vtbl.Invoke = env_handler_invoke;
	env_handler->ref_count = 1;

	hr = vala_webview2_loader_create_environment (&env_handler->iface);
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler_Release (&env_handler->iface);
	if (FAILED (hr)) {
		fprintf (stderr, "CreateCoreWebView2EnvironmentWithOptions failed: 0x%08lx\n", (unsigned long) hr);
		return FALSE;
	}
	return TRUE;
}

void vala_webview2_com_release_host (void)
{
	if (g_glue.webview != NULL) {
		ICoreWebView2_Release (g_glue.webview);
		g_glue.webview = NULL;
	}
	if (g_glue.controller != NULL) {
		ICoreWebView2Controller_Close (g_glue.controller);
		ICoreWebView2Controller_Release (g_glue.controller);
		g_glue.controller = NULL;
	}
	if (g_glue.environment != NULL) {
		ICoreWebView2Environment_Release (g_glue.environment);
		g_glue.environment = NULL;
	}
}
