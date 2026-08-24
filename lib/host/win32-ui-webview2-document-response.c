/* Main-frame document HTTP response — WebResourceResponseReceived + nav URI tracking.
 * Per WebView2Host (plan 4.3). */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-document-response.h"
#include "win32-ui-webview2-host-priv.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

static void
clear_nav_uri (WebView2Host *host)
{
	if (host == NULL) {
		return;
	}
	if (host->doc_nav_uri != NULL) {
		CoTaskMemFree (host->doc_nav_uri);
		host->doc_nav_uri = NULL;
	}
}

static void
set_nav_uri (WebView2Host *host, LPCWSTR uri)
{
	size_t len;

	if (host == NULL) {
		return;
	}
	clear_nav_uri (host);
	if (uri == NULL || uri[0] == L'\0') {
		return;
	}
	len = wcslen (uri);
	host->doc_nav_uri = (wchar_t *) CoTaskMemAlloc ((len + 1) * sizeof (wchar_t));
	if (host->doc_nav_uri == NULL) {
		return;
	}
	memcpy (host->doc_nav_uri, uri, (len + 1) * sizeof (wchar_t));
}

static bool
is_main_document_request (WebView2Host *host, ICoreWebView2WebResourceRequest *request)
{
	LPWSTR req_uri = NULL;
	LPWSTR req_method = NULL;
	bool match = false;

	if (host == NULL || request == NULL || host->doc_nav_uri == NULL) {
		return false;
	}
	if (FAILED (ICoreWebView2WebResourceRequest_get_Uri (request, &req_uri))
	    || req_uri == NULL) {
		return false;
	}
	if (FAILED (ICoreWebView2WebResourceRequest_get_Method (request, &req_method))
	    || req_method == NULL) {
		CoTaskMemFree (req_uri);
		return false;
	}
	if (wcscmp (req_method, L"GET") == 0
	    && wcscmp (req_uri, host->doc_nav_uri) == 0) {
		match = true;
	}
	CoTaskMemFree (req_uri);
	CoTaskMemFree (req_method);
	return match;
}

static char **
dup_utf8_array (const char **src, size_t count)
{
	char **out;
	size_t i;

	out = (char **) calloc (count + 1, sizeof (char *));
	if (out == NULL) {
		return NULL;
	}
	for (i = 0; i < count; i++) {
		out[i] = strdup (src[i] != NULL ? src[i] : "");
		if (out[i] == NULL) {
			while (i > 0) {
				i--;
				free (out[i]);
			}
			free (out);
			return NULL;
		}
	}
	return out;
}

static void
free_utf8_array (char **arr, size_t count)
{
	size_t i;

	if (arr == NULL) {
		return;
	}
	for (i = 0; i < count; i++) {
		free (arr[i]);
	}
	free (arr);
}

