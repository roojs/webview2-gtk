/* Main-frame document HTTP response — WebResourceResponseReceived + nav URI tracking. */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

typedef struct {
	wchar_t *uri;
	EventRegistrationToken nav_token;
	EventRegistrationToken response_token;
	BOOL nav_registered;
	BOOL response_registered;
} DocumentResponseState;

static DocumentResponseState g_doc_response;
static WebView2GtkDocumentResponseCb g_doc_response_cb;
static void *g_doc_response_ctx;

static void
clear_nav_uri (void)
{
	if (g_doc_response.uri != NULL) {
		CoTaskMemFree (g_doc_response.uri);
		g_doc_response.uri = NULL;
	}
}

static void
set_nav_uri (LPCWSTR uri)
{
	size_t len;

	clear_nav_uri ();
	if (uri == NULL || uri[0] == L'\0') {
		return;
	}
	len = wcslen (uri);
	g_doc_response.uri = (wchar_t *) CoTaskMemAlloc ((len + 1) * sizeof (wchar_t));
	if (g_doc_response.uri == NULL) {
		return;
	}
	memcpy (g_doc_response.uri, uri, (len + 1) * sizeof (wchar_t));
}

static bool
is_main_document_request (
	ICoreWebView2WebResourceRequest *request)
{
	LPWSTR req_uri = NULL;
	LPWSTR req_method = NULL;
	bool match = false;

	if (request == NULL || g_doc_response.uri == NULL) {
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
	    && wcscmp (req_uri, g_doc_response.uri) == 0) {
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

	if (g_doc_response_cb == NULL || headers == NULL) {
		return;
	}
	if (FAILED (ICoreWebView2HttpResponseHeaders_GetIterator (headers, &iter))
	    || iter == NULL) {
		g_doc_response_cb (g_doc_response_ctx, status, NULL, NULL, 0);
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
	g_doc_response_cb (g_doc_response_ctx, status,
	                   (const char **) names_out,
	                   (const char **) values_out, count);
	free_utf8_array (names_out, count);
	free_utf8_array (values_out, count);
}

typedef struct {
	ICoreWebView2NavigationStartingEventHandler iface;
	ICoreWebView2NavigationStartingEventHandlerVtbl vtbl;
	LONG ref_count;
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
	LPWSTR uri = NULL;

	(void) This;
	(void) sender;
	if (args != NULL
	    && SUCCEEDED (ICoreWebView2NavigationStartingEventArgs_get_Uri (args, &uri))) {
		set_nav_uri (uri);
		CoTaskMemFree (uri);
	}
	return S_OK;
}

typedef struct {
	ICoreWebView2WebResourceResponseReceivedEventHandler iface;
	ICoreWebView2WebResourceResponseReceivedEventHandlerVtbl vtbl;
	LONG ref_count;
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
	ICoreWebView2WebResourceRequest *request = NULL;
	ICoreWebView2WebResourceResponseView *response = NULL;
	int status = 0;
	ICoreWebView2HttpResponseHeaders *headers = NULL;

	(void) This;
	(void) sender;
	if (args == NULL || g_doc_response_cb == NULL) {
		return S_OK;
	}
	if (FAILED (ICoreWebView2WebResourceResponseReceivedEventArgs_get_Request (
		            args, &request))
	    || request == NULL) {
		return S_OK;
	}
	if (!is_main_document_request (request)) {
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
	emit_document_response (status, headers);
	if (headers != NULL) {
		ICoreWebView2HttpResponseHeaders_Release (headers);
	}
	ICoreWebView2WebResourceResponseView_Release (response);
	return S_OK;
}

static NavUriHandler *g_nav_uri_handler;
static ResponseReceivedHandler *g_response_handler;

void
vala_webview2_document_response_register (ICoreWebView2 *webview)
{
	HRESULT hr;
	ICoreWebView2_2 *webview2 = NULL;

	if (webview == NULL) {
		return;
	}
	hr = ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_2,
	                                   (void **) &webview2);
	if (FAILED (hr) || webview2 == NULL) {
		fprintf (stderr,
		         "WebView2 QueryInterface ICoreWebView2_2 failed: 0x%08lx\n",
		         (unsigned long) hr);
		return;
	}

	if (!g_doc_response.nav_registered) {
		g_nav_uri_handler = (NavUriHandler *) CoTaskMemAlloc (sizeof (NavUriHandler));
		if (g_nav_uri_handler != NULL) {
			ZeroMemory (g_nav_uri_handler, sizeof (*g_nav_uri_handler));
			g_nav_uri_handler->iface.lpVtbl = &g_nav_uri_handler->vtbl;
			g_nav_uri_handler->vtbl.QueryInterface = nav_uri_qi;
			g_nav_uri_handler->vtbl.AddRef = nav_uri_addref;
			g_nav_uri_handler->vtbl.Release = nav_uri_release;
			g_nav_uri_handler->vtbl.Invoke = nav_uri_invoke;
			g_nav_uri_handler->ref_count = 1;
			hr = ICoreWebView2_add_NavigationStarting (
				webview,
				& g_nav_uri_handler->iface,
				& g_doc_response.nav_token);
			if (SUCCEEDED (hr)) {
				g_doc_response.nav_registered = TRUE;
			} else {
				fprintf (stderr,
				         "WebView2 doc-response NavigationStarting failed: 0x%08lx\n",
				         (unsigned long) hr);
				ICoreWebView2NavigationStartingEventHandler_Release (
					&g_nav_uri_handler->iface);
				g_nav_uri_handler = NULL;
			}
		}
	}

	if (!g_doc_response.response_registered) {
		g_response_handler = (ResponseReceivedHandler *) CoTaskMemAlloc (
			sizeof (ResponseReceivedHandler));
		if (g_response_handler != NULL) {
			ZeroMemory (g_response_handler, sizeof (*g_response_handler));
			g_response_handler->iface.lpVtbl = &g_response_handler->vtbl;
			g_response_handler->vtbl.QueryInterface = response_qi;
			g_response_handler->vtbl.AddRef = response_addref;
			g_response_handler->vtbl.Release = response_release;
			g_response_handler->vtbl.Invoke = response_invoke;
			g_response_handler->ref_count = 1;
			hr = ICoreWebView2_2_add_WebResourceResponseReceived (
				webview2,
				&g_response_handler->iface,
				& g_doc_response.response_token);
			if (SUCCEEDED (hr)) {
				g_doc_response.response_registered = TRUE;
			} else {
				fprintf (stderr,
				         "WebView2 add_WebResourceResponseReceived failed: 0x%08lx\n",
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
vala_webview2_document_response_unregister (ICoreWebView2 *webview)
{
	ICoreWebView2_2 *webview2 = NULL;

	if (webview == NULL) {
		return;
	}
	if (g_doc_response.nav_registered) {
		ICoreWebView2_remove_NavigationStarting (webview, g_doc_response.nav_token);
		if (g_nav_uri_handler != NULL) {
			ICoreWebView2NavigationStartingEventHandler_Release (
				&g_nav_uri_handler->iface);
			g_nav_uri_handler = NULL;
		}
		g_doc_response.nav_registered = FALSE;
	}
	if (g_doc_response.response_registered
	    && SUCCEEDED (ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_2,
	                                              (void **) &webview2))
	    && webview2 != NULL) {
		ICoreWebView2_2_remove_WebResourceResponseReceived (
			webview2, g_doc_response.response_token);
		ICoreWebView2_2_Release (webview2);
		if (g_response_handler != NULL) {
			ICoreWebView2WebResourceResponseReceivedEventHandler_Release (
				&g_response_handler->iface);
			g_response_handler = NULL;
		}
		g_doc_response.response_registered = FALSE;
	}
	clear_nav_uri ();
}

void
vala_webview2_host_set_document_response_handler (
	WebView2GtkDocumentResponseCb handler,
	void *user_data)
{
	g_doc_response_cb = handler;
	g_doc_response_ctx = user_data;
}
