/* WebKitGTK script_dialog via ScriptDialogOpening.
 *
 * The event runs only when AreDefaultScriptDialogsEnabled is FALSE.
 * No connected handler → leave the default TRUE so Edge shows its dialog.
 * A handler that returns true completes the page from ScriptDialog fields.
 * A handler that returns false cannot bring Edge's dialog back for this
 * event, so a Win32 dialog answers the page instead.
 */

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <glib.h>

#include "webview2gtk-host-api.h"
#include "win32-ui-webview2-script-dialogs.h"
#include "win32-ui-webview2-host-priv.h"
#include "win32-ui-webview2-com-glue.h"
#include "win32-ui-webview2-sdk.h"

#define WV2_SCRIPT_KIND_ALERT 0
#define WV2_SCRIPT_KIND_CONFIRM 1
#define WV2_SCRIPT_KIND_PROMPT 2
#define WV2_SCRIPT_KIND_BEFOREUNLOAD 3

#define PROMPT_OK 1
#define PROMPT_CANCEL 2
#define PROMPT_EDIT 101

static BOOL g_prepare_default_script_dialogs = TRUE;
static BOOL g_prompt_class_ready = FALSE;

typedef struct {
	ICoreWebView2ScriptDialogOpeningEventHandler iface;
	ICoreWebView2ScriptDialogOpeningEventHandlerVtbl vtbl;
	LONG ref_count;
	WebView2Host *host;
} ScriptDialogHandler;

typedef struct {
	LPCWSTR message;
	LPCWSTR initial;
	wchar_t *result;
	BOOL accepted;
	HWND edit;
} PromptBox;

static char *
wide_to_utf8 (LPCWSTR wide)
{
	char *utf8;

	if (wide == NULL) {
		return strdup ("");
	}
	utf8 = win32_ui_utf16_to_utf8 ((uint16_t *) wide, (int) wcslen (wide) + 1);
	return utf8 != NULL ? utf8 : strdup ("");
}

static void
apply_default_script_dialogs (WebView2Host *host)
{
	ICoreWebView2Settings *settings = NULL;
	HRESULT hr;

	if (host == NULL || host->webview == NULL) {
		return;
	}
	hr = ICoreWebView2_get_Settings (host->webview, &settings);
	if (FAILED (hr) || settings == NULL) {
		fprintf (stderr, "WebView2 get_Settings failed: 0x%08lx\n", (unsigned long) hr);
		return;
	}
	hr = ICoreWebView2Settings_put_AreDefaultScriptDialogsEnabled (
		settings, host->default_script_dialogs ? TRUE : FALSE);
	if (FAILED (hr)) {
		fprintf (stderr, "WebView2 put_AreDefaultScriptDialogsEnabled failed: 0x%08lx\n",
		         (unsigned long) hr);
	}
	ICoreWebView2Settings_Release (settings);
}

