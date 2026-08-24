/*
 * 4.5 spike — two ICoreWebView2Controller on one toplevel HWND.
 *
 * Does NOT use libwebview2gtk (singleton). Speaks WebView2 COM directly.
 *
 * Pass: both controllers create, navigate to different URLs, both get
 * NavigationCompleted; park left off-screen then restore still paints.
 *
 *   webview2gtk-multi-host-spike.exe [--smoke]
 */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <stdio.h>
#include <string.h>

#include "WebView2.h"

typedef HRESULT (STDMETHODCALLTYPE *PFN_CreateCoreWebView2EnvironmentWithOptions)(
	PCWSTR browserExecutableFolder,
	PCWSTR userDataFolder,
	ICoreWebView2EnvironmentOptions *environmentOptions,
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *environmentCreatedHandler);

static PFN_CreateCoreWebView2EnvironmentWithOptions g_create_env;
static ICoreWebView2Environment *g_env;
static HWND g_hwnd;
static BOOL g_smoke;
static volatile LONG g_controllers_ready;
static volatile LONG g_nav_done;
static volatile LONG g_create_failed;

typedef struct Slot {
	const wchar_t *url;
	const char *name;
	RECT bounds;
	ICoreWebView2Controller *controller;
	ICoreWebView2 *webview;
	EventRegistrationToken nav_token;
	BOOL nav_finished;
} Slot;

static Slot g_slots[2];

/* --- minimal COM handlers --- */

typedef struct EnvHandler {
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler iface;
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl vtbl;
	LONG ref_count;
} EnvHandler;

typedef struct CtrlHandler {
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandler iface;
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl vtbl;
	LONG ref_count;
	int slot;
} CtrlHandler;

typedef struct NavHandler {
	ICoreWebView2NavigationCompletedEventHandler iface;
	ICoreWebView2NavigationCompletedEventHandlerVtbl vtbl;
	LONG ref_count;
	int slot;
} NavHandler;

