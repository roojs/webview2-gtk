#ifndef VALA_WIN32_UI_WEBVIEW2_COM_GLUE_H
#define VALA_WIN32_UI_WEBVIEW2_COM_GLUE_H

#include <windows.h>
#include <stdint.h>

struct ICoreWebView2;
struct ICoreWebView2Controller;

#ifdef __cplusplus
extern "C" {
#endif

BOOL vala_webview2_com_begin_host (HWND parent, LPCWSTR url, const RECT *bounds);

void vala_webview2_com_present_webview (HWND parent);

void vala_webview2_com_release_host (void);

struct ICoreWebView2 *vala_webview2_com_get_webview (void);

void vala_webview2_com_pump_messages (void);
void vala_webview2_com_sync_await (volatile LONG *done);

/* UTF-8 ↔ UTF-16 — implemented in generated/win32-wide-strings.c (Win32.Ui). */
uint16_t *win32_ui_utf8_to_utf16 (const char *text, int *result_length1);
char *win32_ui_utf16_to_utf8 (uint16_t *wide, int wide_length1);

#ifdef __cplusplus
}
#endif

#endif /* VALA_WIN32_UI_WEBVIEW2_COM_GLUE_H */
