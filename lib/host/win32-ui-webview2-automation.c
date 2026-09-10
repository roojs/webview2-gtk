/* WEBKIT_INSPECTOR_SERVER → WebView2 --remote-debugging-port. */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

#include "win32-ui-webview2-automation.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

static BOOL g_automation_allowed = FALSE;
/* 0=ALLOW, 1=ALLOW_WITHOUT_SOUND, 2=DENY — match WebView2Gtk.AutoplayPolicy */
static int g_autoplay_policy = 0;
/* 0=AUTO, 1=ENABLED, 2=DISABLED — match NavigatorWebDriverActivePolicy */
static int g_navigator_webdriver_policy = 0;
/* 0=DEFAULT, 1=CUSTOM, 2=NONE — match NetworkProxyMode */
static int g_proxy_mode = 0;
static char *g_proxy_uri = NULL;
static BOOL g_proxy_late_warned = FALSE;

void
vala_webview2_host_set_automation_allowed (bool allowed)
{
	g_automation_allowed = allowed ? TRUE : FALSE;
}

bool
vala_webview2_host_get_automation_allowed (void)
{
	return g_automation_allowed ? true : false;
}

void
vala_webview2_host_set_autoplay_policy (int policy)
{
	g_autoplay_policy = policy;
}

void
vala_webview2_host_set_navigator_webdriver_policy (int policy)
{
	g_navigator_webdriver_policy = policy;
}

bool
vala_webview2_host_environment_created (void)
{
	return vala_webview2_com_get_environment () != NULL;
}

void
vala_webview2_host_set_proxy_settings (int mode, const char *proxy_uri_utf8)
{
	if (vala_webview2_host_environment_created () && !g_proxy_late_warned) {
		g_proxy_late_warned = TRUE;
		fprintf (
			stderr,
			"webview2gtk: set_proxy_settings after env create — stored only; "
			"new WebView2 environment required for Chromium proxy flags\n"
		);
	}

	if (g_proxy_uri != NULL) {
		free (g_proxy_uri);
		g_proxy_uri = NULL;
	}

	if (mode == 1 && proxy_uri_utf8 != NULL && proxy_uri_utf8[0] != '\0') {
		/* CUSTOM */
		size_t n = strlen (proxy_uri_utf8) + 1;
		g_proxy_uri = (char *) malloc (n);
		if (g_proxy_uri != NULL) {
			memcpy (g_proxy_uri, proxy_uri_utf8, n);
		}
		g_proxy_mode = (g_proxy_uri != NULL) ? 1 : 0;
	} else if (mode == 2) {
		/* NONE */
		g_proxy_mode = 2;
	} else {
		/* DEFAULT, or CUSTOM without URI */
		g_proxy_mode = 0;
	}
}

/* --- ICoreWebView2EnvironmentOptions (minimal C implementation) --- */

typedef struct {
	ICoreWebView2EnvironmentOptions iface;
	ICoreWebView2EnvironmentOptionsVtbl vtbl;
	LONG ref_count;
	wchar_t *additional_args;
	wchar_t *language;
	wchar_t *target_version;
	BOOL allow_sso;
} EnvOptions;

static LPWSTR
dup_cotask_wstr (LPCWSTR src)
{
	size_t bytes;
	LPWSTR out;

	if (src == NULL) {
		return NULL;
	}
	bytes = (wcslen (src) + 1) * sizeof (wchar_t);
	out = (LPWSTR) CoTaskMemAlloc (bytes);
	if (out != NULL) {
		memcpy (out, src, bytes);
	}
	return out;
}

