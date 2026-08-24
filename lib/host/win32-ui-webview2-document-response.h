/* Document response register — per WebView2Host (plan 4.3). */

#ifndef WIN32_UI_WEBVIEW2_DOCUMENT_RESPONSE_H
#define WIN32_UI_WEBVIEW2_DOCUMENT_RESPONSE_H

#include "win32-ui-webview2-sdk.h"

#ifdef __cplusplus
extern "C" {
#endif

struct WebView2Host;

void vala_webview2_document_response_register_host (struct WebView2Host *host);
void vala_webview2_document_response_unregister_host (struct WebView2Host *host);

/* Obsolete singleton forms — prefer *_host. */
void vala_webview2_document_response_register (ICoreWebView2 *webview);
void vala_webview2_document_response_unregister (ICoreWebView2 *webview);

#ifdef __cplusplus
}
#endif

#endif /* WIN32_UI_WEBVIEW2_DOCUMENT_RESPONSE_H */
