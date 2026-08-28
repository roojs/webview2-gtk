/* Per-instance WebView2 COM glue (plan 4.0 / 4.1).
 * One shared ICoreWebView2Environment; N controllers (WebView2Host*). */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdbool.h>

#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-host-priv.h"
#include "win32-ui-webview2-loader.h"
#include "win32-ui-webview2-sdk.h"
#include "webview2gtk-host-api.h"

void vala_webview2_host_finish_setup (
	void *host,
	ICoreWebView2Controller *controller,
	ICoreWebView2 *webview,
	HWND parent);

/* struct WebView2Host is in win32-ui-webview2-host-priv.h */

static ICoreWebView2Environment *g_env;
static LONG g_env_refcount;
static LONG g_env_creating;
static WebView2Host *g_env_waiters[8];
static int g_env_waiter_count;
static WebView2Host *g_last_host;

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
		              SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
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
	WebView2Host *host;
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

static BOOL
create_controller_for_host (WebView2Host *host);

static HRESULT STDMETHODCALLTYPE controller_handler_invoke (
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This,
	HRESULT error_code,
	ICoreWebView2Controller *controller)
{
	ControllerCompletedHandler *self = (ControllerCompletedHandler *) This;
	WebView2Host *host = self->host;
	HRESULT hr;

	if (host == NULL) {
		return E_FAIL;
	}
	if (FAILED (error_code) || controller == NULL) {
		fprintf (stderr, "WebView2 controller failed: 0x%08lx\n", (unsigned long) error_code);
		return error_code;
	}

	host->controller = controller;
	ICoreWebView2Controller_AddRef (host->controller);
	hr = ICoreWebView2Controller_get_CoreWebView2 (host->controller, &host->webview);
	if (FAILED (hr) || host->webview == NULL) {
		fprintf (stderr, "get_CoreWebView2 failed: 0x%08lx\n", (unsigned long) hr);
		return hr;
	}

	{
		RECT bounds;
		if (host->use_client_bounds) {
			GetClientRect (host->parent, &bounds);
		} else {
			bounds = host->bounds;
		}
		hr = ICoreWebView2Controller_put_Bounds (host->controller, bounds);
		if (FAILED (hr)) {
			fprintf (stderr, "WebView2 put_Bounds failed: 0x%08lx\n", (unsigned long) hr);
		}
		vala_webview2_com_present_webview (host->parent);
	}
	if (host->url[0] != L'\0') {
		hr = ICoreWebView2_Navigate (host->webview, host->url);
		if (FAILED (hr)) {
			fprintf (stderr, "WebView2 Navigate failed: 0x%08lx\n", (unsigned long) hr);
		}
	}
	g_last_host = host;
	vala_webview2_host_finish_setup (host, host->controller, host->webview, host->parent);
	return S_OK;
}

static BOOL
create_controller_for_host (WebView2Host *host)
{
	ControllerCompletedHandler *controller_handler;
	HRESULT hr;

	if (host == NULL || g_env == NULL) {
		return FALSE;
	}

	controller_handler = (ControllerCompletedHandler *) CoTaskMemAlloc (sizeof (ControllerCompletedHandler));
	if (controller_handler == NULL) {
		return FALSE;
	}
	ZeroMemory (controller_handler, sizeof (*controller_handler));
	controller_handler->iface.lpVtbl = &controller_handler->vtbl;
	controller_handler->vtbl.QueryInterface = controller_handler_qi;
	controller_handler->vtbl.AddRef = controller_handler_addref;
	controller_handler->vtbl.Release = controller_handler_release;
	controller_handler->vtbl.Invoke = controller_handler_invoke;
	controller_handler->ref_count = 1;
	controller_handler->host = host;

	hr = ICoreWebView2Environment_CreateCoreWebView2Controller (
		g_env,
		host->parent,
		&controller_handler->iface);
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandler_Release (&controller_handler->iface);
	if (FAILED (hr)) {
		fprintf (stderr, "CreateCoreWebView2Controller failed: 0x%08lx\n", (unsigned long) hr);
		return FALSE;
	}
	return TRUE;
}

static HRESULT STDMETHODCALLTYPE env_handler_invoke (
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This,
	HRESULT error_code,
	ICoreWebView2Environment *environment)
{
	int i;

	(void) This;
	InterlockedExchange (&g_env_creating, 0);

	if (FAILED (error_code) || environment == NULL) {
		fprintf (stderr, "WebView2 environment failed: 0x%08lx\n", (unsigned long) error_code);
		g_env_waiter_count = 0;
		return error_code;
	}

	g_env = environment;
	ICoreWebView2Environment_AddRef (g_env);

	for (i = 0; i < g_env_waiter_count; i++) {
		WebView2Host *host = g_env_waiters[i];
		if (host == NULL) {
			continue;
		}
		InterlockedIncrement (&g_env_refcount);
		create_controller_for_host (host);
	}
	g_env_waiter_count = 0;
	return S_OK;
}

