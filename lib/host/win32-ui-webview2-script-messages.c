/* WebKitGTK-shaped script message handlers via WebView2 web messages.
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

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-script-messages.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

#define MAX_HANDLERS 64

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
} MessageHandler;

typedef struct {
	volatile LONG done;
	wchar_t *id;
	ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler handler;
	ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandlerVtbl vtbl;
} AddScriptHandler;

static char *g_handler_names[MAX_HANDLERS];
static size_t g_handler_count;
static EventRegistrationToken g_msg_token;
static BOOL g_msg_registered;
static MessageHandler *g_msg_handler;
static wchar_t *g_script_id;
static WebView2GtkScriptMessageCb g_cb;
static void *g_cb_ctx;

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
	LPWSTR wide = NULL;
	char *utf8 = NULL;
	char *nl;
	size_t name_len;
	char *name;
	char *body;

	(void) This;
	(void) sender;

	if (g_cb == NULL || args == NULL) {
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
	g_cb (g_cb_ctx, name, body);
	free (name);
	free (body);
	return S_OK;
}

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
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
add_script_addref (ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler *This)
{
	(void) This;
	return 2;
}

static ULONG STDMETHODCALLTYPE
add_script_release (ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler *This)
{
	(void) This;
	return 1;
}

static HRESULT STDMETHODCALLTYPE
add_script_invoke (
	ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler *This,
	HRESULT error_code,
	LPCWSTR result)
{
	AddScriptHandler *sh = CONTAINING_RECORD (This, AddScriptHandler, handler);
	if (SUCCEEDED (error_code) && result != NULL) {
		size_t len = wcslen (result);
		sh->id = (wchar_t *) CoTaskMemAlloc ((len + 1) * sizeof (wchar_t));
		if (sh->id != NULL) {
			memcpy (sh->id, result, (len + 1) * sizeof (wchar_t));
		}
	}
	InterlockedExchange (&sh->done, 1);
	return S_OK;
}

static char *
build_inject_script (void)
{
	size_t i;
	size_t cap = sizeof (SCRIPT_PREFIX) + sizeof (SCRIPT_SUFFIX) + 64;
	char *out;
	size_t len = 0;

	for (i = 0; i < g_handler_count; i++) {
		cap += strlen (g_handler_names[i]) * 2 + 8;
	}
	out = (char *) malloc (cap);
	if (out == NULL) {
		return NULL;
	}
	memcpy (out, SCRIPT_PREFIX, sizeof (SCRIPT_PREFIX) - 1);
	len = sizeof (SCRIPT_PREFIX) - 1;
	for (i = 0; i < g_handler_count; i++) {
		const char *n = g_handler_names[i];
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
clear_script_id (ICoreWebView2 *webview)
{
	if (g_script_id == NULL) {
		return;
	}
	if (webview != NULL) {
		ICoreWebView2_RemoveScriptToExecuteOnDocumentCreated (webview, g_script_id);
	}
	CoTaskMemFree (g_script_id);
	g_script_id = NULL;
}

static bool
refresh_document_script (ICoreWebView2 *webview)
{
	char *script_utf8;
	uint16_t *script_wide;
	AddScriptHandler sh;
	HRESULT hr;
	char *ignored = NULL;

	if (webview == NULL) {
		return false;
	}
	clear_script_id (webview);
	if (g_handler_count == 0) {
		return true;
	}
	script_utf8 = build_inject_script ();
	if (script_utf8 == NULL) {
		return false;
	}
	script_wide = win32_ui_utf8_to_utf16 (script_utf8, NULL);
	if (script_wide == NULL) {
		free (script_utf8);
		return false;
	}

	ZeroMemory (&sh, sizeof (sh));
	sh.handler.lpVtbl = &sh.vtbl;
	sh.vtbl.QueryInterface = add_script_qi;
	sh.vtbl.AddRef = add_script_addref;
	sh.vtbl.Release = add_script_release;
	sh.vtbl.Invoke = add_script_invoke;

	hr = ICoreWebView2_AddScriptToExecuteOnDocumentCreated (
		webview, (LPCWSTR) script_wide, &sh.handler);
	free (script_wide);
	if (FAILED (hr)) {
		free (script_utf8);
		return false;
	}
	vala_webview2_com_sync_await (&sh.done);
	g_script_id = sh.id;

	/* Run now so handlers work without a reload. */
	vala_webview2_host_execute_script_sync (script_utf8, &ignored);
	free (script_utf8);
	if (ignored != NULL) {
		free (ignored);
	}
	return true;
}