static LRESULT CALLBACK
prompt_wndproc (HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
	PromptBox *box = (PromptBox *) GetWindowLongPtrW (hwnd, GWLP_USERDATA);

	switch (msg) {
	case WM_CREATE: {
		CREATESTRUCTW *cs = (CREATESTRUCTW *) lp;
		HFONT font = (HFONT) GetStockObject (DEFAULT_GUI_FONT);
		HWND label;
		HWND ok;
		HWND cancel;
		LPCWSTR text;
		LPCWSTR initial;

		box = (PromptBox *) cs->lpCreateParams;
		SetWindowLongPtrW (hwnd, GWLP_USERDATA, (LONG_PTR) box);
		text = (box != NULL && box->message != NULL) ? box->message : L"";
		initial = (box != NULL && box->initial != NULL) ? box->initial : L"";
		label = CreateWindowExW (0, L"STATIC", text,
		                          WS_CHILD | WS_VISIBLE | SS_LEFT,
		                          12, 12, 400, 52,
		                          hwnd, NULL, NULL, NULL);
		if (box != NULL) {
			box->edit = CreateWindowExW (WS_EX_CLIENTEDGE, L"EDIT", initial,
			                              WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL | ES_LEFT,
			                              12, 70, 400, 24,
			                              hwnd, (HMENU) (INT_PTR) PROMPT_EDIT, NULL, NULL);
		}
		ok = CreateWindowExW (0, L"BUTTON", L"OK",
		                       WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON,
		                       228, 108, 88, 26,
		                       hwnd, (HMENU) (INT_PTR) PROMPT_OK, NULL, NULL);
		cancel = CreateWindowExW (0, L"BUTTON", L"Cancel",
		                           WS_CHILD | WS_VISIBLE | WS_TABSTOP,
		                           324, 108, 88, 26,
		                           hwnd, (HMENU) (INT_PTR) PROMPT_CANCEL, NULL, NULL);
		SendMessageW (label, WM_SETFONT, (WPARAM) font, TRUE);
		if (box != NULL && box->edit != NULL) {
			SendMessageW (box->edit, WM_SETFONT, (WPARAM) font, TRUE);
			SendMessageW (box->edit, EM_SETSEL, 0, -1);
		}
		SendMessageW (ok, WM_SETFONT, (WPARAM) font, TRUE);
		SendMessageW (cancel, WM_SETFONT, (WPARAM) font, TRUE);
		return 0;
	}
	case DM_GETDEFID:
		return MAKELRESULT (PROMPT_OK, DC_HASDEFID);
	case WM_COMMAND:
		if (box == NULL) {
			return 0;
		}
		if (LOWORD (wp) == PROMPT_OK) {
			int n = GetWindowTextLengthW (box->edit);
			if (n < 0) {
				n = 0;
			}
			if (n > 65536) {
				n = 65536;
			}
			box->result = (wchar_t *) calloc ((size_t) n + 1, sizeof (wchar_t));
			if (box->result != NULL && n > 0) {
				GetWindowTextW (box->edit, box->result, n + 1);
			}
			box->accepted = TRUE;
			DestroyWindow (hwnd);
			return 0;
		}
		if (LOWORD (wp) == PROMPT_CANCEL) {
			box->accepted = FALSE;
			DestroyWindow (hwnd);
			return 0;
		}
		return 0;
	case WM_CLOSE:
		if (box != NULL) {
			box->accepted = FALSE;
		}
		DestroyWindow (hwnd);
		return 0;
	default:
		break;
	}
	return DefWindowProcW (hwnd, msg, wp, lp);
}

static void
ensure_prompt_class (void)
{
	WNDCLASSW wc;

	if (g_prompt_class_ready) {
		return;
	}
	ZeroMemory (&wc, sizeof (wc));
	wc.lpfnWndProc = prompt_wndproc;
	wc.hInstance = GetModuleHandleW (NULL);
	wc.lpszClassName = L"WebView2GtkScriptPrompt";
	wc.hbrBackground = (HBRUSH) (COLOR_WINDOW + 1);
	wc.hCursor = LoadCursor (NULL, IDC_ARROW);
	if (RegisterClassW (&wc) != 0 || GetLastError () == ERROR_CLASS_ALREADY_EXISTS) {
		g_prompt_class_ready = TRUE;
	}
}

static BOOL
run_prompt (HWND parent, LPCWSTR message, LPCWSTR initial, wchar_t **result_out)
{
	PromptBox box;
	HWND hwnd;
	RECT pr;
	int x = CW_USEDEFAULT;
	int y = CW_USEDEFAULT;

	ZeroMemory (&box, sizeof (box));
	box.message = message;
	box.initial = initial;
	*result_out = NULL;
	ensure_prompt_class ();
	if (!g_prompt_class_ready) {
		return FALSE;
	}
	if (parent != NULL && GetWindowRect (parent, &pr)) {
		x = pr.left + ((pr.right - pr.left) - 440) / 2;
		y = pr.top + ((pr.bottom - pr.top) - 180) / 2;
	}
	hwnd = CreateWindowExW (WS_EX_DLGMODALFRAME, L"WebView2GtkScriptPrompt", L"JavaScript",
	                         WS_POPUP | WS_CAPTION | WS_SYSMENU,
	                         x, y, 440, 180,
	                         parent, NULL, GetModuleHandleW (NULL), &box);
	if (hwnd == NULL) {
		return FALSE;
	}
	ShowWindow (hwnd, SW_SHOW);
	UpdateWindow (hwnd);
	if (parent != NULL) {
		EnableWindow (parent, FALSE);
	}
	EnableWindow (hwnd, TRUE);
	if (box.edit != NULL) {
		SetFocus (box.edit);
	}
	while (IsWindow (hwnd)) {
		MSG msg;
		int got = GetMessageW (&msg, NULL, 0, 0);
		if (got == 0) {
			PostQuitMessage ((int) msg.wParam);
			break;
		}
		if (got < 0) {
			break;
		}
		if (!IsWindow (hwnd) || !IsDialogMessageW (hwnd, &msg)) {
			TranslateMessage (&msg);
			DispatchMessageW (&msg);
		}
	}
	if (parent != NULL) {
		EnableWindow (parent, TRUE);
		SetForegroundWindow (parent);
	}
	*result_out = box.result;
	return box.accepted ? TRUE : FALSE;
}

