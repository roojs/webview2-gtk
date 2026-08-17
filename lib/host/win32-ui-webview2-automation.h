/* Automation / inspector attach helpers (Windows WebView2 host). */

#ifndef WIN32_UI_WEBVIEW2_AUTOMATION_H
#define WIN32_UI_WEBVIEW2_AUTOMATION_H

#include <stdbool.h>
#include <windows.h>

struct ICoreWebView2EnvironmentOptions;

#ifdef __cplusplus
extern "C" {
#endif

/* Vala WebContext.set_automation_allowed — stored for env create. */
void vala_webview2_host_set_automation_allowed (bool allowed);
bool vala_webview2_host_get_automation_allowed (void);

/*
 * Build ICoreWebView2EnvironmentOptions when WEBKIT_INSPECTOR_SERVER is set.
 * Caller must Release the result. Returns NULL when no remote-debugging args.
 */
struct ICoreWebView2EnvironmentOptions *
vala_webview2_host_create_environment_options (void);

#ifdef __cplusplus
}
#endif

#endif
