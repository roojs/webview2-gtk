/* Diagnose a11y Invoke — evidence log, not guesses. */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

#include "win32-ui-webview2-a11y-diag.h"
#include "win32-ui-webview2-sdk.h"

static FILE *g_diag;
static BOOL g_nw_registered;
static BOOL g_nav_registered;
static EventRegistrationToken g_nw_token;
static EventRegistrationToken g_nav_token;
static int g_diag_enabled = -1; /* -1 unset, 0 off, 1 on */

int
vala_webview2_a11y_diag_enabled (void)
{
#if !WEBVIEW2GTK_A11Y_DIAG_COMPILE
	return 0;
#else
	const char *e;

	if (g_diag_enabled >= 0) {
		return g_diag_enabled;
	}
	e = getenv ("WEBVIEW2GTK_A11Y_DIAG");
	g_diag_enabled = 0;
	if (e != NULL
	    && (strcmp (e, "1") == 0
	        || _stricmp (e, "true") == 0
	        || _stricmp (e, "yes") == 0
	        || _stricmp (e, "on") == 0)) {
		g_diag_enabled = 1;
	}
	return g_diag_enabled;
#endif
}

static void
diag_open (void)
{
	char path[MAX_PATH];
	DWORD n;

	if (!vala_webview2_a11y_diag_enabled ()) {
		return;
	}
	if (g_diag != NULL) {
		return;
	}
	n = GetTempPathA (MAX_PATH, path);
	if (n == 0 || n >= MAX_PATH) {
		g_diag = fopen ("webview2gtk-a11y-diag.txt", "ab");
		return;
	}
	strncat (path, "webview2gtk-a11y-diag.txt", MAX_PATH - strlen (path) - 1);
	g_diag = fopen (path, "ab");
	if (g_diag != NULL) {
		fprintf (g_diag, "\n======== diag session ========\n");
		fflush (g_diag);
	}
}

void
vala_webview2_a11y_diag_log (const char *fmt, ...)
{
	SYSTEMTIME st;
	va_list ap;

	if (!vala_webview2_a11y_diag_enabled ()) {
		return;
	}
	diag_open ();
	if (g_diag == NULL) {
		return;
	}
	GetLocalTime (&st);
	fprintf (g_diag, "%02u:%02u:%02u.%03u ",
	         (unsigned) st.wHour, (unsigned) st.wMinute,
	         (unsigned) st.wSecond, (unsigned) st.wMilliseconds);
	va_start (ap, fmt);
	vfprintf (g_diag, fmt, ap);
	va_end (ap);
	fputc ('\n', g_diag);
	fflush (g_diag);
}

/* Snapshot visible top-level windows — detect OS popups even if WebView2 is silent. */

#define DIAG_HWND_CAP 256

typedef struct {
	HWND list[DIAG_HWND_CAP];
	int count;
} HwndSnap;

static HwndSnap g_hwnd_before;

static BOOL CALLBACK
enum_visible_toplevel (HWND hwnd, LPARAM lp)
{
	HwndSnap *snap = (HwndSnap *) lp;

	if (!IsWindowVisible (hwnd)) {
		return TRUE;
	}
	/* Include owned popups — WebView2/Edge may use owned top-level windows. */
	if (snap->count < DIAG_HWND_CAP) {
		snap->list[snap->count++] = hwnd;
	}
	return TRUE;
}

static int
hwnd_in_snap (const HwndSnap *snap, HWND hwnd)
{
	int i;

	for (i = 0; i < snap->count; i++) {
		if (snap->list[i] == hwnd) {
			return 1;
		}
	}
	return 0;
}

static void
log_hwnd_title_class (HWND hwnd)
{
	char title[256];
	char cls[128];
	DWORD pid = 0;

	title[0] = '\0';
	cls[0] = '\0';
	GetWindowTextA (hwnd, title, (int) sizeof (title));
	GetClassNameA (hwnd, cls, (int) sizeof (cls));
	GetWindowThreadProcessId (hwnd, &pid);
	vala_webview2_a11y_diag_log (
		"  HWND %p pid=%lu class=%s title=%s",
		(void *) hwnd,
		(unsigned long) pid,
		cls[0] != '\0' ? cls : "?",
		title[0] != '\0' ? title : "(empty)");
}

void
vala_webview2_a11y_diag_hwnd_snap_begin (void)
{
	if (!vala_webview2_a11y_diag_enabled ()) {
		return;
	}
	ZeroMemory (&g_hwnd_before, sizeof (g_hwnd_before));
	EnumWindows (enum_visible_toplevel, (LPARAM) &g_hwnd_before);
	vala_webview2_a11y_diag_log ("HWND snap pre-invoke count=%d", g_hwnd_before.count);
}

