/* Sync ICoreWebView2CookieManager::GetCookies — used by CookieManager.get_cookies. */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

typedef struct {
	volatile LONG done;
	char *result;
	ICoreWebView2GetCookiesCompletedHandler handler;
	ICoreWebView2GetCookiesCompletedHandlerVtbl vtbl;
} CookiesHandler;

static HRESULT STDMETHODCALLTYPE cookies_qi (void *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2GetCookiesCompletedHandler)) {
		*ppv = This;
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE cookies_addref (void *This)
{
	(void) This;
	return 2;
}

static ULONG STDMETHODCALLTYPE cookies_release (void *This)
{
	(void) This;
	return 1;
}

static char *
take_wide_as_utf8 (LPWSTR wide)
{
	int len;
	char *utf8;

	if (wide == NULL) {
		return strdup ("");
	}
	len = 0;
	while (wide[len] != L'\0') {
		len++;
	}
	utf8 = win32_ui_utf16_to_utf8 ((uint16_t *) wide, len + 1);
	CoTaskMemFree (wide);
	return utf8 != NULL ? utf8 : strdup ("");
}

static bool
append_text (char **buf, size_t *len, size_t *cap, const char *text)
{
	size_t add;

	if (text == NULL) {
		return true;
	}
	add = strlen (text);
	if (*len + add + 1 > *cap) {
		size_t new_cap = (*cap == 0) ? 256 : *cap * 2;
		while (new_cap < *len + add + 1) {
			new_cap *= 2;
		}
		{
			char *next = realloc (*buf, new_cap);
			if (next == NULL) {
				return false;
			}
			*buf = next;
			*cap = new_cap;
		}
	}
	memcpy (*buf + *len, text, add);
	*len += add;
	(*buf)[*len] = '\0';
	return true;
}

static bool
append_cookie_line (
	char **buf,
	size_t *len,
	size_t *cap,
	ICoreWebView2Cookie *cookie)
{
	LPWSTR name = NULL;
	LPWSTR value = NULL;
	LPWSTR domain = NULL;
	LPWSTR path = NULL;
	char *name_u = NULL;
	char *value_u = NULL;
	char *domain_u = NULL;
	char *path_u = NULL;
	BOOL http_only = FALSE;
	BOOL secure = FALSE;
	bool ok = true;

	if (FAILED (ICoreWebView2Cookie_get_Name (cookie, &name))
	    || FAILED (ICoreWebView2Cookie_get_Value (cookie, &value))
	    || FAILED (ICoreWebView2Cookie_get_Domain (cookie, &domain))
	    || FAILED (ICoreWebView2Cookie_get_Path (cookie, &path))) {
		ok = false;
		goto out;
	}
	ICoreWebView2Cookie_get_IsHttpOnly (cookie, &http_only);
	ICoreWebView2Cookie_get_IsSecure (cookie, &secure);

	name_u = take_wide_as_utf8 (name);
	value_u = take_wide_as_utf8 (value);
	domain_u = take_wide_as_utf8 (domain);
	path_u = take_wide_as_utf8 (path);

	if (*len > 0) {
		ok = append_text (buf, len, cap, "\n");
	}
	ok = ok && append_text (buf, len, cap, name_u);
	ok = ok && append_text (buf, len, cap, "=");
	ok = ok && append_text (buf, len, cap, value_u);
	if (domain_u[0] != '\0') {
		ok = ok && append_text (buf, len, cap, "; Domain=");
		ok = ok && append_text (buf, len, cap, domain_u);
	}
	if (path_u[0] != '\0') {
		ok = ok && append_text (buf, len, cap, "; Path=");
		ok = ok && append_text (buf, len, cap, path_u);
	}
	if (http_only) {
		ok = ok && append_text (buf, len, cap, "; HttpOnly");
	}
	if (secure) {
		ok = ok && append_text (buf, len, cap, "; Secure");
	}

out:
	free (name_u);
	free (value_u);
	free (domain_u);
	free (path_u);
	return ok;
}

static HRESULT STDMETHODCALLTYPE cookies_invoke (
	ICoreWebView2GetCookiesCompletedHandler *This,
	HRESULT error_code,
	ICoreWebView2CookieList *cookie_list)
{
	CookiesHandler *ch = CONTAINING_RECORD (This, CookiesHandler, handler);
	UINT count = 0;
	UINT i;

	if (FAILED (error_code) || cookie_list == NULL) {
		InterlockedExchange (&ch->done, 1);
		return S_OK;
	}
	if (FAILED (ICoreWebView2CookieList_get_Count (cookie_list, &count))) {
		InterlockedExchange (&ch->done, 1);
		return S_OK;
	}
	for (i = 0; i < count; i++) {
		ICoreWebView2Cookie *cookie = NULL;
		size_t len = 0;
		size_t cap = 0;

		if (FAILED (ICoreWebView2CookieList_GetValueAtIndex (cookie_list, i, &cookie))
		    || cookie == NULL) {
			continue;
		}
		if (!append_cookie_line (&ch->result, &len, &cap, cookie)) {
			ICoreWebView2Cookie_Release (cookie);
			break;
		}
		ICoreWebView2Cookie_Release (cookie);
	}
	InterlockedExchange (&ch->done, 1);
	return S_OK;
}

bool
vala_webview2_host_get_cookies_sync (const char *uri_utf8, char **cookies_text_out)
{
	ICoreWebView2 *webview;
	ICoreWebView2_2 *webview2 = NULL;
	ICoreWebView2CookieManager *manager = NULL;
	uint16_t *uri_wide = NULL;
	CookiesHandler ch;
	HRESULT hr;
	bool ok = false;

	if (cookies_text_out != NULL) {
		*cookies_text_out = NULL;
	}
	webview = vala_webview2_com_get_webview ();
	if (webview == NULL || uri_utf8 == NULL || uri_utf8[0] == '\0') {
		return false;
	}
	hr = ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_2, (void **) &webview2);
	if (FAILED (hr) || webview2 == NULL) {
		return false;
	}
	hr = ICoreWebView2_2_get_CookieManager (webview2, &manager);
	ICoreWebView2_2_Release (webview2);
	if (FAILED (hr) || manager == NULL) {
		return false;
	}

	uri_wide = win32_ui_utf8_to_utf16 (uri_utf8, NULL);
	if (uri_wide == NULL) {
		ICoreWebView2CookieManager_Release (manager);
		return false;
	}

	ZeroMemory (&ch, sizeof (ch));
	ch.handler.lpVtbl = &ch.vtbl;
	ch.vtbl.QueryInterface = cookies_qi;
	ch.vtbl.AddRef = cookies_addref;
	ch.vtbl.Release = cookies_release;
	ch.vtbl.Invoke = cookies_invoke;

	hr = ICoreWebView2CookieManager_GetCookies (
		manager,
		(LPCWSTR) uri_wide,
		&ch.handler);
	free (uri_wide);
	ICoreWebView2CookieManager_Release (manager);
	if (FAILED (hr)) {
		return false;
	}

	vala_webview2_com_sync_await (&ch.done);

	if (cookies_text_out != NULL && ch.result != NULL) {
		*cookies_text_out = ch.result;
		ok = true;
	} else if (ch.result != NULL) {
		free (ch.result);
		ok = true;
	}
	return ok;
}
