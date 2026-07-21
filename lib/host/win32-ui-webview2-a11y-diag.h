/* A11y Invoke diagnostics (HWND snap, event log).
 *
 * Off in normal builds. To enable:
 *   1. Set WEBVIEW2GTK_A11Y_DIAG_COMPILE to 1 below and rebuild.
 *   2. Run with WEBVIEW2GTK_A11Y_DIAG=1
 *      → log: %TEMP%\webview2gtk-a11y-diag.txt
 *   3. Uncomment a11y_diag_register(...) in win32-ui-webview2-host.vala
 */

#ifndef WIN32_UI_WEBVIEW2_A11Y_DIAG_H
#define WIN32_UI_WEBVIEW2_A11Y_DIAG_H

/* 0 = general build (diag always off). 1 = allow env WEBVIEW2GTK_A11Y_DIAG. */
#ifndef WEBVIEW2GTK_A11Y_DIAG_COMPILE
#define WEBVIEW2GTK_A11Y_DIAG_COMPILE 0
#endif

struct ICoreWebView2;

#ifdef __cplusplus
extern "C" {
#endif

/* Non-zero only when COMPILE=1 and env WEBVIEW2GTK_A11Y_DIAG enables logging. */
int vala_webview2_a11y_diag_enabled (void);

void vala_webview2_a11y_diag_register (struct ICoreWebView2 *webview);
void vala_webview2_a11y_diag_log (const char *fmt, ...);
/* Call snap_begin before Invoke, snap_end after (wait_ms). No-op if diag off. */
void vala_webview2_a11y_diag_hwnd_snap_begin (void);
void vala_webview2_a11y_diag_hwnd_snap_end (unsigned long wait_ms);

#ifdef __cplusplus
}
#endif

#endif