static void
fallback_dialog (
	HWND parent,
	int kind,
	LPCWSTR message,
	LPCWSTR default_text,
	ICoreWebView2ScriptDialogOpeningEventArgs *args)
{
	LPCWSTR text = (message != NULL && message[0] != L'\0') ? message : L"";

	switch (kind) {
	case WV2_SCRIPT_KIND_CONFIRM:
		if (MessageBoxW (parent, text, L"JavaScript", MB_OKCANCEL | MB_ICONQUESTION) == IDOK) {
			ICoreWebView2ScriptDialogOpeningEventArgs_Accept (args);
		}
		break;
	case WV2_SCRIPT_KIND_BEFOREUNLOAD:
		if (text[0] == L'\0') {
			text = L"Leave this page?";
		}
		if (MessageBoxW (parent, text, L"Leave page?", MB_YESNO | MB_ICONWARNING) == IDYES) {
			ICoreWebView2ScriptDialogOpeningEventArgs_Accept (args);
		}
		break;
	case WV2_SCRIPT_KIND_PROMPT: {
		wchar_t *result = NULL;
		if (run_prompt (parent, text, default_text, &result)) {
			if (result != NULL) {
				ICoreWebView2ScriptDialogOpeningEventArgs_put_ResultText (args, result);
				free (result);
			}
			ICoreWebView2ScriptDialogOpeningEventArgs_Accept (args);
		} else {
			free (result);
		}
		break;
	}
	case WV2_SCRIPT_KIND_ALERT:
	default:
		MessageBoxW (parent, text, L"JavaScript", MB_OK | MB_ICONINFORMATION);
		break;
	}
}

static void
complete_handled (
	ICoreWebView2ScriptDialogOpeningEventArgs *args,
	int kind,
	int accept,
	char *result_utf8)
{
	if (kind == WV2_SCRIPT_KIND_PROMPT && result_utf8 != NULL) {
		wchar_t *wide = (wchar_t *) win32_ui_utf8_to_utf16 (result_utf8, NULL);
		if (wide != NULL) {
			ICoreWebView2ScriptDialogOpeningEventArgs_put_ResultText (args, wide);
			free (wide);
		}
	}
	/* Alert finishes when the event returns. Accept is confirm / prompt / beforeunload. */
	if (accept && kind != WV2_SCRIPT_KIND_ALERT) {
		if (kind != WV2_SCRIPT_KIND_PROMPT || result_utf8 != NULL) {
			ICoreWebView2ScriptDialogOpeningEventArgs_Accept (args);
		}
	}
}

