/* Per-instance WebView2 navigation/title events (plan 4.3). */
#ifndef VALA_WIN32_UI_WEBVIEW2_EVENTS_H
#define VALA_WIN32_UI_WEBVIEW2_EVENTS_H

#include "win32-ui-webview2-sdk.h"

#ifdef __cplusplus
extern "C" {
#endif

struct WebView2Host;

void vala_webview2_events_register_host (struct WebView2Host *host);
void vala_webview2_events_unregister_host (struct WebView2Host *host);

/* Obsolete singleton forms — no-ops that log. Prefer *_host. */
void vala_webview2_events_register (ICoreWebView2 *webview);
void vala_webview2_events_unregister (ICoreWebView2 *webview);

#ifdef __cplusplus
}
#endif

#endif /* VALA_WIN32_UI_WEBVIEW2_EVENTS_H */