static BOOL
queue_host_for_env (WebView2Host *host)
{
	if (g_env_waiter_count >= (int) (sizeof (g_env_waiters) / sizeof (g_env_waiters[0]))) {
		fprintf (stderr, "WebView2: env waiter queue full\n");
		return FALSE;
	}
	g_env_waiters[g_env_waiter_count++] = host;
	return TRUE;
}

BOOL
vala_webview2_com_begin_host (WebView2Host *host, HWND parent, LPCWSTR url, const RECT *bounds)
{
	EnvCompletedHandler *env_handler;
	HRESULT hr;

	if (host == NULL || parent == NULL) {
		return FALSE;
	}

	ensure_parent_clip_styles (parent);

	host->parent = parent;
	host->use_client_bounds = (bounds == NULL);
	if (bounds != NULL) {
		host->bounds = *bounds;
	}
	host->host_visible = TRUE;
	host->url[0] = L'\0';
	if (url != NULL) {
		wcsncpy (host->url, url, (sizeof (host->url) / sizeof (host->url[0])) - 1);
		host->url[(sizeof (host->url) / sizeof (host->url[0])) - 1] = L'\0';
	}

	if (!vala_webview2_loader_init ()) {
		return FALSE;
	}

	if (g_env != NULL) {
		InterlockedIncrement (&g_env_refcount);
		return create_controller_for_host (host);
	}

	if (!queue_host_for_env (host)) {
		return FALSE;
	}

	if (InterlockedCompareExchange (&g_env_creating, 1, 0) != 0) {
		/* Another create is already creating the env; we are queued. */
		return TRUE;
	}

	env_handler = (EnvCompletedHandler *) CoTaskMemAlloc (sizeof (EnvCompletedHandler));
	if (env_handler == NULL) {
		InterlockedExchange (&g_env_creating, 0);
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
		InterlockedExchange (&g_env_creating, 0);
		g_env_waiter_count = 0;
		return FALSE;
	}
	return TRUE;
}

WebView2Host *
vala_webview2_host_create_with_xywh (void *parent_hwnd, int x, int y, int width, int height, uint16_t *url)
{
	WebView2Host *host;
	RECT bounds;

	if (parent_hwnd == NULL) {
		return NULL;
	}
	host = (WebView2Host *) CoTaskMemAlloc (sizeof (WebView2Host));
	if (host == NULL) {
		return NULL;
	}
	ZeroMemory (host, sizeof (*host));
	host->enable_media_stream = TRUE;
	host->enable_webrtc = TRUE;
	bounds.left = x;
	bounds.top = y;
	bounds.right = x + width;
	bounds.bottom = y + height;
	if (!vala_webview2_com_begin_host (host, (HWND) parent_hwnd, (LPCWSTR) url, &bounds)) {
		CoTaskMemFree (host);
		return NULL;
	}
	g_last_host = host;
	return host;
}

void
vala_webview2_host_set_bounds_xywh (WebView2Host *host, int x, int y, int width, int height)
{
	RECT bounds;

	if (host == NULL) {
		return;
	}
	bounds.left = x;
	bounds.top = y;
	bounds.right = x + width;
	bounds.bottom = y + height;
	host->bounds = bounds;
	host->use_client_bounds = FALSE;
	if (host->controller != NULL) {
		ICoreWebView2Controller_put_Bounds (host->controller, bounds);
		if (host->host_visible) {
			vala_webview2_com_present_webview (host->parent);
		}
		vala_webview2_host_note_visible_hwnd (host);
	}
}

bool
vala_webview2_host_navigate (WebView2Host *host, const char *url_utf8)
{
	wchar_t *wide;
	int wide_len = 0;
	HRESULT hr;

	if (host == NULL || url_utf8 == NULL || url_utf8[0] == '\0') {
		return false;
	}
	wide = (wchar_t *) win32_ui_utf8_to_utf16 (url_utf8, &wide_len);
	if (wide == NULL) {
		return false;
	}
	wcsncpy (host->pending_url, wide, (sizeof (host->pending_url) / sizeof (host->pending_url[0])) - 1);
	host->pending_url[(sizeof (host->pending_url) / sizeof (host->pending_url[0])) - 1] = L'\0';
	CoTaskMemFree (wide);

	if (host->ready && host->webview != NULL) {
		hr = ICoreWebView2_Navigate (host->webview, host->pending_url);
		host->pending_url[0] = L'\0';
		return SUCCEEDED (hr);
	}
	return true;
}

