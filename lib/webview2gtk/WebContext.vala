[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_automation_allowed")]
extern void wv2_host_set_automation_allowed(bool allowed);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_accept_language")]
extern void wv2_host_set_accept_language(string accept_language);

namespace WebView2Gtk {

/**
 * WebKitGTK-shaped web context — automation allow + session signal.
 *
 * Default singleton via {@link get_default}, matching WebKit.WebContext.
 *
 * On Windows, {@link set_automation_allowed} notifies the host. CDP listen
 * comes from env ''WEBKIT_INSPECTOR_SERVER'' (host:port) at WebView2
 * environment create → ''--remote-debugging-port''.
 */
public class WebContext : Object {
	private static WebContext? default_context = null;

	private bool automation_allowed = false;
	private NetworkSession? automation_network_session = null;
	private bool automation_started_emitted = false;
	private bool controlled_webview_seen = false;

	/** WebKitGTK-shaped — automation client connected / session ready. */
	public signal void automation_started(AutomationSession session);

	public WebContext() {
	}

	public static unowned WebContext get_default() {
		if (WebContext.default_context == null) {
			WebContext.default_context = new WebContext();
		}
		return WebContext.default_context;
	}

	public void set_automation_allowed(bool allowed) {
		this.automation_allowed = allowed;
		wv2_host_set_automation_allowed(allowed);
		this.maybe_emit_automation_started();
	}

	public bool is_automation_allowed() {
		return this.automation_allowed;
	}

	public void set_preferred_languages(string[]? languages) {
		if (languages == null || languages.length == 0) {
			return;
		}
		var normalized = new Gee.ArrayList<string>();
		foreach (var lang in languages) {
			if (lang == "") {
				continue;
			}
			var folded = lang.casefold();
			if (folded == "c" || folded == "posix") {
				normalized.add("en-US");
			} else {
				normalized.add(lang.replace("_", "-"));
			}
		}
		if (normalized.is_empty) {
			wv2_host_set_accept_language("en");
			return;
		}
		var delta = normalized.size < 10 ? 10 : (normalized.size < 20 ? 5 : 1);
		var parts = new Gee.ArrayList<string>();
		for (var i = 0; i < normalized.size; i++) {
			var part = normalized[i];
			var quality = 100 - i * delta;
			if (quality > 0 && quality < 100) {
				parts.add("%s;q=%.2f".printf(part, quality / 100.0));
			} else {
				parts.add(part);
			}
		}
		wv2_host_set_accept_language(string.join(",", parts.to_array()));
	}

	/**
	 * Network session for automation-controlled views(WebKitGTK shape).
	 */
	public NetworkSession? get_network_session_for_automation() {
		if (this.automation_network_session == null) {
			this.automation_network_session = new NetworkSession();
		}
		return this.automation_network_session;
	}

	/**
	 * A {@link WebView} with {@link WebView.is_controlled_by_automation} was created.
	 * Session emit is deferred so callers can connect {@link automation_started} first.
	 */
	internal void register_controlled_webview(WebView view) {
		this.controlled_webview_seen = true;
		Idle.add(() => {
			this.maybe_emit_automation_started();
			return false;
		});
	}

	private void maybe_emit_automation_started() {
		if (!this.automation_allowed
		    || !this.controlled_webview_seen
		    || this.automation_started_emitted) {
			return;
		}
		this.automation_started_emitted = true;
		var session = new AutomationSession();
		this.automation_started(session);
	}
}

}
