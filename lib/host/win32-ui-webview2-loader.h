#ifndef VALA_WIN32_UI_WEBVIEW2_LOADER_H
#define VALA_WIN32_UI_WEBVIEW2_LOADER_H

#include <windows.h>

struct ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler;

#ifdef __cplusplus
extern "C" {
#endif

/* Load WebView2Loader.dll and CoInitializeEx (apartment). Safe to call once. */
BOOL vala_webview2_loader_init (void);

/* Async; handler must stay alive until Invoke runs. */
HRESULT vala_webview2_loader_create_environment (
	struct ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *handler);

#ifdef __cplusplus
}
#endif

#endif /* VALA_WIN32_UI_WEBVIEW2_LOADER_H */