void
vala_webview2_a11y_diag_hwnd_snap_end (DWORD wait_ms)
{
	HwndSnap after;
	int i;
	int added = 0;

	if (!vala_webview2_a11y_diag_enabled ()) {
		return;
	}
	if (wait_ms > 0) {
		Sleep (wait_ms);
	}
	ZeroMemory (&after, sizeof (after));
	EnumWindows (enum_visible_toplevel, (LPARAM) &after);
	vala_webview2_a11y_diag_log ("HWND snap post-invoke+%lums count=%d",
	                             (unsigned long) wait_ms, after.count);
	for (i = 0; i < after.count; i++) {
		if (!hwnd_in_snap (&g_hwnd_before, after.list[i])) {
			added++;
			vala_webview2_a11y_diag_log ("HWND NEW:");
			log_hwnd_title_class (after.list[i]);
		}
	}
	if (added == 0) {
		vala_webview2_a11y_diag_log ("HWND delta: no new visible top-level windows");
	} else {
		vala_webview2_a11y_diag_log ("HWND delta: %d new visible top-level window(s)", added);
	}
}

static char *
xstrdup (const char *s)
{
	size_t n;
	char *d;

	if (s == NULL) {
		return NULL;
	}
	n = strlen (s) + 1;
	d = (char *) malloc (n);
	if (d != NULL) {
		memcpy (d, s, n);
	}
	return d;
}

