/* Internal host layout — for COM glue + event modules (plan 4.0). */
#ifndef WIN32_UI_WEBVIEW2_HOST_PRIV_H
#define WIN32_UI_WEBVIEW2_HOST_PRIV_H

#include <windows.h>
#include <stdbool.h>
#include "win32-ui-webview2-sdk.h"
#include "webview2gtk-host-api.h"

#define WV2_MAX_SCRIPT_HANDLERS 64
#define WV2_MAX_PENDING_RESOURCES 512

typedef struct {
	int id;
	char *uri;
} WebView2PendingResource;

struct WebView2Host {
	HWND parent;
	wchar_t url[2048];
	wchar_t pending_url[2048];
	BOOL use_client_bounds;
	RECT bounds;
	ICoreWebView2Controller *controller;
	ICoreWebView2 *webview;
	BOOL ready;
	BOOL host_visible;

	/* Per-instance COM event wiring (4.3) — nav / title */
	BOOL events_registered;
	EventRegistrationToken tok_nav_completed;
	EventRegistrationToken tok_nav_starting;
	EventRegistrationToken tok_title;
	WebView2GtkEventCb cb_nav_starting;
	WebView2GtkNavCompletedCb cb_nav_completed;
	WebView2GtkEventCb cb_title_changed;
	void *event_user_data;

	/* Document response (main-frame HTTP) */
	BOOL doc_response_registered;
	EventRegistrationToken tok_doc_nav;
	EventRegistrationToken tok_doc_response;
	wchar_t *doc_nav_uri;
	WebView2GtkDocumentResponseCb cb_doc_response;
	void *doc_response_ctx;

	/* Script message handlers */
	BOOL script_msg_registered;
	EventRegistrationToken tok_script_msg;
	char *script_handler_names[WV2_MAX_SCRIPT_HANDLERS];
	size_t script_handler_count;
	wchar_t *script_inject_id;
	WebView2GtkScriptMessageCb cb_script_msg;
	void *script_msg_ctx;

	/* Downloads (DownloadStarting); jobs are process-global keyed by id */
	BOOL downloads_registered;
	EventRegistrationToken tok_download_start;
	WebView2GtkDownloadStartedCb cb_dl_started;
	WebView2GtkDownloadProgressCb cb_dl_progress;
	WebView2GtkDownloadFinishedCb cb_dl_finished;
	WebView2GtkDownloadFailedCb cb_dl_failed;
	void *dl_ctx;

	/* Web resource load lifecycle */
	BOOL resources_registered;
	BOOL resource_filter_added;
	EventRegistrationToken tok_resource_requested;
	EventRegistrationToken tok_resource_response;
	WebView2PendingResource pending_resources[WV2_MAX_PENDING_RESOURCES];
	WebView2GtkResourceStartedCb cb_res_started;
	WebView2GtkResourceFinishedCb cb_res_finished;
	WebView2GtkResourceFailedCb cb_res_failed;
	void *res_ctx;

	/* Permissions / mute / media flags */
	BOOL perm_registered;
	EventRegistrationToken tok_perm;
	BOOL enable_media_stream;
	BOOL enable_webrtc;
	BOOL is_muted;
	WebView2GtkPermissionDecideCb cb_perm_decide;
	void *perm_ctx;
};

#endif /* WIN32_UI_WEBVIEW2_HOST_PRIV_H */
