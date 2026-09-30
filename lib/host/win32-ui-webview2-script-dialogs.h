/* ScriptDialogOpening — WebKitGTK WebView.script_dialog (per host). */

#ifndef WIN32_UI_WEBVIEW2_SCRIPT_DIALOGS_H
#define WIN32_UI_WEBVIEW2_SCRIPT_DIALOGS_H

#include <stdbool.h>

#include "win32-ui-webview2-sdk.h"

#ifdef __cplusplus
extern "C" {
#endif

struct WebView2Host;

/* Value copied onto the next host at create, before the controller callback. */
void vala_webview2_host_prepare_default_script_dialogs (bool enabled);
BOOL vala_webview2_script_dialogs_default_enabled (void);

void vala_webview2_script_dialogs_register_host (struct WebView2Host *host);
void vala_webview2_script_dialogs_unregister_host (struct WebView2Host *host);

#ifdef __cplusplus
}
#endif

#endif /* WIN32_UI_WEBVIEW2_SCRIPT_DIALOGS_H */
