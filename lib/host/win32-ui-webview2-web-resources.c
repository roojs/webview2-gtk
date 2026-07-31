/* Resource load lifecycle — WebResourceRequested + WebResourceResponseReceived. */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include <glib.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-web-resources.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

#define MAX_PENDING 512

typedef struct {
	int id;
	char *uri;
} PendingResource;

typedef struct {
	ICoreWebView2WebResourceRequestedEventHandler iface;
	ICoreWebView2WebResourceRequestedEventHandlerVtbl vtbl;
	LONG ref_count;
} RequestedHandler;

typedef struct {
	ICoreWebView2WebResourceResponseReceivedEventHandler iface;
	ICoreWebView2WebResourceResponseReceivedEventHandlerVtbl vtbl;
	LONG ref_count;
} ResponseHandler;

/* Idle payload: uri non-NULL => started; uri NULL => finished. */
typedef struct {
	int id;
	char *uri;
} ResourceIdle;

static PendingResource g_pending[MAX_PENDING];
static volatile LONG g_next_id = 1;
static EventRegistrationToken g_requested_token;
static EventRegistrationToken g_response_token;
static BOOL g_requested_registered;
static BOOL g_response_registered;
static BOOL g_filter_added;
static RequestedHandler *g_requested_handler;
static ResponseHandler *g_response_handler;

static WebView2GtkResourceStartedCb g_started_cb;
static WebView2GtkResourceFinishedCb g_finished_cb;
static WebView2GtkResourceFailedCb g_failed_cb;
static void *g_cb_ctx;

static char *
request_uri_utf8 (ICoreWebView2WebResourceRequest *request)
{
	LPWSTR uri_w = NULL;
	char *uri;

	if (request == NULL) {
		return NULL;
	}
	if (FAILED (ICoreWebView2WebResourceRequest_get_Uri (request, &uri_w))
	    || uri_w == NULL) {
		return NULL;
	}
	uri = win32_ui_utf16_to_utf8 ((uint16_t *) uri_w, (int) wcslen (uri_w) + 1);
	CoTaskMemFree (uri_w);
	return uri;
}

/* Never call into Vala/GObject from WebResourceRequested — that deadlocks WebView2. */
static gboolean
resource_idle_cb (gpointer data)
{
	ResourceIdle *job = (ResourceIdle *) data;

	if (job->uri != NULL) {
		if (g_started_cb != NULL) {
			g_started_cb (job->id, job->uri, g_cb_ctx);
		}
		free (job->uri);
	} else if (g_finished_cb != NULL) {
		g_finished_cb (job->id, g_cb_ctx);
	}
	g_free (job);
	return G_SOURCE_REMOVE;
}

