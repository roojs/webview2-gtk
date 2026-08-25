/* Public C API for the embedded WebView2 host (Windows only). */

#ifndef WEBVIEW2GTK_HOST_API_H
#define WEBVIEW2GTK_HOST_API_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque per-GTK-WebView host (ICoreWebView2Controller + document). */
typedef struct WebView2Host WebView2Host;

WebView2Host *vala_webview2_host_create_with_xywh (void *parent_hwnd, int x, int y, int width, int height, uint16_t *url);
void vala_webview2_host_set_bounds_xywh (WebView2Host *host, int x, int y, int width, int height);
bool vala_webview2_host_navigate (WebView2Host *host, const char *url_utf8);
bool vala_webview2_host_navigate_to_string (WebView2Host *host, const char *html_utf8);
void vala_webview2_host_destroy (WebView2Host *host);
bool vala_webview2_host_is_ready (WebView2Host *host);

bool vala_webview2_host_go_back (WebView2Host *host);
bool vala_webview2_host_go_forward (WebView2Host *host);
bool vala_webview2_host_reload (WebView2Host *host);
bool vala_webview2_host_stop (WebView2Host *host);
bool vala_webview2_host_get_can_go_back (WebView2Host *host);
bool vala_webview2_host_get_can_go_forward (WebView2Host *host);

const char *vala_webview2_host_get_source (WebView2Host *host);
const char *vala_webview2_host_get_document_title (WebView2Host *host);
double vala_webview2_host_get_zoom_factor (WebView2Host *host);
bool vala_webview2_host_put_zoom_factor (WebView2Host *host, double zoom);
bool vala_webview2_host_put_is_visible (WebView2Host *host, bool visible);

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
	WebView2Host *host,
	WebView2GtkEventCb navigation_starting,
	WebView2GtkNavCompletedCb navigation_completed,
	WebView2GtkEventCb document_title_changed,
	void *user_data
);

void vala_webview2_host_set_document_response_handler (
	WebView2Host *host,
	WebView2GtkDocumentResponseCb handler,
	void *user_data
);

typedef void (*WebView2GtkScriptMessageCb) (
	void *user_data,
	const char *handler_name,
	const char *message_json_utf8
);

void vala_webview2_host_set_script_message_handler (
	WebView2Host *host,
	WebView2GtkScriptMessageCb handler,
	void *user_data
);
bool vala_webview2_host_register_script_message_handler (
	WebView2Host *host,
	const char *name_utf8
);
bool vala_webview2_host_unregister_script_message_handler (
	WebView2Host *host,
	const char *name_utf8
);

typedef void (*WebView2GtkDownloadStartedCb) (
	int id,
	const char *uri,
	const char *suggested_filename,
	const char *mime_type,
	int64_t content_length,
	void *user_data
);
typedef void (*WebView2GtkDownloadProgressCb) (int id, uint64_t received, void *user_data);
typedef void (*WebView2GtkDownloadFinishedCb) (int id, void *user_data);
typedef void (*WebView2GtkDownloadFailedCb) (int id, const char *message, void *user_data);

void vala_webview2_host_set_download_handlers (
	WebView2Host *host,
	WebView2GtkDownloadStartedCb started,
	WebView2GtkDownloadProgressCb progress,
	WebView2GtkDownloadFinishedCb finished,
	WebView2GtkDownloadFailedCb failed,
	void *user_data
);
int vala_webview2_host_download_create (WebView2Host *host, const char *uri_utf8);
bool vala_webview2_host_download_start (int id, const char *dest_path_utf8, bool overwrite);
void vala_webview2_host_download_cancel (int id);

typedef void (*WebView2GtkResourceStartedCb) (
	int id,
	const char *uri_utf8,
	void *user_data
);
typedef void (*WebView2GtkResourceFinishedCb) (int id, void *user_data);
typedef void (*WebView2GtkResourceFailedCb) (
	int id,
	const char *message,
	void *user_data
);

void vala_webview2_host_set_resource_handlers (
	WebView2Host *host,
	WebView2GtkResourceStartedCb started,
	WebView2GtkResourceFinishedCb finished,
	WebView2GtkResourceFailedCb failed,
	void *user_data
);

bool vala_webview2_host_execute_script_sync (WebView2Host *host, const char *script_utf8, char **result_json_out);
bool vala_webview2_host_capture_screenshot_sync (WebView2Host *host, bool full_document, char **devtools_json_out);
bool vala_webview2_host_print_to_pdf_sync (WebView2Host *host, const char *output_path_utf8);
bool vala_webview2_host_get_cookies_sync (WebView2Host *host, const char *uri_utf8, char **cookies_text_out);
bool vala_webview2_host_add_cookie_sync (
	WebView2Host *host,
	const char *name_utf8,
	const char *value_utf8,
	const char *domain_utf8,
	const char *path_utf8,
	bool http_only,
	bool secure
);

typedef void (*WebView2GtkCookieApplyCb) (void *user_data);
void vala_webview2_host_set_cookie_apply (
	WebView2Host *host,
	WebView2GtkCookieApplyCb cb,
	void *user_data
);
void vala_webview2_host_apply_pending_cookies (WebView2Host *host);

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

bool vala_webview2_host_a11y_walk (WebView2Host *host, webview2gtk_a11y_node **nodes_out, size_t *count_out);
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
bool vala_webview2_host_a11y_walk_foreach (WebView2Host *host, WebView2GtkA11yForeachCb cb, void *user_data);

bool vala_webview2_host_a11y_invoke (int id);
bool vala_webview2_host_a11y_set_value (int id, const char *utf8);
/* SetFocus only — for AT-SPI grab_focus without activating. */
bool vala_webview2_host_a11y_focus (int id);
/* Type UTF-8 via SendInput (AT-SPI generate_keyboard_event STRING). */
bool vala_webview2_host_a11y_type_text (const char *utf8);
/* Virtual-key press+release (e.g. VK_BACK = 0x08). */
bool vala_webview2_host_a11y_key_vk (unsigned short vk);

/* Automation / inspector (WEBKIT_INSPECTOR_SERVER → CDP remote-debugging-port). */
void vala_webview2_host_set_automation_allowed (bool allowed);
bool vala_webview2_host_get_automation_allowed (void);

/* 0=ALLOW, 1=ALLOW_WITHOUT_SOUND, 2=DENY — match AutoplayPolicy */
void vala_webview2_host_set_autoplay_policy (int policy);

bool vala_webview2_host_open_dev_tools_window (WebView2Host *host);

/* Media / mute / PermissionRequested (plan 3.7 §9) — per host. */
void vala_webview2_host_set_media_flags (
	WebView2Host *host,
	bool enable_media_stream,
	bool enable_webrtc
);
bool vala_webview2_host_set_is_muted (WebView2Host *host, bool muted);
bool vala_webview2_host_get_is_muted (WebView2Host *host);

/*
 * Decide callback: return non-zero if the app handled the request.
 * When handled, *allow_out is 1=allow / 0=deny.
 * permission_kind matches COREWEBVIEW2_PERMISSION_KIND.
 */
typedef int (*WebView2GtkPermissionDecideCb) (
	int permission_kind,
	int *allow_out,
	void *user_data
);
void vala_webview2_host_set_permission_handler (
	WebView2Host *host,
	WebView2GtkPermissionDecideCb decide,
	void *user_data
);

#ifdef __cplusplus
}
#endif

#endif
