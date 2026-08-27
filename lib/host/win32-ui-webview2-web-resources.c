/* Resource load lifecycle — per WebView2Host (plan 4.3). */

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
#include "win32-ui-webview2-host-priv.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

static wchar_t *g_accept_language = NULL;

typedef struct {
	ICoreWebView2WebResourceRequestedEventHandler iface;
	ICoreWebView2WebResourceRequestedEventHandlerVtbl vtbl;
	LONG ref_count;
	WebView2Host *host;
} RequestedHandler;

typedef struct {
	ICoreWebView2WebResourceResponseReceivedEventHandler iface;
	ICoreWebView2WebResourceResponseReceivedEventHandlerVtbl vtbl;
	LONG ref_count;
	WebView2Host *host;
} ResponseHandler;

/* Idle payload: uri non-NULL => started; uri NULL => finished. */
typedef struct {
	WebView2Host *host;
	int id;
	char *uri;
} ResourceIdle;

static volatile LONG g_next_id = 1;

static void
apply_accept_language (ICoreWebView2WebResourceRequest *request)
{
	ICoreWebView2HttpRequestHeaders *headers = NULL;

	if (request == NULL || g_accept_language == NULL || g_accept_language[0] == L'\0') {
		return;
	}
	if (FAILED (ICoreWebView2WebResourceRequest_get_Headers (request, &headers))
	    || headers == NULL) {
		return;
	}
	ICoreWebView2HttpRequestHeaders_SetHeader (
		headers, L"Accept-Language", g_accept_language);
	ICoreWebView2HttpRequestHeaders_Release (headers);
}

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
	WebView2Host *host = job->host;

	if (host != NULL) {
		if (job->uri != NULL) {
			if (host->cb_res_started != NULL) {
				host->cb_res_started (job->id, job->uri, host->res_ctx);
			}
			free (job->uri);
		} else if (host->cb_res_finished != NULL) {
			host->cb_res_finished (job->id, host->res_ctx);
		}
	} else {
		free (job->uri);
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
	RequestedHandler *self = (RequestedHandler *) This;
	WebView2Host *host = self->host;
	ICoreWebView2WebResourceRequest *request = NULL;
	char *uri = NULL;
	int slot = -1;
	int i;
	int id;

	(void) sender;
	if (args == NULL || host == NULL) {
		return S_OK;
	}
	if (FAILED (ICoreWebView2WebResourceRequestedEventArgs_get_Request (
		            args, &request))
	    || request == NULL) {
		return S_OK;
	}
	apply_accept_language (request);
	if (host->cb_res_started == NULL) {
		ICoreWebView2WebResourceRequest_Release (request);
		return S_OK;
	}
	uri = request_uri_utf8 (request);
	ICoreWebView2WebResourceRequest_Release (request);
	if (uri == NULL || uri[0] == '\0') {
		free (uri);
		return S_OK;
	}
	for (i = 0; i < WV2_MAX_PENDING_RESOURCES; i++) {
		if (host->pending_resources[i].uri == NULL) {
			slot = i;
			break;
		}
	}
	if (slot < 0) {
		free (uri);
		return S_OK;
	}
	id = (int) InterlockedIncrement (&g_next_id);
	host->pending_resources[slot].id = id;
	host->pending_resources[slot].uri = strdup (uri);
	{
		ResourceIdle *job = g_new0 (ResourceIdle, 1);
		job->host = host;
		job->id = id;
		job->uri = uri; /* ownership → idle */
		g_idle_add (resource_idle_cb, job);
	}
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
	ResponseHandler *self = (ResponseHandler *) This;
	WebView2Host *host = self->host;
	ICoreWebView2WebResourceRequest *request = NULL;
	char *uri = NULL;
	int i;
	int id;

	(void) sender;
	if (args == NULL || host == NULL || host->cb_res_finished == NULL) {
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
	for (i = 0; i < WV2_MAX_PENDING_RESOURCES; i++) {
		if (host->pending_resources[i].uri == NULL
		    || strcmp (host->pending_resources[i].uri, uri) != 0) {
			continue;
		}
		id = host->pending_resources[i].id;
		free (host->pending_resources[i].uri);
		host->pending_resources[i].uri = NULL;
		host->pending_resources[i].id = 0;
		free (uri);
		{
			ResourceIdle *job = g_new0 (ResourceIdle, 1);
			job->host = host;
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
	WebView2Host *host,
	WebView2GtkResourceStartedCb started,
	WebView2GtkResourceFinishedCb finished,
	WebView2GtkResourceFailedCb failed,
	void *user_data)
{
	if (host == NULL) {
		return;
	}
	host->cb_res_started = started;
	host->cb_res_finished = finished;
	host->cb_res_failed = failed;
	host->res_ctx = user_data;
}

void
vala_webview2_host_set_accept_language (const char *accept_language_utf8)
{
	if (g_accept_language != NULL) {
		CoTaskMemFree (g_accept_language);
		g_accept_language = NULL;
	}
	if (accept_language_utf8 == NULL || accept_language_utf8[0] == '\0') {
		return;
	}
	g_accept_language = (wchar_t *) win32_ui_utf8_to_utf16 (accept_language_utf8, NULL);
}

void
vala_webview2_web_resources_register_host (WebView2Host *host)
{
	ICoreWebView2 *webview;
	HRESULT hr;
	ICoreWebView2_2 *webview2 = NULL;
	static const WCHAR filter_uri[] = L"*";

	if (host == NULL || host->webview == NULL || host->resources_registered) {
		return;
	}
	webview = host->webview;

	if (!host->resource_filter_added) {
		hr = ICoreWebView2_AddWebResourceRequestedFilter (
			webview, filter_uri, COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
		if (FAILED (hr)) {
			fprintf (stderr,
			         "WebView2 AddWebResourceRequestedFilter failed: 0x%08lx\n",
			         (unsigned long) hr);
			return;
		}
		host->resource_filter_added = TRUE;
	}

	{
		RequestedHandler *handler = (RequestedHandler *) CoTaskMemAlloc (
			sizeof (RequestedHandler));
		if (handler != NULL) {
			ZeroMemory (handler, sizeof (*handler));
			handler->iface.lpVtbl = &handler->vtbl;
			handler->vtbl.QueryInterface = requested_qi;
			handler->vtbl.AddRef = requested_addref;
			handler->vtbl.Release = requested_release;
			handler->vtbl.Invoke = requested_invoke;
			handler->ref_count = 1;
			handler->host = host;
			hr = ICoreWebView2_add_WebResourceRequested (
				webview, &handler->iface, &host->tok_resource_requested);
			if (FAILED (hr)) {
				fprintf (stderr,
				         "WebView2 add_WebResourceRequested failed: 0x%08lx\n",
				         (unsigned long) hr);
				ICoreWebView2WebResourceRequestedEventHandler_Release (
					&handler->iface);
			} else {
				ICoreWebView2WebResourceRequestedEventHandler_Release (
					&handler->iface);
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

	{
		ResponseHandler *handler = (ResponseHandler *) CoTaskMemAlloc (
			sizeof (ResponseHandler));
		if (handler != NULL) {
			ZeroMemory (handler, sizeof (*handler));
			handler->iface.lpVtbl = &handler->vtbl;
			handler->vtbl.QueryInterface = response_qi;
			handler->vtbl.AddRef = response_addref;
			handler->vtbl.Release = response_release;
			handler->vtbl.Invoke = response_invoke;
			handler->ref_count = 1;
			handler->host = host;
			hr = ICoreWebView2_2_add_WebResourceResponseReceived (
				webview2, &handler->iface, &host->tok_resource_response);
			if (FAILED (hr)) {
				fprintf (stderr,
				         "WebView2 add_WebResourceResponseReceived (resources) "
				         "failed: 0x%08lx\n",
				         (unsigned long) hr);
				ICoreWebView2WebResourceResponseReceivedEventHandler_Release (
					&handler->iface);
			} else {
				ICoreWebView2WebResourceResponseReceivedEventHandler_Release (
					&handler->iface);
			}
		}
	}

	ICoreWebView2_2_Release (webview2);
	host->resources_registered = TRUE;
}

void
vala_webview2_web_resources_unregister_host (WebView2Host *host)
{
	ICoreWebView2 *webview;
	ICoreWebView2_2 *webview2 = NULL;
	int i;

	if (host == NULL) {
		return;
	}

	for (i = 0; i < WV2_MAX_PENDING_RESOURCES; i++) {
		if (host->pending_resources[i].uri == NULL) {
			continue;
		}
		if (host->cb_res_failed != NULL) {
			host->cb_res_failed (host->pending_resources[i].id,
			                     "WebView destroyed", host->res_ctx);
		}
		free (host->pending_resources[i].uri);
		host->pending_resources[i].uri = NULL;
		host->pending_resources[i].id = 0;
	}

	if (!host->resources_registered || host->webview == NULL) {
		return;
	}
	webview = host->webview;
	ICoreWebView2_remove_WebResourceRequested (webview, host->tok_resource_requested);
	if (host->resource_filter_added) {
		ICoreWebView2_RemoveWebResourceRequestedFilter (
			webview, L"*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
		host->resource_filter_added = FALSE;
	}
	if (SUCCEEDED (ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_2,
	                                              (void **) &webview2))
	    && webview2 != NULL) {
		ICoreWebView2_2_remove_WebResourceResponseReceived (
			webview2, host->tok_resource_response);
		ICoreWebView2_2_Release (webview2);
	}
	host->resources_registered = FALSE;
}

void
vala_webview2_web_resources_register (ICoreWebView2 *webview)
{
	(void) webview;
	fprintf (stderr, "WebView2: web_resources_register(webview) obsolete; use *_host\n");
}

void
vala_webview2_web_resources_unregister (ICoreWebView2 *webview)
{
	(void) webview;
}
