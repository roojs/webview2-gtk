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

/* 0=ALLOW, 1=ALLOW_WITHOUT_SOUND, 2=DENY — match AutoplayPolicy */
void vala_webview2_host_set_autoplay_policy (int policy);

/*
 * Build ICoreWebView2EnvironmentOptions when WEBKIT_INSPECTOR_SERVER is set
 * and/or autoplay DENY needs --autoplay-policy=. Caller must Release.
 * Returns NULL when no additional browser args are needed.
 */
struct ICoreWebView2EnvironmentOptions *
vala_webview2_host_create_environment_options (void);

#ifdef __cplusplus
}
#endif

#endif