static void
emit_document_response (
	WebView2Host *host,
	int status,
	ICoreWebView2HttpResponseHeaders *headers)
{
	ICoreWebView2HttpHeadersCollectionIterator *iter = NULL;
	BOOL has_current = FALSE;
	BOOL has_next = FALSE;
	size_t count = 0;
	size_t cap = 0;
	char **names = NULL;
	char **values = NULL;
	char **names_out = NULL;
	char **values_out = NULL;

	if (host == NULL || host->cb_doc_response == NULL || headers == NULL) {
		return;
	}
	if (FAILED (ICoreWebView2HttpResponseHeaders_GetIterator (headers, &iter))
	    || iter == NULL) {
		host->cb_doc_response (host->doc_response_ctx, status, NULL, NULL, 0);
		return;
	}
	for (;;) {
		if (FAILED (ICoreWebView2HttpHeadersCollectionIterator_get_HasCurrentHeader (
			            iter, &has_current))
		    || !has_current) {
			break;
		}
		{
			LPWSTR wname = NULL;
			LPWSTR wvalue = NULL;
			char *name = NULL;
			char *value = NULL;

			if (FAILED (ICoreWebView2HttpHeadersCollectionIterator_GetCurrentHeader (
				            iter, &wname, &wvalue))) {
				break;
			}
			if (wname != NULL) {
				name = win32_ui_utf16_to_utf8 ((uint16_t *) wname,
				                               (int) wcslen (wname) + 1);
				CoTaskMemFree (wname);
			}
			if (wvalue != NULL) {
				value = win32_ui_utf16_to_utf8 ((uint16_t *) wvalue,
				                                (int) wcslen (wvalue) + 1);
				CoTaskMemFree (wvalue);
			}
			if (count + 1 > cap) {
				size_t new_cap = cap == 0 ? 8 : cap * 2;
				char **nn = (char **) realloc (names, new_cap * sizeof (char *));
				char **nv = (char **) realloc (values, new_cap * sizeof (char *));
				if (nn == NULL || nv == NULL) {
					free (name);
					free (value);
					free_utf8_array (names, count);
					free_utf8_array (values, count);
					ICoreWebView2HttpHeadersCollectionIterator_Release (iter);
					return;
				}
				names = nn;
				values = nv;
				cap = new_cap;
			}
			names[count] = name != NULL ? name : strdup ("");
			values[count] = value != NULL ? value : strdup ("");
			count++;
		}
		if (FAILED (ICoreWebView2HttpHeadersCollectionIterator_MoveNext (iter, &has_next))
		    || !has_next) {
			break;
		}
	}
	ICoreWebView2HttpHeadersCollectionIterator_Release (iter);

	names_out = dup_utf8_array ((const char **) names, count);
	values_out = dup_utf8_array ((const char **) values, count);
	free_utf8_array (names, count);
	free_utf8_array (values, count);
	if (names_out == NULL || values_out == NULL) {
		free_utf8_array (names_out, count);
		free_utf8_array (values_out, count);
		return;
	}
	host->cb_doc_response (host->doc_response_ctx, status,
	                       (const char **) names_out,
	                       (const char **) values_out, count);
	free_utf8_array (names_out, count);
	free_utf8_array (values_out, count);
}

typedef struct {
	ICoreWebView2NavigationStartingEventHandler iface;
	ICoreWebView2NavigationStartingEventHandlerVtbl vtbl;
	LONG ref_count;
	WebView2Host *host;
} NavUriHandler;

