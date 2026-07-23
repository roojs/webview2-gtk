/* Bridges WebView2 COM events to the public host C API (one host per process).
 * Owns vala_webview2_emit_* (called from generated events.c) — no Vala delegate bridge.
 */

namespace Win32.Ui.WebView {

[CCode (has_target = false)]
private delegate void EventCb (void* ctx);

[CCode (has_target = false)]
private delegate void NavCompletedCb (void* ctx, bool success);

private void* g_event_ctx;
private EventCb? g_event_start;
private NavCompletedCb? g_event_completed;
private EventCb? g_event_title;

[CCode (cname = "vala_webview2_emit_navigation_starting")]
public void emit_navigation_starting () {
	if (g_event_start != null) {
		g_event_start (g_event_ctx);
	}
}

[CCode (cname = "vala_webview2_emit_navigation_completed")]
public void emit_navigation_completed (int success) {
	if (g_event_completed != null) {
		g_event_completed (g_event_ctx, success != 0);
	}
}

[CCode (cname = "vala_webview2_emit_document_title_changed")]
public void emit_document_title_changed () {
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
}

}