static int
find_handler_index (const char *name)
{
	size_t i;

	for (i = 0; i < g_handler_count; i++) {
		if (strcmp (g_handler_names[i], name) == 0) {
			return (int) i;
		}
	}
	return -1;
}

void
vala_webview2_host_set_script_message_handler (
	WebView2GtkScriptMessageCb handler,
	void *user_data)
{
	g_cb = handler;
	g_cb_ctx = user_data;
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
vala_webview2_host_register_script_message_handler (const char *name)
{
	ICoreWebView2 *webview;
	char *copy;

	if (name == NULL || !name_is_safe (name)) {
		return false;
	}
	if (find_handler_index (name) >= 0) {
		return false;
	}
	if (g_handler_count >= MAX_HANDLERS) {
		return false;
	}
	copy = strdup (name);
	if (copy == NULL) {
		return false;
	}
	g_handler_names[g_handler_count++] = copy;
	webview = vala_webview2_com_get_webview ();
	if (webview != NULL) {
		refresh_document_script (webview);
	}
	return true;
}

bool
vala_webview2_host_unregister_script_message_handler (const char *name)
{
	ICoreWebView2 *webview;
	int idx;
	size_t i;

	if (name == NULL || name[0] == '\0') {
		return false;
	}
	idx = find_handler_index (name);
	if (idx < 0) {
		return false;
	}
	free (g_handler_names[idx]);
	for (i = (size_t) idx; i + 1 < g_handler_count; i++) {
		g_handler_names[i] = g_handler_names[i + 1];
	}
	g_handler_count--;
	g_handler_names[g_handler_count] = NULL;
	webview = vala_webview2_com_get_webview ();
	if (webview != NULL) {
		char *ignored = NULL;
		char *script;
		size_t need = strlen (name) + 128;

		refresh_document_script (webview);
		script = (char *) malloc (need);
		if (script != NULL) {
			snprintf (script, need,
			          "try{if(window.webkit&&window.webkit.messageHandlers)"
			          "delete window.webkit.messageHandlers[\"%s\"];}catch(e){}",
			          name);
			vala_webview2_host_execute_script_sync (script, &ignored);
			free (script);
			if (ignored != NULL) {
				free (ignored);
			}
		}
	}
	return true;
}

void
vala_webview2_script_messages_register (ICoreWebView2 *webview)
{
	HRESULT hr;

	if (webview == NULL || g_msg_registered) {
		return;
	}
	g_msg_handler = (MessageHandler *) CoTaskMemAlloc (sizeof (MessageHandler));
	if (g_msg_handler == NULL) {
		return;
	}
	ZeroMemory (g_msg_handler, sizeof (*g_msg_handler));
	g_msg_handler->iface.lpVtbl = &g_msg_handler->vtbl;
	g_msg_handler->vtbl.QueryInterface = msg_qi;
	g_msg_handler->vtbl.AddRef = msg_addref;
	g_msg_handler->vtbl.Release = msg_release;
	g_msg_handler->vtbl.Invoke = msg_invoke;
	g_msg_handler->ref_count = 1;
	hr = ICoreWebView2_add_WebMessageReceived (
		webview, &g_msg_handler->iface, &g_msg_token);
	if (FAILED (hr)) {
		fprintf (stderr, "WebView2 add_WebMessageReceived failed: 0x%08lx\n",
		         (unsigned long) hr);
		ICoreWebView2WebMessageReceivedEventHandler_Release (&g_msg_handler->iface);
		g_msg_handler = NULL;
		return;
	}
	g_msg_registered = TRUE;
	if (g_handler_count > 0) {
		refresh_document_script (webview);
	}
}

void
vala_webview2_script_messages_unregister (ICoreWebView2 *webview)
{
	size_t i;

	if (webview != NULL && g_msg_registered) {
		ICoreWebView2_remove_WebMessageReceived (webview, g_msg_token);
		g_msg_registered = FALSE;
	}
	if (g_msg_handler != NULL) {
		ICoreWebView2WebMessageReceivedEventHandler_Release (&g_msg_handler->iface);
		g_msg_handler = NULL;
	}
	clear_script_id (webview);
	for (i = 0; i < g_handler_count; i++) {
		free (g_handler_names[i]);
		g_handler_names[i] = NULL;
	}
	g_handler_count = 0;
}
