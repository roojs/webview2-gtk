/* Sync ICoreWebView2_7::PrintToPdf — used by PrintOperation. */

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
	BOOL ok;
	ICoreWebView2PrintToPdfCompletedHandler handler;
	ICoreWebView2PrintToPdfCompletedHandlerVtbl vtbl;
} PrintHandler;

static HRESULT STDMETHODCALLTYPE print_qi (void *This, REFIID riid, void **ppv)
{
	if (IsEqualIID (riid, &IID_IUnknown)
	    || IsEqualIID (riid, &IID_ICoreWebView2PrintToPdfCompletedHandler)) {
		*ppv = This;
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE print_addref (void *This)
{
	(void) This;
	return 2;
}

static ULONG STDMETHODCALLTYPE print_release (void *This)
{
	(void) This;
	return 1;
}

static HRESULT STDMETHODCALLTYPE print_invoke (
	ICoreWebView2PrintToPdfCompletedHandler *This,
	HRESULT error_code,
	BOOL is_successful)
{
	PrintHandler *ph = CONTAINING_RECORD (This, PrintHandler, handler);
	ph->ok = SUCCEEDED (error_code) && is_successful;
	InterlockedExchange (&ph->done, 1);
	return S_OK;
}

static double
clamp_scale_factor (double scale_factor)
{
	if (scale_factor < 0.1) {
		return 0.1;
	}
	if (scale_factor > 2.0) {
		return 2.0;
	}
	return scale_factor;
}

static void
apply_print_settings (
	ICoreWebView2PrintSettings *settings,
	double page_width_in,
	double page_height_in,
	double margin_top_in,
	double margin_bottom_in,
	double margin_left_in,
	double margin_right_in,
	int landscape,
	double scale_factor)
{
	ICoreWebView2PrintSettings_put_ShouldPrintBackgrounds (settings, TRUE);
	ICoreWebView2PrintSettings_put_ScaleFactor (settings, clamp_scale_factor (scale_factor));
	if (page_width_in <= 0.0 || page_height_in <= 0.0) {
		return;
	}
	ICoreWebView2PrintSettings_put_PageWidth (settings, page_width_in);
	ICoreWebView2PrintSettings_put_PageHeight (settings, page_height_in);
	ICoreWebView2PrintSettings_put_MarginTop (settings, margin_top_in);
	ICoreWebView2PrintSettings_put_MarginBottom (settings, margin_bottom_in);
	ICoreWebView2PrintSettings_put_MarginLeft (settings, margin_left_in);
	ICoreWebView2PrintSettings_put_MarginRight (settings, margin_right_in);
	ICoreWebView2PrintSettings_put_Orientation (
		settings,
		landscape
			? COREWEBVIEW2_PRINT_ORIENTATION_LANDSCAPE
			: COREWEBVIEW2_PRINT_ORIENTATION_PORTRAIT);
}

static ICoreWebView2PrintSettings *
create_print_settings_with_backgrounds (ICoreWebView2 *webview)
{
	ICoreWebView2_2 *webview2 = NULL;
	ICoreWebView2Environment *environment = NULL;
	ICoreWebView2Environment6 *environment6 = NULL;
	ICoreWebView2PrintSettings *settings = NULL;
	HRESULT hr;

	if (webview == NULL) {
		return NULL;
	}
	hr = ICoreWebView2_QueryInterface (
		webview, &IID_ICoreWebView2_2, (void **) &webview2);
	if (FAILED (hr) || webview2 == NULL) {
		return NULL;
	}
	hr = ICoreWebView2_2_get_Environment (webview2, &environment);
	ICoreWebView2_2_Release (webview2);
	if (FAILED (hr) || environment == NULL) {
		return NULL;
	}
	hr = ICoreWebView2Environment_QueryInterface (
		environment, &IID_ICoreWebView2Environment6, (void **) &environment6);
	ICoreWebView2Environment_Release (environment);
	if (FAILED (hr) || environment6 == NULL) {
		return NULL;
	}
	hr = ICoreWebView2Environment6_CreatePrintSettings (environment6, &settings);
	ICoreWebView2Environment6_Release (environment6);
	if (FAILED (hr) || settings == NULL) {
		return NULL;
	}
	return settings;
}

bool
vala_webview2_host_print_to_pdf_sync (
	WebView2Host *host,
	const char *output_path_utf8,
	double page_width_in,
	double page_height_in,
	double margin_top_in,
	double margin_bottom_in,
	double margin_left_in,
	double margin_right_in,
	int landscape,
	double scale_factor)
{
	ICoreWebView2 *webview;
	ICoreWebView2_7 *webview7 = NULL;
	ICoreWebView2PrintSettings *print_settings = NULL;
	uint16_t *path_wide;
	PrintHandler ph;
	HRESULT hr;

	if (output_path_utf8 == NULL || output_path_utf8[0] == '\0') {
		return false;
	}
	webview = vala_webview2_com_get_webview_for (host);
	if (webview == NULL) {
		return false;
	}
	path_wide = win32_ui_utf8_to_utf16 (output_path_utf8, NULL);
	if (path_wide == NULL) {
		return false;
	}

	hr = ICoreWebView2_QueryInterface (webview, &IID_ICoreWebView2_7, (void **) &webview7);
	if (FAILED (hr) || webview7 == NULL) {
		free (path_wide);
		return false;
	}

	print_settings = create_print_settings_with_backgrounds (webview);
	if (print_settings != NULL) {
		apply_print_settings (
			print_settings,
			page_width_in,
			page_height_in,
			margin_top_in,
			margin_bottom_in,
			margin_left_in,
			margin_right_in,
			landscape,
			scale_factor);
	}

	ZeroMemory (&ph, sizeof (ph));
	ph.handler.lpVtbl = &ph.vtbl;
	ph.vtbl.QueryInterface = print_qi;
	ph.vtbl.AddRef = print_addref;
	ph.vtbl.Release = print_release;
	ph.vtbl.Invoke = print_invoke;

	hr = ICoreWebView2_7_PrintToPdf (
		webview7,
		(LPCWSTR) path_wide,
		print_settings,
		&ph.handler);
	ICoreWebView2_7_Release (webview7);
	if (print_settings != NULL) {
		ICoreWebView2PrintSettings_Release (print_settings);
	}
	free (path_wide);
	if (FAILED (hr)) {
		return false;
	}

	vala_webview2_com_sync_await (&ph.done);
	return ph.ok == TRUE;
}
