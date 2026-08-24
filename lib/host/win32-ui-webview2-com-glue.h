#ifndef VALA_WIN32_UI_WEBVIEW2_COM_GLUE_H
#define VALA_WIN32_UI_WEBVIEW2_COM_GLUE_H

#include <windows.h>
#include <stdint.h>
#include <stdbool.h>

struct ICoreWebView2;
struct ICoreWebView2Controller;
struct ICoreWebView2Environment;

typedef struct WebView2Host WebView2Host;

#ifdef __cplusplus
extern "C" {
#endif

WebView2Host *vala_webview2_host_create_with_xywh (
	void *parent_hwnd, int x, int y, int width, int height, uint16_t *url);
void vala_webview2_host_set_bounds_xywh (WebView2Host *host, int x, int y, int width, int height);
bool vala_webview2_host_navigate (WebView2Host *host, const char *url_utf8);
bool vala_webview2_host_is_ready (WebView2Host *host);
void vala_webview2_host_set_ready (WebView2Host *host, bool ready);
void vala_webview2_host_set_visible_flag (WebView2Host *host, bool visible);
void vala_webview2_host_flush_pending_navigate (WebView2Host *host);

BOOL vala_webview2_com_begin_host (WebView2Host *host, HWND parent, LPCWSTR url, const RECT *bounds);

void vala_webview2_com_present_webview (HWND parent);

void vala_webview2_com_release_host (WebView2Host *host);

/* Prefer host-arg forms. No-arg getters use last-created host (4.1 debt for sync helpers). */
struct ICoreWebView2 *vala_webview2_com_get_webview (void);
struct ICoreWebView2 *vala_webview2_com_get_webview_for (WebView2Host *host);
HWND vala_webview2_com_get_parent_hwnd (void);
HWND vala_webview2_com_get_parent_hwnd_for (WebView2Host *host);
struct ICoreWebView2Controller *vala_webview2_com_get_controller_for (WebView2Host *host);
struct ICoreWebView2Environment *vala_webview2_com_get_environment (void);

void vala_webview2_com_pump_messages (void);
void vala_webview2_com_sync_await (volatile LONG *done);

uint16_t *win32_ui_utf8_to_utf16 (const char *text, int *result_length1);
char *win32_ui_utf16_to_utf8 (uint16_t *wide, int wide_length1);

#ifdef __cplusplus
}
#endif

#endif /* VALA_WIN32_UI_WEBVIEW2_COM_GLUE_H */
