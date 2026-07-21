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
typedef void (*WebView2GtkDocumentResponseCb) (
	void *user_data,
	int status,
	const char * const *header_names,
	const char * const *header_values,
	size_t header_count
);

void vala_webview2_host_set_event_handlers (
	WebView2GtkEventCb navigation_starting,
	WebView2GtkNavCompletedCb navigation_completed,
	WebView2GtkEventCb document_title_changed,
	void *user_data
);

void vala_webview2_host_set_document_response_handler (
	WebView2GtkDocumentResponseCb handler,
	void *user_data
);

bool vala_webview2_host_execute_script_sync (const char *script_utf8, char **result_json_out);
bool vala_webview2_host_capture_screenshot_sync (bool full_document, char **devtools_json_out);
bool vala_webview2_host_print_to_pdf_sync (const char *output_path_utf8);
bool vala_webview2_host_get_cookies_sync (const char *uri_utf8, char **cookies_text_out);
bool vala_webview2_host_add_cookie_sync (
	const char *name_utf8,
	const char *value_utf8,
	const char *domain_utf8,
	const char *path_utf8,
	bool http_only,
	bool secure
);

/* Structured ControlView walk from page Document.
 * Coordinates are screen pixels. Call from the GTK/UI thread.
 * Node ids are valid until the next a11y_walk (element cache is replaced).
 */
typedef struct webview2gtk_a11y_node {
	int id;
	int parent_id;
	int x;
	int y;
	int w;
	int h;
	char *name;
	char *role;
	char *value;
	char *uri; /* http(s) when ValuePattern exposes a URL; else empty */
	bool can_invoke;
	bool can_set_value;
} webview2gtk_a11y_node;

bool vala_webview2_host_a11y_walk (webview2gtk_a11y_node **nodes_out, size_t *count_out);
void vala_webview2_host_a11y_nodes_free (webview2gtk_a11y_node *nodes, size_t count);

typedef void (*WebView2GtkA11yForeachCb) (
	int id,
	int parent_id,
	int x,
	int y,
	int w,
	int h,
	const char *name,
	const char *role,
	const char *value,
	const char *uri,
	bool can_invoke,
	bool can_set_value,
	void *user_data
);

/* Vala-friendly: walk Document, invoke cb per node, free staging (keeps invoke cache). */
bool vala_webview2_host_a11y_walk_foreach (WebView2GtkA11yForeachCb cb, void *user_data);

bool vala_webview2_host_a11y_invoke (int id);
bool vala_webview2_host_a11y_set_value (int id, const char *utf8);
/* SetFocus only — for AT-SPI grab_focus without activating. */
bool vala_webview2_host_a11y_focus (int id);
/* Type UTF-8 via SendInput (AT-SPI generate_keyboard_event STRING). */
bool vala_webview2_host_a11y_type_text (const char *utf8);
/* Virtual-key press+release (e.g. VK_BACK = 0x08). */
bool vala_webview2_host_a11y_key_vk (unsigned short vk);

#ifdef __cplusplus
}
#endif

#endif
