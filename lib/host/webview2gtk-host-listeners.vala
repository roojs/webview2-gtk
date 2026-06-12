/* Bridges WebView2 COM events to the public host C API (one host per process). */

namespace Win32.Ui.WebView {

private delegate void EventCb (void* ctx);
private delegate void NavCompletedCb (void* ctx, bool success);

private void* g_event_ctx;
private EventCb? g_event_start;
private NavCompletedCb? g_event_completed;
private EventCb? g_event_title;

private void on_nav_starting_wrapper () {
	if (g_event_start != null) {
		g_event_start (g_event_ctx);
	}
}

private void on_nav_completed_wrapper (bool success) {
	if (g_event_completed != null) {
		g_event_completed (g_event_ctx, success);
	}
}

private void on_title_changed_wrapper () {
	if (g_event_title != null) {
		g_event_title (g_event_ctx);
	}
}

[CCode (cname = "vala_webview2_host_set_event_handlers")]
public void set_event_handlers (
	void* navigation_starting,
	void* navigation_completed,
	void* document_title_changed,
	void* cb_user_data
) {
	g_event_ctx = cb_user_data;
	g_event_start = (EventCb?) navigation_starting;
	g_event_completed = (NavCompletedCb?) navigation_completed;
	g_event_title = (EventCb?) document_title_changed;

	if (g_event_start != null) {
		bind_navigation_starting (on_nav_starting_wrapper);
	} else {
		bind_navigation_starting (null);
	}

	if (g_event_completed != null) {
		bind_navigation_completed (on_nav_completed_wrapper);
	} else {
		bind_navigation_completed (null);
	}

	if (g_event_title != null) {
		bind_document_title_changed (on_title_changed_wrapper);
	} else {
		bind_document_title_changed (null);
	}
}

}
