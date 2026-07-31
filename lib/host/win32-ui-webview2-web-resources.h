/* WebKitGTK-shaped resource_load_started — WebResourceRequested + ResponseReceived. */

#ifndef WIN32_UI_WEBVIEW2_WEB_RESOURCES_H
#define WIN32_UI_WEBVIEW2_WEB_RESOURCES_H

#include "win32-ui-webview2-sdk.h"

#ifdef __cplusplus
extern "C" {
#endif

void vala_webview2_web_resources_register (ICoreWebView2 *webview);
void vala_webview2_web_resources_unregister (ICoreWebView2 *webview);

#ifdef __cplusplus
}
#endif

#endif /* WIN32_UI_WEBVIEW2_WEB_RESOURCES_H */
