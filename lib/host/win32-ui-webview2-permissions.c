/* PermissionRequested honour + IsMuted + media stream/webrtc flags. */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-permissions.h"
#include "win32-ui-webview2-sdk.h"

typedef struct {
	ICoreWebView2PermissionRequestedEventHandler iface;
	ICoreWebView2PermissionRequestedEventHandlerVtbl vtbl;
	LONG ref_count;
} PermissionHandler;

static PermissionHandler *g_perm_handler;
static EventRegistrationToken g_perm_token;
static BOOL g_perm_registered;
static ICoreWebView2 *g_webview;

static BOOL g_enable_media_stream = TRUE;
static BOOL g_enable_webrtc = TRUE;
static BOOL g_is_muted = FALSE;

static WebView2GtkPermissionDecideCb g_decide_cb;
static void *g_decide_ctx;

static HRESULT STDMETHODCALLTYPE
perm_qi (ICoreWebView2PermissionRequestedEventHandler *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2PermissionRequestedEventHandler)) {
		*ppv = This;
		ICoreWebView2PermissionRequestedEventHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
perm_addref (ICoreWebView2PermissionRequestedEventHandler *This)
{
	PermissionHandler *self = (PermissionHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE
perm_release (ICoreWebView2PermissionRequestedEventHandler *This)
{
	PermissionHandler *self = (PermissionHandler *) This;
	LONG n = InterlockedDecrement (&self->ref_count);
	if (n == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) n;
}

static void
apply_state (ICoreWebView2PermissionRequestedEventArgs *args, BOOL allow)
{
	ICoreWebView2PermissionRequestedEventArgs2 *args2 = NULL;

	ICoreWebView2PermissionRequestedEventArgs_put_State (
		args,
		allow ? COREWEBVIEW2_PERMISSION_STATE_ALLOW
		      : COREWEBVIEW2_PERMISSION_STATE_DENY
	);
	if (SUCCEEDED (ICoreWebView2PermissionRequestedEventArgs_QueryInterface (
		    args, &IID_ICoreWebView2PermissionRequestedEventArgs2,
		    (void **) &args2))
	    && args2 != NULL) {
		ICoreWebView2PermissionRequestedEventArgs2_put_Handled (args2, TRUE);
		ICoreWebView2PermissionRequestedEventArgs2_Release (args2);
	}
}

static HRESULT STDMETHODCALLTYPE
perm_invoke (
	ICoreWebView2PermissionRequestedEventHandler *This,
	ICoreWebView2 *sender,
	ICoreWebView2PermissionRequestedEventArgs *args)
{
	COREWEBVIEW2_PERMISSION_KIND kind = COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION;
	BOOL allow = FALSE;
	int decided = 0;

	(void) This;
	(void) sender;

	if (args == NULL) {
		return S_OK;
	}

	ICoreWebView2PermissionRequestedEventArgs_get_PermissionKind (args, &kind);

	if (g_decide_cb != NULL) {
		int allow_i = 0;
		decided = g_decide_cb ((int) kind, &allow_i, g_decide_ctx);
		allow = allow_i ? TRUE : FALSE;
	}

	if (!decided) {
		allow = FALSE;
		if (kind == COREWEBVIEW2_PERMISSION_KIND_MICROPHONE
		    || kind == COREWEBVIEW2_PERMISSION_KIND_CAMERA) {
			if (!g_enable_media_stream || !g_enable_webrtc) {
				allow = FALSE;
			}
		}
	}

	apply_state (args, allow);
	return S_OK;
}

static void
apply_muted_to_webview (void)
{
	ICoreWebView2_8 *wv8 = NULL;

	if (g_webview == NULL) {
		return;
	}
	if (FAILED (ICoreWebView2_QueryInterface (g_webview, &IID_ICoreWebView2_8,
	                                          (void **) &wv8))
	    || wv8 == NULL) {
		fprintf (stderr, "WebView2 ICoreWebView2_8 unavailable — mute ignored\n");
		return;
	}
	ICoreWebView2_8_put_IsMuted (wv8, g_is_muted ? TRUE : FALSE);
	ICoreWebView2_8_Release (wv8);
}

void
vala_webview2_host_set_media_flags (bool enable_media_stream, bool enable_webrtc)
{
	g_enable_media_stream = enable_media_stream ? TRUE : FALSE;
	g_enable_webrtc = enable_webrtc ? TRUE : FALSE;
}

void
vala_webview2_host_set_permission_handler (
	WebView2GtkPermissionDecideCb decide,
	void *user_data)
{
	g_decide_cb = decide;
	g_decide_ctx = user_data;
}

bool
vala_webview2_host_set_is_muted (bool muted)
{
	g_is_muted = muted ? TRUE : FALSE;
	if (g_webview == NULL) {
		return true;
	}
	apply_muted_to_webview ();
	return true;
}

bool
vala_webview2_host_get_is_muted (void)
{
	ICoreWebView2_8 *wv8 = NULL;
	BOOL value = FALSE;

	if (g_webview == NULL) {
		return g_is_muted ? true : false;
	}
	if (FAILED (ICoreWebView2_QueryInterface (g_webview, &IID_ICoreWebView2_8,
	                                          (void **) &wv8))
	    || wv8 == NULL) {
		return g_is_muted ? true : false;
	}
	if (SUCCEEDED (ICoreWebView2_8_get_IsMuted (wv8, &value))) {
		g_is_muted = value ? TRUE : FALSE;
	}
	ICoreWebView2_8_Release (wv8);
	return g_is_muted ? true : false;
}

void
vala_webview2_permissions_register (ICoreWebView2 *webview)
{
	HRESULT hr;

	if (webview == NULL || g_perm_registered) {
		return;
	}

	g_webview = webview;
	ICoreWebView2_AddRef (g_webview);

	g_perm_handler = (PermissionHandler *) CoTaskMemAlloc (sizeof (PermissionHandler));
	if (g_perm_handler == NULL) {
		return;
	}
	ZeroMemory (g_perm_handler, sizeof (*g_perm_handler));
	g_perm_handler->iface.lpVtbl = &g_perm_handler->vtbl;
	g_perm_handler->vtbl.QueryInterface = perm_qi;
	g_perm_handler->vtbl.AddRef = perm_addref;
	g_perm_handler->vtbl.Release = perm_release;
	g_perm_handler->vtbl.Invoke = perm_invoke;
	g_perm_handler->ref_count = 1;

	hr = ICoreWebView2_add_PermissionRequested (
		webview, &g_perm_handler->iface, &g_perm_token);
	if (FAILED (hr)) {
		fprintf (stderr, "WebView2 add_PermissionRequested failed: 0x%08lx\n",
		         (unsigned long) hr);
		ICoreWebView2PermissionRequestedEventHandler_Release (&g_perm_handler->iface);
		g_perm_handler = NULL;
		return;
	}
	g_perm_registered = TRUE;
	apply_muted_to_webview ();
}

void
vala_webview2_permissions_unregister (ICoreWebView2 *webview)
{
	if (webview != NULL && g_perm_registered) {
		ICoreWebView2_remove_PermissionRequested (webview, g_perm_token);
		g_perm_registered = FALSE;
	}
	if (g_perm_handler != NULL) {
		ICoreWebView2PermissionRequestedEventHandler_Release (&g_perm_handler->iface);
		g_perm_handler = NULL;
	}
	if (g_webview != NULL) {
		ICoreWebView2_Release (g_webview);
		g_webview = NULL;
	}
	g_decide_cb = NULL;
	g_decide_ctx = NULL;
}