static HRESULT STDMETHODCALLTYPE nav_uri_qi (
	ICoreWebView2NavigationStartingEventHandler *This,
	REFIID riid,
	void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2NavigationStartingEventHandler)) {
		*ppv = This;
		ICoreWebView2NavigationStartingEventHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE nav_uri_addref (
	ICoreWebView2NavigationStartingEventHandler *This)
{
	NavUriHandler *self = (NavUriHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE nav_uri_release (
	ICoreWebView2NavigationStartingEventHandler *This)
{
	NavUriHandler *self = (NavUriHandler *) This;
	LONG count = InterlockedDecrement (&self->ref_count);
	if (count == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE nav_uri_invoke (
	ICoreWebView2NavigationStartingEventHandler *This,
	ICoreWebView2 *sender,
	ICoreWebView2NavigationStartingEventArgs *args)
{
	NavUriHandler *self = (NavUriHandler *) This;
	LPWSTR uri = NULL;

	(void) sender;
	if (args != NULL
	    && SUCCEEDED (ICoreWebView2NavigationStartingEventArgs_get_Uri (args, &uri))) {
		set_nav_uri (self->host, uri);
		CoTaskMemFree (uri);
	}
	return S_OK;
}

typedef struct {
	ICoreWebView2WebResourceResponseReceivedEventHandler iface;
	ICoreWebView2WebResourceResponseReceivedEventHandlerVtbl vtbl;
	LONG ref_count;
	WebView2Host *host;
} ResponseReceivedHandler;

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
	ResponseReceivedHandler *self = (ResponseReceivedHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE response_release (
	ICoreWebView2WebResourceResponseReceivedEventHandler *This)
{
	ResponseReceivedHandler *self = (ResponseReceivedHandler *) This;
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
	ResponseReceivedHandler *self = (ResponseReceivedHandler *) This;
	WebView2Host *host = self->host;
	ICoreWebView2WebResourceRequest *request = NULL;
	ICoreWebView2WebResourceResponseView *response = NULL;
	int status = 0;
	ICoreWebView2HttpResponseHeaders *headers = NULL;

	(void) sender;
	if (args == NULL || host == NULL || host->cb_doc_response == NULL) {
		return S_OK;
	}
	if (FAILED (ICoreWebView2WebResourceResponseReceivedEventArgs_get_Request (
		            args, &request))
	    || request == NULL) {
		return S_OK;
	}
	if (!is_main_document_request (host, request)) {
		ICoreWebView2WebResourceRequest_Release (request);
		return S_OK;
	}
	ICoreWebView2WebResourceRequest_Release (request);
	if (FAILED (ICoreWebView2WebResourceResponseReceivedEventArgs_get_Response (
		            args, &response))
	    || response == NULL) {
		return S_OK;
	}
	if (FAILED (ICoreWebView2WebResourceResponseView_get_StatusCode (response, &status))) {
		status = 0;
	}
	if (FAILED (ICoreWebView2WebResourceResponseView_get_Headers (response, &headers))) {
		headers = NULL;
	}
	emit_document_response (host, status, headers);
	if (headers != NULL) {
		ICoreWebView2HttpResponseHeaders_Release (headers);
	}
	ICoreWebView2WebResourceResponseView_Release (response);
	return S_OK;
}

void
vala_webview2_document_response_register_host (WebView2Host *host)
{
	ICoreWebView2 *webview;
	HRESULT hr;
	ICoreWebView2_2 *webview2 = NULL;

	if (host == NULL || host->webview == NULL || host->doc_response_registered) {
		return;
	}
	webview = host->webview;

	hr = ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_2,
	                                   (void **) &webview2);
	if (FAILED (hr) || webview2 == NULL) {
		fprintf (stderr,
		         "WebView2 QueryInterface ICoreWebView2_2 failed: 0x%08lx\n",
		         (unsigned long) hr);
		return;
	}

	{
		NavUriHandler *handler = (NavUriHandler *) CoTaskMemAlloc (sizeof (NavUriHandler));
		if (handler != NULL) {
			ZeroMemory (handler, sizeof (*handler));
			handler->iface.lpVtbl = &handler->vtbl;
			handler->vtbl.QueryInterface = nav_uri_qi;
			handler->vtbl.AddRef = nav_uri_addref;
			handler->vtbl.Release = nav_uri_release;
			handler->vtbl.Invoke = nav_uri_invoke;
			handler->ref_count = 1;
			handler->host = host;
			hr = ICoreWebView2_add_NavigationStarting (
				webview, &handler->iface, &host->tok_doc_nav);
			if (FAILED (hr)) {
				fprintf (stderr,
				         "WebView2 doc-response NavigationStarting failed: 0x%08lx\n",
				         (unsigned long) hr);
				ICoreWebView2NavigationStartingEventHandler_Release (&handler->iface);
			} else {
				ICoreWebView2NavigationStartingEventHandler_Release (&handler->iface);
			}
		}
	}

	{
		ResponseReceivedHandler *handler = (ResponseReceivedHandler *) CoTaskMemAlloc (
			sizeof (ResponseReceivedHandler));
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
				webview2, &handler->iface, &host->tok_doc_response);
			if (FAILED (hr)) {
				fprintf (stderr,
				         "WebView2 add_WebResourceResponseReceived failed: 0x%08lx\n",
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
	host->doc_response_registered = TRUE;
}

void
vala_webview2_document_response_unregister_host (WebView2Host *host)
{
	ICoreWebView2 *webview;
	ICoreWebView2_2 *webview2 = NULL;

	if (host == NULL || !host->doc_response_registered || host->webview == NULL) {
		return;
	}
	webview = host->webview;
	ICoreWebView2_remove_NavigationStarting (webview, host->tok_doc_nav);
	if (SUCCEEDED (ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_2,
	                                              (void **) &webview2))
	    && webview2 != NULL) {
		ICoreWebView2_2_remove_WebResourceResponseReceived (
			webview2, host->tok_doc_response);
		ICoreWebView2_2_Release (webview2);
	}
	clear_nav_uri (host);
	host->doc_response_registered = FALSE;
}

void
vala_webview2_host_set_document_response_handler (
	WebView2Host *host,
	WebView2GtkDocumentResponseCb handler,
	void *user_data)
{
	if (host == NULL) {
		return;
	}
	host->cb_doc_response = handler;
	host->doc_response_ctx = user_data;
}

/* Legacy — no-ops. */
void
vala_webview2_document_response_register (ICoreWebView2 *webview)
{
	(void) webview;
	fprintf (stderr, "WebView2: document_response_register(webview) obsolete; use *_host\n");
}

void
vala_webview2_document_response_unregister (ICoreWebView2 *webview)
{
	(void) webview;
}