static char *
wide_to_utf8_alloc (LPWSTR wide)
{
	int nbytes;
	char *utf8;

	if (wide == NULL) {
		return xstrdup ("(null)");
	}
	nbytes = WideCharToMultiByte (CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
	if (nbytes <= 0) {
		return xstrdup ("(utf16-fail)");
	}
	utf8 = (char *) malloc ((size_t) nbytes);
	if (utf8 == NULL) {
		return NULL;
	}
	WideCharToMultiByte (CP_UTF8, 0, wide, -1, utf8, nbytes, NULL, NULL);
	return utf8;
}

/* ---- NewWindowRequested ---- */

typedef struct {
	ICoreWebView2NewWindowRequestedEventHandler iface;
	ICoreWebView2NewWindowRequestedEventHandlerVtbl vtbl;
	LONG ref_count;
} NwHandler;

static HRESULT STDMETHODCALLTYPE nw_qi (ICoreWebView2NewWindowRequestedEventHandler *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2NewWindowRequestedEventHandler)) {
		*ppv = This;
		ICoreWebView2NewWindowRequestedEventHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE nw_addref (ICoreWebView2NewWindowRequestedEventHandler *This)
{
	NwHandler *self = (NwHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE nw_release (ICoreWebView2NewWindowRequestedEventHandler *This)
{
	NwHandler *self = (NwHandler *) This;
	LONG c = InterlockedDecrement (&self->ref_count);
	if (c == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) c;
}

static HRESULT STDMETHODCALLTYPE nw_invoke (
	ICoreWebView2NewWindowRequestedEventHandler *This,
	ICoreWebView2 *sender,
	ICoreWebView2NewWindowRequestedEventArgs *args)
{
	LPWSTR uri_w = NULL;
	BOOL user_init = FALSE;
	BOOL handled = FALSE;
	char *uri8;

	(void) This;
	(void) sender;
	if (args == NULL) {
		vala_webview2_a11y_diag_log ("EVENT NewWindowRequested args=NULL");
		return S_OK;
	}
	ICoreWebView2NewWindowRequestedEventArgs_get_Uri (args, &uri_w);
	ICoreWebView2NewWindowRequestedEventArgs_get_IsUserInitiated (args, &user_init);
	ICoreWebView2NewWindowRequestedEventArgs_get_Handled (args, &handled);
	uri8 = wide_to_utf8_alloc (uri_w);
	vala_webview2_a11y_diag_log (
		"EVENT NewWindowRequested uri=%s isUserInitiated=%d handled=%d "
		"(host NOT setting Handled — default WebView2 popup behavior)",
		uri8 != NULL ? uri8 : "(null)",
		(int) user_init,
		(int) handled);
	free (uri8);
	if (uri_w != NULL) {
		CoTaskMemFree (uri_w);
	}
	/* Leave Handled alone so we observe whether a popup still appears. */
	return S_OK;
}

/* ---- NavigationStarting (extra logger) ---- */

typedef struct {
	ICoreWebView2NavigationStartingEventHandler iface;
	ICoreWebView2NavigationStartingEventHandlerVtbl vtbl;
	LONG ref_count;
} NavHandler;

static HRESULT STDMETHODCALLTYPE nav_qi (ICoreWebView2NavigationStartingEventHandler *This, REFIID riid, void **ppv)
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

static ULONG STDMETHODCALLTYPE nav_addref (ICoreWebView2NavigationStartingEventHandler *This)
{
	NavHandler *self = (NavHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE nav_release (ICoreWebView2NavigationStartingEventHandler *This)
{
	NavHandler *self = (NavHandler *) This;
	LONG c = InterlockedDecrement (&self->ref_count);
	if (c == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) c;
}

static HRESULT STDMETHODCALLTYPE nav_invoke (
	ICoreWebView2NavigationStartingEventHandler *This,
	ICoreWebView2 *sender,
	ICoreWebView2NavigationStartingEventArgs *args)
{
	LPWSTR uri_w = NULL;
	BOOL user_init = FALSE;
	BOOL is_redirect = FALSE;
	char *uri8;

	(void) This;
	(void) sender;
	if (args == NULL) {
		return S_OK;
	}
	ICoreWebView2NavigationStartingEventArgs_get_Uri (args, &uri_w);
	ICoreWebView2NavigationStartingEventArgs_get_IsUserInitiated (args, &user_init);
	ICoreWebView2NavigationStartingEventArgs_get_IsRedirected (args, &is_redirect);
	uri8 = wide_to_utf8_alloc (uri_w);
	vala_webview2_a11y_diag_log (
		"EVENT NavigationStarting uri=%s isUserInitiated=%d isRedirected=%d",
		uri8 != NULL ? uri8 : "(null)",
		(int) user_init,
		(int) is_redirect);
	free (uri8);
	if (uri_w != NULL) {
		CoTaskMemFree (uri_w);
	}
	return S_OK;
}

void
vala_webview2_a11y_diag_register (ICoreWebView2 *webview)
{
	NwHandler *nw;
	NavHandler *nav;
	HRESULT hr;

	if (webview == NULL || !vala_webview2_a11y_diag_enabled ()) {
		return;
	}
	diag_open ();
	vala_webview2_a11y_diag_log ("register diag handlers on webview=%p", (void *) webview);

	if (!g_nw_registered) {
		nw = (NwHandler *) CoTaskMemAlloc (sizeof (NwHandler));
		if (nw != NULL) {
			ZeroMemory (nw, sizeof (*nw));
			nw->iface.lpVtbl = &nw->vtbl;
			nw->vtbl.QueryInterface = nw_qi;
			nw->vtbl.AddRef = nw_addref;
			nw->vtbl.Release = nw_release;
			nw->vtbl.Invoke = nw_invoke;
			nw->ref_count = 1;
			hr = ICoreWebView2_add_NewWindowRequested (webview, &nw->iface, &g_nw_token);
			if (SUCCEEDED (hr)) {
				g_nw_registered = TRUE;
				vala_webview2_a11y_diag_log ("add_NewWindowRequested OK");
			} else {
				vala_webview2_a11y_diag_log ("add_NewWindowRequested FAILED 0x%08lx",
				                            (unsigned long) hr);
				ICoreWebView2NewWindowRequestedEventHandler_Release (&nw->iface);
			}
		}
	}

	if (!g_nav_registered) {
		nav = (NavHandler *) CoTaskMemAlloc (sizeof (NavHandler));
		if (nav != NULL) {
			ZeroMemory (nav, sizeof (*nav));
			nav->iface.lpVtbl = &nav->vtbl;
			nav->vtbl.QueryInterface = nav_qi;
			nav->vtbl.AddRef = nav_addref;
			nav->vtbl.Release = nav_release;
			nav->vtbl.Invoke = nav_invoke;
			nav->ref_count = 1;
			hr = ICoreWebView2_add_NavigationStarting (webview, &nav->iface, &g_nav_token);
			if (SUCCEEDED (hr)) {
				g_nav_registered = TRUE;
				vala_webview2_a11y_diag_log ("add_NavigationStarting (diag) OK");
			} else {
				vala_webview2_a11y_diag_log ("add_NavigationStarting FAILED 0x%08lx",
				                            (unsigned long) hr);
				ICoreWebView2NavigationStartingEventHandler_Release (&nav->iface);
			}
		}
	}
}