static HRESULT STDMETHODCALLTYPE
envopt_qi (ICoreWebView2EnvironmentOptions *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2EnvironmentOptions)) {
		*ppv = This;
		ICoreWebView2EnvironmentOptions_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
envopt_addref (ICoreWebView2EnvironmentOptions *This)
{
	EnvOptions *self = (EnvOptions *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE
envopt_release (ICoreWebView2EnvironmentOptions *This)
{
	EnvOptions *self = (EnvOptions *) This;
	LONG count = InterlockedDecrement (&self->ref_count);
	if (count == 0) {
		free (self->additional_args);
		free (self->language);
		free (self->target_version);
		CoTaskMemFree (self);
	}
	return (ULONG) count;
}

static HRESULT STDMETHODCALLTYPE
envopt_get_args (ICoreWebView2EnvironmentOptions *This, LPWSTR *value)
{
	EnvOptions *self = (EnvOptions *) This;
	if (value == NULL) {
		return E_POINTER;
	}
	*value = dup_cotask_wstr (self->additional_args);
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE
envopt_put_args (ICoreWebView2EnvironmentOptions *This, LPCWSTR value)
{
	EnvOptions *self = (EnvOptions *) This;
	free (self->additional_args);
	self->additional_args = NULL;
	if (value != NULL) {
		size_t n = wcslen (value) + 1;
		self->additional_args = (wchar_t *) malloc (n * sizeof (wchar_t));
		if (self->additional_args == NULL) {
			return E_OUTOFMEMORY;
		}
		memcpy (self->additional_args, value, n * sizeof (wchar_t));
	}
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE
envopt_get_lang (ICoreWebView2EnvironmentOptions *This, LPWSTR *value)
{
	EnvOptions *self = (EnvOptions *) This;
	if (value == NULL) {
		return E_POINTER;
	}
	*value = dup_cotask_wstr (self->language);
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE
envopt_put_lang (ICoreWebView2EnvironmentOptions *This, LPCWSTR value)
{
	EnvOptions *self = (EnvOptions *) This;
	free (self->language);
	self->language = NULL;
	if (value != NULL) {
		size_t n = wcslen (value) + 1;
		self->language = (wchar_t *) malloc (n * sizeof (wchar_t));
		if (self->language == NULL) {
			return E_OUTOFMEMORY;
		}
		memcpy (self->language, value, n * sizeof (wchar_t));
	}
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE
envopt_get_ver (ICoreWebView2EnvironmentOptions *This, LPWSTR *value)
{
	EnvOptions *self = (EnvOptions *) This;
	if (value == NULL) {
		return E_POINTER;
	}
	*value = dup_cotask_wstr (self->target_version);
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE
envopt_put_ver (ICoreWebView2EnvironmentOptions *This, LPCWSTR value)
{
	EnvOptions *self = (EnvOptions *) This;
	free (self->target_version);
	self->target_version = NULL;
	if (value != NULL) {
		size_t n = wcslen (value) + 1;
		self->target_version = (wchar_t *) malloc (n * sizeof (wchar_t));
		if (self->target_version == NULL) {
			return E_OUTOFMEMORY;
		}
		memcpy (self->target_version, value, n * sizeof (wchar_t));
	}
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE
envopt_get_sso (ICoreWebView2EnvironmentOptions *This, BOOL *allow)
{
	EnvOptions *self = (EnvOptions *) This;
	if (allow == NULL) {
		return E_POINTER;
	}
	*allow = self->allow_sso;
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE
envopt_put_sso (ICoreWebView2EnvironmentOptions *This, BOOL allow)
{
	EnvOptions *self = (EnvOptions *) This;
	self->allow_sso = allow;
	return S_OK;
}

static EnvOptions *
envopt_new (void)
{
	EnvOptions *self = (EnvOptions *) CoTaskMemAlloc (sizeof (EnvOptions));
	if (self == NULL) {
		return NULL;
	}
	ZeroMemory (self, sizeof (*self));
	self->iface.lpVtbl = &self->vtbl;
	self->vtbl.QueryInterface = envopt_qi;
	self->vtbl.AddRef = envopt_addref;
	self->vtbl.Release = envopt_release;
	self->vtbl.get_AdditionalBrowserArguments = envopt_get_args;
	self->vtbl.put_AdditionalBrowserArguments = envopt_put_args;
	self->vtbl.get_Language = envopt_get_lang;
	self->vtbl.put_Language = envopt_put_lang;
	self->vtbl.get_TargetCompatibleBrowserVersion = envopt_get_ver;
	self->vtbl.put_TargetCompatibleBrowserVersion = envopt_put_ver;
	self->vtbl.get_AllowSingleSignOnUsingOSPrimaryAccount = envopt_get_sso;
	self->vtbl.put_AllowSingleSignOnUsingOSPrimaryAccount = envopt_put_sso;
	self->ref_count = 1;
	/* Match Microsoft sample default floor. */
	envopt_put_ver (&self->iface, L"95.0.1020.44");
	return self;
}

/*
 * Parse WEBKIT_INSPECTOR_SERVER ("127.0.0.1:19222") → port.
 * Returns 0 if unset / invalid.
 */
static unsigned
parse_inspector_port (void)
{
	const char *env;
	const char *colon;
	unsigned port = 0;

	env = getenv ("WEBKIT_INSPECTOR_SERVER");
	if (env == NULL || env[0] == '\0') {
		return 0;
	}
	colon = strrchr (env, ':');
	if (colon != NULL && colon[1] != '\0') {
		port = (unsigned) strtoul (colon + 1, NULL, 10);
	} else {
		port = (unsigned) strtoul (env, NULL, 10);
	}
	if (port == 0 || port > 65535) {
		return 0;
	}
	return port;
}

ICoreWebView2EnvironmentOptions *
vala_webview2_host_create_environment_options (void)
{
	unsigned port;
	EnvOptions *opt;
	wchar_t args[768];
	size_t used = 0;
	size_t cap;
	BOOL need_deny;
	BOOL need_hide_webdriver;
	BOOL need_proxy_server;
	BOOL need_no_proxy;

	cap = sizeof (args) / sizeof (args[0]);
	port = parse_inspector_port ();
	need_deny = (g_autoplay_policy == 2); /* DENY */
	need_hide_webdriver = (g_navigator_webdriver_policy == 2); /* DISABLED */
	need_proxy_server = (g_proxy_mode == 1 && g_proxy_uri != NULL);
	need_no_proxy = (g_proxy_mode == 2); /* NONE */
	if (port == 0 && !need_deny && !need_hide_webdriver
	    && !need_proxy_server && !need_no_proxy) {
		return NULL;
	}

	opt = envopt_new ();
	if (opt == NULL) {
		return NULL;
	}

	args[0] = L'\0';
	if (port != 0) {
		/*
		 * WebKit twin: WEBKIT_INSPECTOR_SERVER host:port → CDP listen.
		 * --remote-allow-origins=* required for modern Chromium CDP clients.
		 */
		used = (size_t) _snwprintf (
			args,
			cap,
			L"--remote-debugging-port=%u --remote-allow-origins=*",
			port
		);
		if (used >= cap) {
			used = cap - 1;
		}
		args[used] = L'\0';
		fprintf (
			stderr,
			"webview2gtk: automation CDP listen --remote-debugging-port=%u (from WEBKIT_INSPECTOR_SERVER)\n",
			port
		);
	}
	if (need_deny) {
		if (used > 0 && used + 1 < cap) {
			args[used++] = L' ';
			args[used] = L'\0';
		}
		_snwprintf (
			args + used,
			cap - used,
			L"--autoplay-policy=user-gesture-required"
		);
		args[cap - 1] = L'\0';
		used = wcslen (args);
		fprintf (
			stderr,
			"webview2gtk: autoplay DENY (--autoplay-policy=user-gesture-required)\n"
		);
	}
	if (need_hide_webdriver) {
		if (used > 0 && used + 1 < cap) {
			args[used++] = L' ';
			args[used] = L'\0';
		}
		_snwprintf (
			args + used,
			cap - used,
			L"--disable-blink-features=AutomationControlled"
		);
		args[cap - 1] = L'\0';
		used = wcslen (args);
		fprintf (
			stderr,
			"webview2gtk: navigator.webdriver DISABLED (--disable-blink-features=AutomationControlled)\n"
		);
	}
	if (need_proxy_server) {
		wchar_t *uri_wide = (wchar_t *) win32_ui_utf8_to_utf16 (g_proxy_uri, NULL);
		if (uri_wide != NULL) {
			if (used > 0 && used + 1 < cap) {
				args[used++] = L' ';
				args[used] = L'\0';
			}
			_snwprintf (
				args + used,
				cap - used,
				L"--proxy-server=%s",
				uri_wide
			);
			args[cap - 1] = L'\0';
			used = wcslen (args);
			fprintf (
				stderr,
				"webview2gtk: proxy CUSTOM (--proxy-server=%s)\n",
				g_proxy_uri
			);
			free (uri_wide);
		}
	} else if (need_no_proxy) {
		if (used > 0 && used + 1 < cap) {
			args[used++] = L' ';
			args[used] = L'\0';
		}
		_snwprintf (
			args + used,
			cap - used,
			L"--no-proxy-server"
		);
		args[cap - 1] = L'\0';
		used = wcslen (args);
		fprintf (
			stderr,
			"webview2gtk: proxy NONE (--no-proxy-server)\n"
		);
	}
	(void) used;

	if (FAILED (envopt_put_args (&opt->iface, args))) {
		ICoreWebView2EnvironmentOptions_Release (&opt->iface);
		return NULL;
	}

	return &opt->iface;
}
