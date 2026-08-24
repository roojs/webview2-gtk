/* WebKitGTK-shaped script message handlers via WebView2 web messages.
 * Per WebView2Host (plan 4.3).
 *
 * Page: window.webkit.messageHandlers.<name>.postMessage(value)
 * Host: WebMessageReceived → UTF-8 JSON body for Vala JavaScriptResult.
 */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <glib.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-script-messages.h"
#include "win32-ui-webview2-host-priv.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

#define SCRIPT_PREFIX \
	"(function(){" \
	"var names=["
#define SCRIPT_SUFFIX \
	"];" \
	"if(!window.webkit)window.webkit={};" \
	"if(!window.webkit.messageHandlers)window.webkit.messageHandlers={};" \
	"var i;" \
	"for(i=0;i<names.length;i++){(function(name){" \
	"if(window.webkit.messageHandlers[name])return;" \
	"window.webkit.messageHandlers[name]={postMessage:function(value){" \
	"if(!window.chrome||!window.chrome.webview)return;" \
	"var body;" \
	"try{body=JSON.stringify(value===undefined?null:value);}catch(e){body='null';}" \
	"window.chrome.webview.postMessage(name+'\\n'+body);" \
	"}};" \
	"})(names[i]);}" \
	"})();"

typedef struct {
	ICoreWebView2WebMessageReceivedEventHandler iface;
	ICoreWebView2WebMessageReceivedEventHandlerVtbl vtbl;
	LONG ref_count;
	WebView2Host *host;
} MessageHandler;

typedef struct {
	LONG ref_count;
	char *script_utf8;
	WebView2Host *host;
	ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler handler;
	ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandlerVtbl vtbl;
} AddScriptHandler;

typedef struct {
	WebView2Host *host;
	char *script;
} InjectIdle;

