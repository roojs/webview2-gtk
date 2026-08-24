/* PermissionRequested honour + IsMuted + media stream/webrtc flags.
 * Per WebView2Host (plan 4.3). */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-permissions.h"
#include "win32-ui-webview2-host-priv.h"
#include "win32-ui-webview2-sdk.h"

typedef struct {
	ICoreWebView2PermissionRequestedEventHandler iface;
	ICoreWebView2PermissionRequestedEventHandlerVtbl vtbl;
	LONG ref_count;
	WebView2Host *host;
} PermissionHandler;

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
	PermissionHandler *self = (PermissionHandler *) This;
	WebView2Host *host = self->host;
	COREWEBVIEW2_PERMISSION_KIND kind = COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION;
	BOOL allow = FALSE;
	int decided = 0;

	(void) sender;

	if (args == NULL || host == NULL) {
		return S_OK;
	}

	ICoreWebView2PermissionRequestedEventArgs_get_PermissionKind (args, &kind);

	if (host->cb_perm_decide != NULL) {
		int allow_i = 0;
		decided = host->cb_perm_decide ((int) kind, &allow_i, host->perm_ctx);
		allow = allow_i ? TRUE : FALSE;
	}

	if (!decided) {
		allow = FALSE;
		if (kind == COREWEBVIEW2_PERMISSION_KIND_MICROPHONE
		    || kind == COREWEBVIEW2_PERMISSION_KIND_CAMERA) {
			if (!host->enable_media_stream || !host->enable_webrtc) {
				allow = FALSE;
			}
		}
	}

	apply_state (args, allow);
	return S_OK;
}

static void
apply_muted_to_host (WebView2Host *host)
{
	ICoreWebView2_8 *wv8 = NULL;

	if (host == NULL || host->webview == NULL) {
		return;
	}
	if (FAILED (ICoreWebView2_QueryInterface (host->webview, &IID_ICoreWebView2_8,
	                                          (void **) &wv8))
	    || wv8 == NULL) {
		fprintf (stderr, "WebView2 ICoreWebView2_8 unavailable — mute ignored\n");
		return;
	}
	ICoreWebView2_8_put_IsMuted (wv8, host->is_muted ? TRUE : FALSE);
	ICoreWebView2_8_Release (wv8);
}

void
vala_webview2_host_set_media_flags (
	WebView2Host *host,
	bool enable_media_stream,
	bool enable_webrtc)
{
	if (host == NULL) {
		return;
	}
	host->enable_media_stream = enable_media_stream ? TRUE : FALSE;
	host->enable_webrtc = enable_webrtc ? TRUE : FALSE;
}

void
vala_webview2_host_set_permission_handler (
	WebView2Host *host,
	WebView2GtkPermissionDecideCb decide,
	void *user_data)
{
	if (host == NULL) {
		return;
	}
	host->cb_perm_decide = decide;
	host->perm_ctx = user_data;
}

bool
vala_webview2_host_set_is_muted (WebView2Host *host, bool muted)
{
	if (host == NULL) {
		return false;
	}
	host->is_muted = muted ? TRUE : FALSE;
	if (host->webview != NULL) {
		apply_muted_to_host (host);
	}
	return true;
}

bool
vala_webview2_host_get_is_muted (WebView2Host *host)
{
	ICoreWebView2_8 *wv8 = NULL;
	BOOL value = FALSE;

	if (host == NULL) {
		return false;
	}
	if (host->webview == NULL) {
		return host->is_muted ? true : false;
	}
	if (FAILED (ICoreWebView2_QueryInterface (host->webview, &IID_ICoreWebView2_8,
	                                          (void **) &wv8))
	    || wv8 == NULL) {
		return host->is_muted ? true : false;
	}
	if (SUCCEEDED (ICoreWebView2_8_get_IsMuted (wv8, &value))) {
		host->is_muted = value ? TRUE : FALSE;
	}
	ICoreWebView2_8_Release (wv8);
	return host->is_muted ? true : false;
}

void
vala_webview2_permissions_register_host (WebView2Host *host)
{
	ICoreWebView2 *webview;
	PermissionHandler *handler;
	HRESULT hr;

	if (host == NULL || host->webview == NULL || host->perm_registered) {
		return;
	}
	webview = host->webview;

	handler = (PermissionHandler *) CoTaskMemAlloc (sizeof (PermissionHandler));
	if (handler == NULL) {
		return;
	}
	ZeroMemory (handler, sizeof (*handler));
	handler->iface.lpVtbl = &handler->vtbl;
	handler->vtbl.QueryInterface = perm_qi;
	handler->vtbl.AddRef = perm_addref;
	handler->vtbl.Release = perm_release;
	handler->vtbl.Invoke = perm_invoke;
	handler->ref_count = 1;
	handler->host = host;

	hr = ICoreWebView2_add_PermissionRequested (
		webview, &handler->iface, &host->tok_perm);
	if (FAILED (hr)) {
		fprintf (stderr, "WebView2 add_PermissionRequested failed: 0x%08lx\n",
		         (unsigned long) hr);
		ICoreWebView2PermissionRequestedEventHandler_Release (&handler->iface);
		return;
	}
	ICoreWebView2PermissionRequestedEventHandler_Release (&handler->iface);
	host->perm_registered = TRUE;
	apply_muted_to_host (host);
}

void
vala_webview2_permissions_unregister_host (WebView2Host *host)
{
	if (host == NULL) {
		return;
	}
	if (host->webview != NULL && host->perm_registered) {
		ICoreWebView2_remove_PermissionRequested (host->webview, host->tok_perm);
		host->perm_registered = FALSE;
	}
	host->cb_perm_decide = NULL;
	host->perm_ctx = NULL;
}

void
vala_webview2_permissions_register (ICoreWebView2 *webview)
{
	(void) webview;
	fprintf (stderr, "WebView2: permissions_register(webview) obsolete; use *_host\n");
}

void
vala_webview2_permissions_unregister (ICoreWebView2 *webview)
{
	(void) webview;
}
