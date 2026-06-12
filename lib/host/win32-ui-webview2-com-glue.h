#ifndef VALA_WIN32_UI_WEBVIEW2_COM_GLUE_H
#define VALA_WIN32_UI_WEBVIEW2_COM_GLUE_H

#include <windows.h>

struct ICoreWebView2;
struct ICoreWebView2Controller;

#ifdef __cplusplus
extern "C" {
#endif

BOOL vala_webview2_com_begin_host (HWND parent, LPCWSTR url, const RECT *bounds);

void vala_webview2_com_present_webview (HWND parent);

void vala_webview2_com_release_host (void);

#ifdef __cplusplus
}
#endif

#endif /* VALA_WIN32_UI_WEBVIEW2_COM_GLUE_H */