static HRESULT STDMETHODCALLTYPE
qi_env (ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)) {
		*ppv = This;
		This->lpVtbl->AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
addref_env (ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This)
{
	return (ULONG) InterlockedIncrement (&((EnvHandler *) This)->ref_count);
}

static ULONG STDMETHODCALLTYPE
release_env (ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This)
{
	LONG c = InterlockedDecrement (&((EnvHandler *) This)->ref_count);
	if (c == 0) {
		CoTaskMemFree (This);
	}
	return (ULONG) c;
}

static HRESULT STDMETHODCALLTYPE
qi_ctrl (ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2CreateCoreWebView2ControllerCompletedHandler)) {
		*ppv = This;
		This->lpVtbl->AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
addref_ctrl (ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This)
{
	return (ULONG) InterlockedIncrement (&((CtrlHandler *) This)->ref_count);
}

static ULONG STDMETHODCALLTYPE
release_ctrl (ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This)
{
	LONG c = InterlockedDecrement (&((CtrlHandler *) This)->ref_count);
	if (c == 0) {
		CoTaskMemFree (This);
	}
	return (ULONG) c;
}

static HRESULT STDMETHODCALLTYPE
qi_nav (ICoreWebView2NavigationCompletedEventHandler *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2NavigationCompletedEventHandler)) {
		*ppv = This;
		This->lpVtbl->AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
addref_nav (ICoreWebView2NavigationCompletedEventHandler *This)
{
	return (ULONG) InterlockedIncrement (&((NavHandler *) This)->ref_count);
}

static ULONG STDMETHODCALLTYPE
release_nav (ICoreWebView2NavigationCompletedEventHandler *This)
{
	LONG c = InterlockedDecrement (&((NavHandler *) This)->ref_count);
	if (c == 0) {
		CoTaskMemFree (This);
	}
	return (ULONG) c;
}

static HRESULT STDMETHODCALLTYPE
nav_invoke (ICoreWebView2NavigationCompletedEventHandler *This,
	ICoreWebView2 *sender,
	ICoreWebView2NavigationCompletedEventArgs *args)
{
	NavHandler *self = (NavHandler *) This;
	BOOL ok = FALSE;
	Slot *slot = &g_slots[self->slot];

	(void) sender;
	if (args != NULL) {
		ICoreWebView2NavigationCompletedEventArgs_get_IsSuccess (args, &ok);
	}
	fprintf (stderr, "spike: %s NavigationCompleted success=%d\n", slot->name, (int) ok);
	if (!slot->nav_finished) {
		slot->nav_finished = TRUE;
		InterlockedIncrement (&g_nav_done);
	}
	return S_OK;
}

static void
slot_start_navigate (int i)
{
	NavHandler *nav;
	HRESULT hr;
	Slot *slot = &g_slots[i];

	nav = (NavHandler *) CoTaskMemAlloc (sizeof (NavHandler));
	ZeroMemory (nav, sizeof (*nav));
	nav->iface.lpVtbl = &nav->vtbl;
	nav->vtbl.QueryInterface = qi_nav;
	nav->vtbl.AddRef = addref_nav;
	nav->vtbl.Release = release_nav;
	nav->vtbl.Invoke = nav_invoke;
	nav->ref_count = 1;
	nav->slot = i;

	hr = ICoreWebView2_add_NavigationCompleted (slot->webview, &nav->iface, &slot->nav_token);
	ICoreWebView2NavigationCompletedEventHandler_Release (&nav->iface);
	if (FAILED (hr)) {
		fprintf (stderr, "spike: %s add_NavigationCompleted failed 0x%08lx\n",
			slot->name, (unsigned long) hr);
		InterlockedIncrement (&g_create_failed);
		return;
	}

	hr = ICoreWebView2Controller_put_Bounds (slot->controller, slot->bounds);
	if (FAILED (hr)) {
		fprintf (stderr, "spike: %s put_Bounds failed 0x%08lx\n",
			slot->name, (unsigned long) hr);
	}
	hr = ICoreWebView2Controller_put_IsVisible (slot->controller, TRUE);
	(void) hr;

	fprintf (stderr, "spike: %s Navigate %ls bounds=(%ld,%ld)-(%ld,%ld)\n",
		slot->name, slot->url,
		slot->bounds.left, slot->bounds.top, slot->bounds.right, slot->bounds.bottom);
	hr = ICoreWebView2_Navigate (slot->webview, slot->url);
	if (FAILED (hr)) {
		fprintf (stderr, "spike: %s Navigate failed 0x%08lx\n",
			slot->name, (unsigned long) hr);
		InterlockedIncrement (&g_create_failed);
	}
}

static HRESULT STDMETHODCALLTYPE
ctrl_invoke (ICoreWebView2CreateCoreWebView2ControllerCompletedHandler *This,
	HRESULT error_code,
	ICoreWebView2Controller *controller)
{
	CtrlHandler *self = (CtrlHandler *) This;
	Slot *slot = &g_slots[self->slot];
	HRESULT hr;

	if (FAILED (error_code) || controller == NULL) {
		fprintf (stderr, "spike: %s controller failed 0x%08lx\n",
			slot->name, (unsigned long) error_code);
		InterlockedIncrement (&g_create_failed);
		return error_code;
	}

	slot->controller = controller;
	ICoreWebView2Controller_AddRef (slot->controller);
	hr = ICoreWebView2Controller_get_CoreWebView2 (slot->controller, &slot->webview);
	if (FAILED (hr) || slot->webview == NULL) {
		fprintf (stderr, "spike: %s get_CoreWebView2 failed 0x%08lx\n",
			slot->name, (unsigned long) hr);
		InterlockedIncrement (&g_create_failed);
		return hr;
	}

	fprintf (stderr, "spike: %s controller ready\n", slot->name);
	InterlockedIncrement (&g_controllers_ready);
	slot_start_navigate (self->slot);
	return S_OK;
}

static void
create_controller (int slot)
{
	CtrlHandler *h;
	HRESULT hr;

	h = (CtrlHandler *) CoTaskMemAlloc (sizeof (CtrlHandler));
	ZeroMemory (h, sizeof (*h));
	h->iface.lpVtbl = &h->vtbl;
	h->vtbl.QueryInterface = qi_ctrl;
	h->vtbl.AddRef = addref_ctrl;
	h->vtbl.Release = release_ctrl;
	h->vtbl.Invoke = ctrl_invoke;
	h->ref_count = 1;
	h->slot = slot;

	hr = ICoreWebView2Environment_CreateCoreWebView2Controller (
		g_env, g_hwnd, &h->iface);
	ICoreWebView2CreateCoreWebView2ControllerCompletedHandler_Release (&h->iface);
	if (FAILED (hr)) {
		fprintf (stderr, "spike: CreateCoreWebView2Controller(%s) failed 0x%08lx\n",
			g_slots[slot].name, (unsigned long) hr);
		InterlockedIncrement (&g_create_failed);
	}
}

static HRESULT STDMETHODCALLTYPE
env_invoke (ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *This,
	HRESULT error_code,
	ICoreWebView2Environment *environment)
{
	(void) This;
	if (FAILED (error_code) || environment == NULL) {
		fprintf (stderr, "spike: environment failed 0x%08lx\n", (unsigned long) error_code);
		InterlockedIncrement (&g_create_failed);
		return error_code;
	}
	g_env = environment;
	ICoreWebView2Environment_AddRef (g_env);
	fprintf (stderr, "spike: environment ready — creating two controllers on same HWND\n");
	create_controller (0);
	create_controller (1);
	return S_OK;
}

static void
layout_halves (void)
{
	RECT rc;
	LONG mid;

	GetClientRect (g_hwnd, &rc);
	mid = (rc.left + rc.right) / 2;
	g_slots[0].bounds.left = rc.left;
	g_slots[0].bounds.top = rc.top;
	g_slots[0].bounds.right = mid;
	g_slots[0].bounds.bottom = rc.bottom;
	g_slots[1].bounds.left = mid;
	g_slots[1].bounds.top = rc.top;
	g_slots[1].bounds.right = rc.right;
	g_slots[1].bounds.bottom = rc.bottom;
}

static void
park_slot (int i, BOOL park)
{
	RECT r;
	HRESULT hr;

	if (g_slots[i].controller == NULL) {
		return;
	}
	if (park) {
		r.left = -30000;
		r.top = -30000;
		r.right = -29900;
		r.bottom = -29900;
		fprintf (stderr, "spike: park %s off-screen\n", g_slots[i].name);
	} else {
		layout_halves ();
		r = g_slots[i].bounds;
		fprintf (stderr, "spike: restore %s on-screen\n", g_slots[i].name);
	}
	hr = ICoreWebView2Controller_put_Bounds (g_slots[i].controller, r);
	if (FAILED (hr)) {
		fprintf (stderr, "spike: park put_Bounds failed 0x%08lx\n", (unsigned long) hr);
		InterlockedIncrement (&g_create_failed);
	}
}

static LRESULT CALLBACK
wnd_proc (HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
	switch (msg) {
	case WM_SIZE:
		if (g_controllers_ready >= 2) {
			layout_halves ();
			if (g_slots[0].controller) {
				ICoreWebView2Controller_put_Bounds (g_slots[0].controller, g_slots[0].bounds);
			}
			if (g_slots[1].controller) {
				ICoreWebView2Controller_put_Bounds (g_slots[1].controller, g_slots[1].bounds);
			}
		}
		return 0;
	case WM_DESTROY:
		PostQuitMessage (0);
		return 0;
	default:
		return DefWindowProcW (hwnd, msg, wparam, lparam);
	}
}

static BOOL
load_webview2 (void)
{
	HMODULE mod = LoadLibraryW (L"WebView2Loader.dll");
	if (mod == NULL) {
		fprintf (stderr, "spike: LoadLibrary WebView2Loader.dll failed %lu\n",
			(unsigned long) GetLastError ());
		return FALSE;
	}
	g_create_env = (PFN_CreateCoreWebView2EnvironmentWithOptions) (void *)
		GetProcAddress (mod, "CreateCoreWebView2EnvironmentWithOptions");
	if (g_create_env == NULL) {
		fprintf (stderr, "spike: GetProcAddress CreateCoreWebView2EnvironmentWithOptions failed\n");
		return FALSE;
	}
	return TRUE;
}

int WINAPI
wWinMain (HINSTANCE inst, HINSTANCE prev, PWSTR cmd, int show)
{
	WNDCLASSW wc;
	MSG msg;
	EnvHandler *env_h;
	HRESULT hr;
	DWORD start;
	BOOL park_done = FALSE;
	BOOL restore_done = FALSE;
	int exit_code = 1;

	(void) prev;
	(void) show;

	g_smoke = (cmd != NULL && wcsstr (cmd, L"--smoke") != NULL);

	hr = CoInitializeEx (NULL, COINIT_APARTMENTTHREADED);
	if (FAILED (hr) && hr != RPC_E_CHANGED_MODE) {
		fprintf (stderr, "spike: CoInitializeEx failed 0x%08lx\n", (unsigned long) hr);
		return 1;
	}

	if (!load_webview2 ()) {
		return 1;
	}

	ZeroMemory (&wc, sizeof (wc));
	wc.lpfnWndProc = wnd_proc;
	wc.hInstance = inst;
	wc.lpszClassName = L"WebView2GtkMultiHostSpike";
	wc.hCursor = LoadCursor (NULL, IDC_ARROW);
	RegisterClassW (&wc);

	g_hwnd = CreateWindowExW (0, wc.lpszClassName, L"webview2-gtk multi-host spike",
		WS_OVERLAPPEDWINDOW | WS_VISIBLE,
		CW_USEDEFAULT, CW_USEDEFAULT, 960, 640,
		NULL, NULL, inst, NULL);
	if (g_hwnd == NULL) {
		fprintf (stderr, "spike: CreateWindowEx failed\n");
		return 1;
	}

	{
		LONG style = GetWindowLongW (g_hwnd, GWL_STYLE);
		SetWindowLongW (g_hwnd, GWL_STYLE, style | WS_CLIPCHILDREN | WS_CLIPSIBLINGS);
	}

	g_slots[0].name = "left";
	g_slots[0].url = L"https://example.com/";
	g_slots[1].name = "right";
	g_slots[1].url = L"https://example.org/";
	layout_halves ();

	env_h = (EnvHandler *) CoTaskMemAlloc (sizeof (EnvHandler));
	ZeroMemory (env_h, sizeof (*env_h));
	env_h->iface.lpVtbl = &env_h->vtbl;
	env_h->vtbl.QueryInterface = qi_env;
	env_h->vtbl.AddRef = addref_env;
	env_h->vtbl.Release = release_env;
	env_h->vtbl.Invoke = env_invoke;
	env_h->ref_count = 1;

	hr = g_create_env (NULL, NULL, NULL, &env_h->iface);
	ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler_Release (&env_h->iface);
	if (FAILED (hr)) {
		fprintf (stderr, "spike: CreateCoreWebView2EnvironmentWithOptions failed 0x%08lx\n",
			(unsigned long) hr);
		return 1;
	}

	start = GetTickCount ();
	while (TRUE) {
		while (PeekMessageW (&msg, NULL, 0, 0, PM_REMOVE)) {
			if (msg.message == WM_QUIT) {
				goto done;
			}
			TranslateMessage (&msg);
			DispatchMessageW (&msg);
		}

		if (g_create_failed) {
			fprintf (stderr, "SPIKE_FAIL create/navigate error\n");
			exit_code = 1;
			break;
		}

		if (g_nav_done >= 2 && !park_done) {
			fprintf (stderr, "spike: both navigations finished — testing park\n");
			park_slot (0, TRUE);
			park_done = TRUE;
			start = GetTickCount ();
		}

		if (park_done && !restore_done && GetTickCount () - start > 500) {
			park_slot (0, FALSE);
			restore_done = TRUE;
			start = GetTickCount ();
		}

		if (restore_done && GetTickCount () - start > 500) {
			fprintf (stderr, "SPIKE_PASS same-parent two controllers + park/restore\n");
			exit_code = 0;
			break;
		}

		if (GetTickCount () - start > 20000) {
			fprintf (stderr, "SPIKE_FAIL timeout controllers=%ld nav=%ld\n",
				(long) g_controllers_ready, (long) g_nav_done);
			exit_code = 1;
			break;
		}

		if (g_smoke && exit_code == 0) {
			break;
		}
		Sleep (10);
	}

done:
	if (g_smoke || exit_code != 0) {
		DestroyWindow (g_hwnd);
	} else {
		/* Interactive: leave window open until closed. */
		while (GetMessageW (&msg, NULL, 0, 0) > 0) {
			TranslateMessage (&msg);
			DispatchMessageW (&msg);
		}
	}

	return exit_code;
}

/* MinGW: provide main that calls wWinMain when linking -mconsole. */
#ifdef __GNUC__
int
main (int argc, char **argv)
{
	wchar_t cmd[512];
	int i;
	cmd[0] = L'\0';
	for (i = 1; i < argc; i++) {
		MultiByteToWideChar (CP_UTF8, 0, argv[i], -1,
			cmd + wcslen (cmd), (int) (512 - wcslen (cmd) - 2));
		wcscat (cmd, L" ");
	}
	return wWinMain (GetModuleHandleW (NULL), NULL, cmd, SW_SHOW);
}
#endif