static HRESULT STDMETHODCALLTYPE
dlg_qi (ICoreWebView2ScriptDialogOpeningEventHandler *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2ScriptDialogOpeningEventHandler)) {
		*ppv = This;
		ICoreWebView2ScriptDialogOpeningEventHandler_AddRef (This);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
dlg_addref (ICoreWebView2ScriptDialogOpeningEventHandler *This)
{
	ScriptDialogHandler *self = (ScriptDialogHandler *) This;
	return (ULONG) InterlockedIncrement (&self->ref_count);
}

static ULONG STDMETHODCALLTYPE
dlg_release (ICoreWebView2ScriptDialogOpeningEventHandler *This)
{
	ScriptDialogHandler *self = (ScriptDialogHandler *) This;
	LONG n = InterlockedDecrement (&self->ref_count);
	if (n == 0) {
		CoTaskMemFree (self);
	}
	return (ULONG) n;
}

static HRESULT STDMETHODCALLTYPE
dlg_invoke (
	ICoreWebView2ScriptDialogOpeningEventHandler *This,
	ICoreWebView2 *sender,
	ICoreWebView2ScriptDialogOpeningEventArgs *args)
{
	ScriptDialogHandler *self = (ScriptDialogHandler *) This;
	WebView2Host *host = self->host;
	COREWEBVIEW2_SCRIPT_DIALOG_KIND kind = COREWEBVIEW2_SCRIPT_DIALOG_KIND_ALERT;
	LPWSTR message_w = NULL;
	LPWSTR default_w = NULL;
	char *message_utf8 = NULL;
	char *default_utf8 = NULL;
	char *result_utf8 = NULL;
	int accept = 0;
	int handled = 0;

	(void) sender;

	if (args == NULL || host == NULL) {
		return S_OK;
	}

	ICoreWebView2ScriptDialogOpeningEventArgs_get_Kind (args, &kind);
	ICoreWebView2ScriptDialogOpeningEventArgs_get_Message (args, &message_w);
	ICoreWebView2ScriptDialogOpeningEventArgs_get_DefaultText (args, &default_w);

	if (host->cb_script_dlg != NULL) {
		message_utf8 = wide_to_utf8 (message_w);
		default_utf8 = wide_to_utf8 (default_w);
		handled = host->cb_script_dlg (
			(int) kind,
			message_utf8 != NULL ? message_utf8 : "",
			default_utf8 != NULL ? default_utf8 : "",
			&accept,
			&result_utf8,
			host->script_dlg_ctx);
	}

	if (handled) {
		complete_handled (args, (int) kind, accept, result_utf8);
	} else {
		fallback_dialog (host->parent, (int) kind, message_w, default_w, args);
	}

	g_free (result_utf8);
	free (message_utf8);
	free (default_utf8);
	CoTaskMemFree (message_w);
	CoTaskMemFree (default_w);
	return S_OK;
}

void
vala_webview2_host_prepare_default_script_dialogs (bool enabled)
{
	g_prepare_default_script_dialogs = enabled ? TRUE : FALSE;
}

BOOL
vala_webview2_script_dialogs_default_enabled (void)
{
	return g_prepare_default_script_dialogs;
}

void
vala_webview2_host_set_script_dialog_handler (
	WebView2Host *host,
	WebView2GtkScriptDialogCb cb,
	void *user_data)
{
	if (host == NULL) {
		return;
	}
	host->cb_script_dlg = cb;
	host->script_dlg_ctx = user_data;
}

void
vala_webview2_host_set_default_script_dialogs_enabled (WebView2Host *host, bool enabled)
{
	if (host == NULL) {
		return;
	}
	host->default_script_dialogs = enabled ? TRUE : FALSE;
	apply_default_script_dialogs (host);
}

void
vala_webview2_script_dialogs_register_host (WebView2Host *host)
{
	ICoreWebView2 *webview;
	ScriptDialogHandler *handler;
	HRESULT hr;

	if (host == NULL || host->webview == NULL || host->script_dlg_registered) {
		return;
	}
	webview = host->webview;
	apply_default_script_dialogs (host);

	handler = (ScriptDialogHandler *) CoTaskMemAlloc (sizeof (ScriptDialogHandler));
	if (handler == NULL) {
		return;
	}
	ZeroMemory (handler, sizeof (*handler));
	handler->iface.lpVtbl = &handler->vtbl;
	handler->vtbl.QueryInterface = dlg_qi;
	handler->vtbl.AddRef = dlg_addref;
	handler->vtbl.Release = dlg_release;
	handler->vtbl.Invoke = dlg_invoke;
	handler->ref_count = 1;
	handler->host = host;

	hr = ICoreWebView2_add_ScriptDialogOpening (webview, &handler->iface, &host->tok_script_dlg);
	if (FAILED (hr)) {
		fprintf (stderr, "WebView2 add_ScriptDialogOpening failed: 0x%08lx\n",
		         (unsigned long) hr);
		ICoreWebView2ScriptDialogOpeningEventHandler_Release (&handler->iface);
		return;
	}
	ICoreWebView2ScriptDialogOpeningEventHandler_Release (&handler->iface);
	host->script_dlg_registered = TRUE;
}

void
vala_webview2_script_dialogs_unregister_host (WebView2Host *host)
{
	if (host == NULL) {
		return;
	}
	if (host->webview != NULL && host->script_dlg_registered) {
		ICoreWebView2_remove_ScriptDialogOpening (host->webview, host->tok_script_dlg);
		host->script_dlg_registered = FALSE;
	}
	host->cb_script_dlg = NULL;
	host->script_dlg_ctx = NULL;
}