static HRESULT STDMETHODCALLTYPE requested_qi (
	ICoreWebView2WebResourceRequestedEventHandler *This,
	REFIID riid,
	void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2WebResourceRequestedEventHandler)) {
		*ppv = This;
		ICoreWebView2WebResourceRequestedEventHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE requested_addref (
	ICoreWebView2WebResourceRequestedEventHandler *This)
{
	RequestedHandler *self = (RequestedHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE requested_release (
	ICoreWebView2WebResourceRequestedEventHandler *This)
{
	RequestedHandler *self = (RequestedHandler *) This;
	LONG count = InterlockedDecrement (&self->ref_count);
	if (count == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE requested_invoke (
	ICoreWebView2WebResourceRequestedEventHandler *This,
	ICoreWebView2 *sender,
	ICoreWebView2WebResourceRequestedEventArgs *args)
{
	ICoreWebView2WebResourceRequest *request = NULL;
	char *uri = NULL;
	int slot = -1;
	int i;
	int id;

	(void) This;
	(void) sender;
	if (args == NULL || g_started_cb == NULL) {
		return S_OK;
	}
	if (FAILED (ICoreWebView2WebResourceRequestedEventArgs_get_Request (
		            args, &request))
	    || request == NULL) {
		return S_OK;
	}
	uri = request_uri_utf8 (request);
	ICoreWebView2WebResourceRequest_Release (request);
	if (uri == NULL || uri[0] == '\0') {
		free (uri);
		return S_OK;
	}
	for (i = 0; i < MAX_PENDING; i++) {
		if (g_pending[i].uri == NULL) {
			slot = i;
			break;
		}
	}
	if (slot < 0) {
		free (uri);
		return S_OK;
	}
	id = (int) InterlockedIncrement (&g_next_id);
	g_pending[slot].id = id;
	g_pending[slot].uri = strdup (uri);
	{
		ResourceIdle *job = g_new0 (ResourceIdle, 1);
		job->id = id;
		job->uri = uri; /* ownership → idle */
		g_idle_add (resource_idle_cb, job);
	}
	/* No custom response / deferral — request continues normally. */
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE response_qi (
	ICoreWebView2WebResourceResponseReceivedEventHandler *This,
	REFIID riid,
	void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2WebResourceResponseReceivedEventHandler)) {
		*ppv = This;
		ICoreWebView2WebResourceResponseReceivedEventHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE response_addref (
	ICoreWebView2WebResourceResponseReceivedEventHandler *This)
{
	ResponseHandler *self = (ResponseHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE response_release (
	ICoreWebView2WebResourceResponseReceivedEventHandler *This)
{
	ResponseHandler *self = (ResponseHandler *) This;
	LONG count = InterlockedDecrement (&self->ref_count);
	if (count == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE response_invoke (
	ICoreWebView2WebResourceResponseReceivedEventHandler *This,
	ICoreWebView2 *sender,
	ICoreWebView2WebResourceResponseReceivedEventArgs *args)
{
	ICoreWebView2WebResourceRequest *request = NULL;
	char *uri = NULL;
	int i;
	int id;

	(void) This;
	(void) sender;
	if (args == NULL || g_finished_cb == NULL) {
		return S_OK;
	}
	if (FAILED (ICoreWebView2WebResourceResponseReceivedEventArgs_get_Request (
		            args, &request))
	    || request == NULL) {
		return S_OK;
	}
	uri = request_uri_utf8 (request);
	ICoreWebView2WebResourceRequest_Release (request);
	if (uri == NULL) {
		return S_OK;
	}
	for (i = 0; i < MAX_PENDING; i++) {
		if (g_pending[i].uri == NULL || strcmp (g_pending[i].uri, uri) != 0) {
			continue;
		}
		id = g_pending[i].id;
		free (g_pending[i].uri);
		g_pending[i].uri = NULL;
		g_pending[i].id = 0;
		free (uri);
		{
			ResourceIdle *job = g_new0 (ResourceIdle, 1);
			job->id = id;
			g_idle_add (resource_idle_cb, job);
		}
		return S_OK;
	}
	free (uri);
	return S_OK;
}

void
vala_webview2_host_set_resource_handlers (
	WebView2GtkResourceStartedCb started,
	WebView2GtkResourceFinishedCb finished,
	WebView2GtkResourceFailedCb failed,
	void *user_data)
{
	g_started_cb = started;
	g_finished_cb = finished;
	g_failed_cb = failed;
	g_cb_ctx = user_data;
}

void
vala_webview2_web_resources_register (ICoreWebView2 *webview)
{
	HRESULT hr;
	ICoreWebView2_2 *webview2 = NULL;
	static const WCHAR filter_uri[] = L"*";

	if (webview == NULL) {
		return;
	}

	if (!g_filter_added) {
		hr = ICoreWebView2_AddWebResourceRequestedFilter (
			webview, filter_uri, COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
		if (FAILED (hr)) {
			fprintf (stderr,
			         "WebView2 AddWebResourceRequestedFilter failed: 0x%08lx\n",
			         (unsigned long) hr);
			return;
		}
		g_filter_added = TRUE;
	}

	if (!g_requested_registered) {
		g_requested_handler = (RequestedHandler *) CoTaskMemAlloc (
			sizeof (RequestedHandler));
		if (g_requested_handler != NULL) {
			ZeroMemory (g_requested_handler, sizeof (*g_requested_handler));
			g_requested_handler->iface.lpVtbl = &g_requested_handler->vtbl;
			g_requested_handler->vtbl.QueryInterface = requested_qi;
			g_requested_handler->vtbl.AddRef = requested_addref;
			g_requested_handler->vtbl.Release = requested_release;
			g_requested_handler->vtbl.Invoke = requested_invoke;
			g_requested_handler->ref_count = 1;
			hr = ICoreWebView2_add_WebResourceRequested (
				webview, &g_requested_handler->iface, &g_requested_token);
			if (SUCCEEDED (hr)) {
				g_requested_registered = TRUE;
			} else {
				fprintf (stderr,
				         "WebView2 add_WebResourceRequested failed: 0x%08lx\n",
				         (unsigned long) hr);
				ICoreWebView2WebResourceRequestedEventHandler_Release (
					&g_requested_handler->iface);
				g_requested_handler = NULL;
			}
		}
	}

	hr = ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_2,
	                                   (void **) &webview2);
	if (FAILED (hr) || webview2 == NULL) {
		fprintf (stderr,
		         "WebView2 QueryInterface ICoreWebView2_2 failed: 0x%08lx\n",
		         (unsigned long) hr);
		return;
	}

	if (!g_response_registered) {
		g_response_handler = (ResponseHandler *) CoTaskMemAlloc (
			sizeof (ResponseHandler));
		if (g_response_handler != NULL) {
			ZeroMemory (g_response_handler, sizeof (*g_response_handler));
			g_response_handler->iface.lpVtbl = &g_response_handler->vtbl;
			g_response_handler->vtbl.QueryInterface = response_qi;
			g_response_handler->vtbl.AddRef = response_addref;
			g_response_handler->vtbl.Release = response_release;
			g_response_handler->vtbl.Invoke = response_invoke;
			g_response_handler->ref_count = 1;
			hr = ICoreWebView2_2_add_WebResourceResponseReceived (
				webview2, &g_response_handler->iface, &g_response_token);
			if (SUCCEEDED (hr)) {
				g_response_registered = TRUE;
			} else {
				fprintf (stderr,
				         "WebView2 add_WebResourceResponseReceived (resources) "
				         "failed: 0x%08lx\n",
				         (unsigned long) hr);
				ICoreWebView2WebResourceResponseReceivedEventHandler_Release (
					&g_response_handler->iface);
				g_response_handler = NULL;
			}
		}
	}

	ICoreWebView2_2_Release (webview2);
}

void
vala_webview2_web_resources_unregister (ICoreWebView2 *webview)
{
	ICoreWebView2_2 *webview2 = NULL;
	int i;

	for (i = 0; i < MAX_PENDING; i++) {
		if (g_pending[i].uri == NULL) {
			continue;
		}
		if (g_failed_cb != NULL) {
			g_failed_cb (g_pending[i].id, "WebView destroyed", g_cb_ctx);
		}
		free (g_pending[i].uri);
		g_pending[i].uri = NULL;
		g_pending[i].id = 0;
	}

	if (webview == NULL) {
		return;
	}
	if (g_requested_registered) {
		ICoreWebView2_remove_WebResourceRequested (webview, g_requested_token);
		if (g_requested_handler != NULL) {
			ICoreWebView2WebResourceRequestedEventHandler_Release (
				&g_requested_handler->iface);
			g_requested_handler = NULL;
		}
		g_requested_registered = FALSE;
	}
	if (g_filter_added) {
		ICoreWebView2_RemoveWebResourceRequestedFilter (
			webview, L"*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
		g_filter_added = FALSE;
	}
	if (g_response_registered
	    && SUCCEEDED (ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_2,
	                                              (void **) &webview2))
	    && webview2 != NULL) {
		ICoreWebView2_2_remove_WebResourceResponseReceived (
			webview2, g_response_token);
		ICoreWebView2_2_Release (webview2);
		if (g_response_handler != NULL) {
			ICoreWebView2WebResourceResponseReceivedEventHandler_Release (
				&g_response_handler->iface);
			g_response_handler = NULL;
		}
		g_response_registered = FALSE;
	}
}