bool
vala_webview2_host_is_ready (WebView2Host *host)
{
	return host != NULL && host->ready && host->webview != NULL;
}

void
vala_webview2_host_set_ready (WebView2Host *host, bool ready)
{
	if (host != NULL) {
		host->ready = ready ? TRUE : FALSE;
	}
}

void
vala_webview2_host_set_visible_flag (WebView2Host *host, bool visible)
{
	if (host != NULL) {
		host->host_visible = visible ? TRUE : FALSE;
	}
}

void
vala_webview2_host_flush_pending_navigate (WebView2Host *host)
{
	HRESULT hr;

	if (host == NULL || !host->ready || host->webview == NULL || host->pending_url[0] == L'\0') {
		return;
	}
	hr = ICoreWebView2_Navigate (host->webview, host->pending_url);
	if (FAILED (hr)) {
		fprintf (stderr, "WebView2 pending navigate failed: 0x%08lx\n", (unsigned long) hr);
	}
	host->pending_url[0] = L'\0';
}

void
vala_webview2_host_set_cookie_apply (
	WebView2Host *host,
	void (*cb) (void *user_data),
	void *user_data)
{
	if (host == NULL) {
		return;
	}
	host->cb_cookie_apply = cb;
	host->cookie_apply_ctx = user_data;
}

void
vala_webview2_host_apply_pending_cookies (WebView2Host *host)
{
	if (host != NULL && host->cb_cookie_apply != NULL) {
		host->cb_cookie_apply (host->cookie_apply_ctx);
	}
}

ICoreWebView2 *
vala_webview2_com_get_webview_for (WebView2Host *host)
{
	if (host == NULL) {
		host = g_last_host;
	}
	return host != NULL ? host->webview : NULL;
}

ICoreWebView2 *
vala_webview2_com_get_webview (void)
{
	return vala_webview2_com_get_webview_for (g_last_host);
}

HWND
vala_webview2_com_get_parent_hwnd_for (WebView2Host *host)
{
	if (host == NULL) {
		host = g_last_host;
	}
	return host != NULL ? host->parent : NULL;
}

HWND
vala_webview2_com_get_parent_hwnd (void)
{
	return vala_webview2_com_get_parent_hwnd_for (g_last_host);
}

ICoreWebView2Environment *
vala_webview2_com_get_environment (void)
{
	return g_env;
}

ICoreWebView2Controller *
vala_webview2_com_get_controller_for (WebView2Host *host)
{
	if (host == NULL) {
		host = g_last_host;
	}
	return host != NULL ? host->controller : NULL;
}

void
vala_webview2_com_pump_messages (void)
{
	MSG msg;
	while (PeekMessageW (&msg, NULL, 0, 0, PM_REMOVE)) {
		TranslateMessage (&msg);
		DispatchMessageW (&msg);
	}
}

void
vala_webview2_com_sync_await (volatile LONG *done)
{
	while (InterlockedCompareExchange (done, 0, 0) == 0) {
		vala_webview2_com_pump_messages ();
		Sleep (10);
	}
}

void
vala_webview2_host_set_event_handlers (
	WebView2Host *host,
	WebView2GtkEventCb navigation_starting,
	WebView2GtkNavCompletedCb navigation_completed,
	WebView2GtkEventCb document_title_changed,
	void *user_data)
{
	if (host == NULL) {
		return;
	}
	host->cb_nav_starting = navigation_starting;
	host->cb_nav_completed = navigation_completed;
	host->cb_title_changed = document_title_changed;
	host->event_user_data = user_data;
}

void
vala_webview2_com_release_host (WebView2Host *host)
{
	LONG left;

	if (host == NULL) {
		return;
	}
	if (g_last_host == host) {
		g_last_host = NULL;
	}
	if (host->webview != NULL) {
		ICoreWebView2_Release (host->webview);
		host->webview = NULL;
	}
	if (host->controller != NULL) {
		ICoreWebView2Controller_Close (host->controller);
		ICoreWebView2Controller_Release (host->controller);
		host->controller = NULL;
	}
	host->ready = FALSE;

	left = InterlockedDecrement (&g_env_refcount);
	if (left <= 0 && g_env != NULL) {
		ICoreWebView2Environment_Release (g_env);
		g_env = NULL;
		g_env_refcount = 0;
	}
	CoTaskMemFree (host);
}