static HRESULT STDMETHODCALLTYPE
msg_qi (ICoreWebView2WebMessageReceivedEventHandler *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2WebMessageReceivedEventHandler)) {
		*ppv = This;
		ICoreWebView2WebMessageReceivedEventHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
msg_addref (ICoreWebView2WebMessageReceivedEventHandler *This)
{
	MessageHandler *self = (MessageHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE
msg_release (ICoreWebView2WebMessageReceivedEventHandler *This)
{
	MessageHandler *self = (MessageHandler *) This;
	LONG count = InterlockedDecrement (&self->ref_count);
	if (count == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE
msg_invoke (
	ICoreWebView2WebMessageReceivedEventHandler *This,
	ICoreWebView2 *sender,
	ICoreWebView2WebMessageReceivedEventArgs *args)
{
	MessageHandler *self = (MessageHandler *) This;
	WebView2Host *host = self->host;
	LPWSTR wide = NULL;
	char *utf8 = NULL;
	char *nl;
	size_t name_len;
	char *name;
	char *body;

	(void) sender;

	if (host == NULL || host->cb_script_msg == NULL || args == NULL) {
		return S_OK;
	}
	if (FAILED (ICoreWebView2WebMessageReceivedEventArgs_TryGetWebMessageAsString (
		    args, &wide))
	    || wide == NULL) {
		return S_OK;
	}
	utf8 = win32_ui_utf16_to_utf8 ((uint16_t *) wide, (int) wcslen (wide) + 1);
	CoTaskMemFree (wide);
	if (utf8 == NULL) {
		return S_OK;
	}
	nl = strchr (utf8, '\n');
	if (nl == NULL || nl == utf8) {
		free (utf8);
		return S_OK;
	}
	name_len = (size_t) (nl - utf8);
	name = (char *) malloc (name_len + 1);
	if (name == NULL) {
		free (utf8);
		return S_OK;
	}
	memcpy (name, utf8, name_len);
	name[name_len] = '\0';
	body = strdup (nl + 1);
	free (utf8);
	if (body == NULL) {
		free (name);
		return S_OK;
	}
	host->cb_script_msg (host->script_msg_ctx, name, body);
	free (name);
	free (body);
	return S_OK;
}

static void clear_script_id (WebView2Host *host);

static HRESULT STDMETHODCALLTYPE
add_script_qi (
	ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler *This,
	REFIID riid,
	void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid,
	                   &IID_ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler)) {
		*ppv = This;
		This->lpVtbl->AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
add_script_addref (ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler *This)
{
	AddScriptHandler *sh = CONTAINING_RECORD (This, AddScriptHandler, handler);
	return (ULONG) InterlockedIncrement (&sh->ref_count);
}

static ULONG STDMETHODCALLTYPE
add_script_release (ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler *This)
{
	AddScriptHandler *sh = CONTAINING_RECORD (This, AddScriptHandler, handler);
	LONG count = InterlockedDecrement (&sh->ref_count);
	if (count == 0) {
		free (sh->script_utf8);
		CoTaskMemFree (sh);
	}
	return (ULONG) count;
}

/* Never ExecuteScript-sync from a WebView2 completion — re-enters sync_await and hangs. */
static gboolean
inject_script_idle (gpointer data)
{
	InjectIdle *job = (InjectIdle *) data;
	ICoreWebView2 *wv;
	uint16_t *wide;

	wv = (job->host != NULL) ? job->host->webview : NULL;
	if (wv != NULL && job->script != NULL) {
		wide = win32_ui_utf8_to_utf16 (job->script, NULL);
		if (wide != NULL) {
			/* Fire-and-forget into this host's document (handler may be NULL). */
			ICoreWebView2_ExecuteScript (wv, (LPCWSTR) wide, NULL);
			free (wide);
		}
	}
	free (job->script);
	g_free (job);
	return G_SOURCE_REMOVE;
}

static HRESULT STDMETHODCALLTYPE
add_script_invoke (
	ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler *This,
	HRESULT error_code,
	LPCWSTR result)
{
	AddScriptHandler *sh = CONTAINING_RECORD (This, AddScriptHandler, handler);
	WebView2Host *host = sh->host;

	if (SUCCEEDED (error_code) && result != NULL && host != NULL) {
		size_t len = wcslen (result);
		wchar_t *id = (wchar_t *) CoTaskMemAlloc ((len + 1) * sizeof (wchar_t));
		if (id != NULL) {
			memcpy (id, result, (len + 1) * sizeof (wchar_t));
			if (host->script_inject_id != NULL) {
				CoTaskMemFree (host->script_inject_id);
			}
			host->script_inject_id = id;
		}
	}
	if (sh->script_utf8 != NULL) {
		InjectIdle *job = g_new0 (InjectIdle, 1);
		job->host = host;
		job->script = sh->script_utf8;
		sh->script_utf8 = NULL;
		g_idle_add (inject_script_idle, job);
	}
	return S_OK;
}

static char *
build_inject_script (WebView2Host *host)
{
	size_t i;
	size_t cap = sizeof (SCRIPT_PREFIX) + sizeof (SCRIPT_SUFFIX) + 64;
	char *out;
	size_t len = 0;

	if (host == NULL) {
		return NULL;
	}
	for (i = 0; i < host->script_handler_count; i++) {
		cap += strlen (host->script_handler_names[i]) * 2 + 8;
	}
	out = (char *) malloc (cap);
	if (out == NULL) {
		return NULL;
	}
	memcpy (out, SCRIPT_PREFIX, sizeof (SCRIPT_PREFIX) - 1);
	len = sizeof (SCRIPT_PREFIX) - 1;
	for (i = 0; i < host->script_handler_count; i++) {
		const char *n = host->script_handler_names[i];
		size_t nlen = strlen (n);
		if (i > 0) {
			out[len++] = ',';
		}
		out[len++] = '"';
		memcpy (out + len, n, nlen);
		len += nlen;
		out[len++] = '"';
	}
	memcpy (out + len, SCRIPT_SUFFIX, sizeof (SCRIPT_SUFFIX));
	return out;
}

static void
clear_script_id (WebView2Host *host)
{
	if (host == NULL || host->script_inject_id == NULL) {
		return;
	}
	if (host->webview != NULL) {
		ICoreWebView2_RemoveScriptToExecuteOnDocumentCreated (
			host->webview, host->script_inject_id);
	}
	CoTaskMemFree (host->script_inject_id);
	host->script_inject_id = NULL;
}

static bool
refresh_document_script (WebView2Host *host)
{
	ICoreWebView2 *webview;
	char *script_utf8;
	uint16_t *script_wide;
	AddScriptHandler *sh;
	HRESULT hr;

	if (host == NULL || host->webview == NULL) {
		return false;
	}
	webview = host->webview;
	clear_script_id (host);
	if (host->script_handler_count == 0) {
		return true;
	}
	script_utf8 = build_inject_script (host);
	if (script_utf8 == NULL) {
		return false;
	}
	script_wide = win32_ui_utf8_to_utf16 (script_utf8, NULL);
	if (script_wide == NULL) {
		free (script_utf8);
		return false;
	}

	/* Async only — sync_await here deadlocks when called from controller_invoke
	 * (finish_setup → script_messages_register). */
	sh = (AddScriptHandler *) CoTaskMemAlloc (sizeof (AddScriptHandler));
	if (sh == NULL) {
		free (script_wide);
		free (script_utf8);
		return false;
	}
	ZeroMemory (sh, sizeof (*sh));
	sh->handler.lpVtbl = &sh->vtbl;
	sh->vtbl.QueryInterface = add_script_qi;
	sh->vtbl.AddRef = add_script_addref;
	sh->vtbl.Release = add_script_release;
	sh->vtbl.Invoke = add_script_invoke;
	sh->ref_count = 1;
	sh->host = host;
	sh->script_utf8 = script_utf8; /* ownership → completion / idle */

	hr = ICoreWebView2_AddScriptToExecuteOnDocumentCreated (
		webview, (LPCWSTR) script_wide, &sh->handler);
	free (script_wide);
	if (FAILED (hr)) {
		free (sh->script_utf8);
		sh->script_utf8 = NULL;
		sh->handler.lpVtbl->Release (&sh->handler);
		return false;
	}
	sh->handler.lpVtbl->Release (&sh->handler);
	return true;
}

static int
find_handler_index (WebView2Host *host, const char *name)
{
	size_t i;

	if (host == NULL) {
		return -1;
	}
	for (i = 0; i < host->script_handler_count; i++) {
		if (strcmp (host->script_handler_names[i], name) == 0) {
			return (int) i;
		}
	}
	return -1;
}

void
vala_webview2_host_set_script_message_handler (
	WebView2Host *host,
	WebView2GtkScriptMessageCb handler,
	void *user_data)
{
	if (host == NULL) {
		return;
	}
	host->cb_script_msg = handler;
	host->script_msg_ctx = user_data;
}

static bool
name_is_safe (const char *name)
{
	const char *p;

	for (p = name; *p != '\0'; p++) {
		char c = *p;
		if ((c >= 'a' && c <= 'z')
		    || (c >= 'A' && c <= 'Z')
		    || (c >= '0' && c <= '9')
		    || c == '_' || c == '-') {
			continue;
		}
		return false;
	}
	return name[0] != '\0';
}

bool
vala_webview2_host_register_script_message_handler (
	WebView2Host *host,
	const char *name)
{
	char *copy;

	if (host == NULL || name == NULL || !name_is_safe (name)) {
		return false;
	}
	if (find_handler_index (host, name) >= 0) {
		return false;
	}
	if (host->script_handler_count >= WV2_MAX_SCRIPT_HANDLERS) {
		return false;
	}
	copy = strdup (name);
	if (copy == NULL) {
		return false;
	}
	host->script_handler_names[host->script_handler_count++] = copy;
	if (host->webview != NULL) {
		refresh_document_script (host);
	}
	return true;
}

bool
vala_webview2_host_unregister_script_message_handler (
	WebView2Host *host,
	const char *name)
{
	int idx;
	size_t i;

	if (host == NULL || name == NULL || name[0] == '\0') {
		return false;
	}
	idx = find_handler_index (host, name);
	if (idx < 0) {
		return false;
	}
	free (host->script_handler_names[idx]);
	for (i = (size_t) idx; i + 1 < host->script_handler_count; i++) {
		host->script_handler_names[i] = host->script_handler_names[i + 1];
	}
	host->script_handler_count--;
	host->script_handler_names[host->script_handler_count] = NULL;
	if (host->webview != NULL) {
		char *script;
		size_t need = strlen (name) + 128;
		uint16_t *wide;

		refresh_document_script (host);
		script = (char *) malloc (need);
		if (script != NULL) {
			snprintf (script, need,
			          "try{if(window.webkit&&window.webkit.messageHandlers)"
			          "delete window.webkit.messageHandlers[\"%s\"];}catch(e){}",
			          name);
			wide = win32_ui_utf8_to_utf16 (script, NULL);
			free (script);
			if (wide != NULL) {
				ICoreWebView2_ExecuteScript (host->webview, (LPCWSTR) wide, NULL);
				free (wide);
			}
		}
	}
	return true;
}

void
vala_webview2_script_messages_register_host (WebView2Host *host)
{
	ICoreWebView2 *webview;
	HRESULT hr;
	MessageHandler *handler;

	if (host == NULL || host->webview == NULL || host->script_msg_registered) {
		return;
	}
	webview = host->webview;
	handler = (MessageHandler *) CoTaskMemAlloc (sizeof (MessageHandler));
	if (handler == NULL) {
		return;
	}
	ZeroMemory (handler, sizeof (*handler));
	handler->iface.lpVtbl = &handler->vtbl;
	handler->vtbl.QueryInterface = msg_qi;
	handler->vtbl.AddRef = msg_addref;
	handler->vtbl.Release = msg_release;
	handler->vtbl.Invoke = msg_invoke;
	handler->ref_count = 1;
	handler->host = host;
	hr = ICoreWebView2_add_WebMessageReceived (
		webview, &handler->iface, &host->tok_script_msg);
	if (FAILED (hr)) {
		fprintf (stderr, "WebView2 add_WebMessageReceived failed: 0x%08lx\n",
		         (unsigned long) hr);
		ICoreWebView2WebMessageReceivedEventHandler_Release (&handler->iface);
		return;
	}
	ICoreWebView2WebMessageReceivedEventHandler_Release (&handler->iface);
	host->script_msg_registered = TRUE;
	if (host->script_handler_count > 0) {
		refresh_document_script (host);
	}
}

void
vala_webview2_script_messages_unregister_host (WebView2Host *host)
{
	size_t i;

	if (host == NULL) {
		return;
	}
	if (host->webview != NULL && host->script_msg_registered) {
		ICoreWebView2_remove_WebMessageReceived (host->webview, host->tok_script_msg);
		host->script_msg_registered = FALSE;
	}
	clear_script_id (host);
	for (i = 0; i < host->script_handler_count; i++) {
		free (host->script_handler_names[i]);
		host->script_handler_names[i] = NULL;
	}
	host->script_handler_count = 0;
}

void
vala_webview2_script_messages_register (ICoreWebView2 *webview)
{
	(void) webview;
	fprintf (stderr, "WebView2: script_messages_register(webview) obsolete; use *_host\n");
}

void
vala_webview2_script_messages_unregister (ICoreWebView2 *webview)
{
	(void) webview;
}
