/* WebKitGTK-shaped resource_load_started — per WebView2Host (plan 4.3). */

#ifndef WIN32_UI_WEBVIEW2_WEB_RESOURCES_H
#define WIN32_UI_WEBVIEW2_WEB_RESOURCES_H

#include "win32-ui-webview2-sdk.h"

#ifdef __cplusplus
extern "C" {
#endif

struct WebView2Host;

void vala_webview2_web_resources_register_host (struct WebView2Host *host);
void vala_webview2_web_resources_unregister_host (struct WebView2Host *host);

void vala_webview2_web_resources_register (ICoreWebView2 *webview);
void vala_webview2_web_resources_unregister (ICoreWebView2 *webview);

#ifdef __cplusplus
}
#endif

#endif /* WIN32_UI_WEBVIEW2_WEB_RESOURCES_H */
