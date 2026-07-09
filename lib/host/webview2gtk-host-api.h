/* Public C API for the embedded WebView2 host (Windows only). */

#ifndef WEBVIEW2GTK_HOST_API_H
#define WEBVIEW2GTK_HOST_API_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

bool vala_webview2_host_create_with_xywh (void *parent_hwnd, int x, int y, int width, int height, uint16_t *url);
void vala_webview2_host_set_bounds_xywh (int x, int y, int width, int height);
bool vala_webview2_host_navigate (const char *url_utf8);
bool vala_webview2_host_navigate_to_string (const char *html_utf8);
void vala_webview2_host_on_size (void *parent_hwnd);
void vala_webview2_host_destroy (void);
bool vala_webview2_host_is_ready (void);

bool vala_webview2_host_go_back (void);
bool vala_webview2_host_go_forward (void);
bool vala_webview2_host_reload (void);
bool vala_webview2_host_stop (void);
bool vala_webview2_host_get_can_go_back (void);
bool vala_webview2_host_get_can_go_forward (void);

const char *vala_webview2_host_get_source (void);
const char *vala_webview2_host_get_document_title (void);
double vala_webview2_host_get_zoom_factor (void);
bool vala_webview2_host_put_zoom_factor (double zoom);
bool vala_webview2_host_put_is_visible (bool visible);

typedef void (*WebView2GtkEventCb) (void *user_data);
typedef void (*WebView2GtkNavCompletedCb) (void *user_data, bool success);

void vala_webview2_host_set_event_handlers (
	WebView2GtkEventCb navigation_starting,
	WebView2GtkNavCompletedCb navigation_completed,
	WebView2GtkEventCb document_title_changed,
	void *user_data
);

bool vala_webview2_host_execute_script_sync (const char *script_utf8, char **result_json_out);
bool vala_webview2_host_capture_screenshot_sync (bool full_document, char **devtools_json_out);
bool vala_webview2_host_print_to_pdf_sync (const char *output_path_utf8);
bool vala_webview2_host_get_cookies_sync (const char *uri_utf8, char **cookies_text_out);

#ifdef __cplusplus
}
#endif

#endif
