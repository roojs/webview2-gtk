namespace WebView2Gtk {

/**
 * WebKitGTK-shaped user content manager — script message handlers for 2.0.
 *
 * Register a named channel, then connect to the detailed
 * `script_message_received` signal. Page JS uses
 * `window.webkit.messageHandlers.<name>.postMessage(…)`.
 */
public class UserContentManager : Object {
	private Gee.HashSet<string> handlers = new Gee.HashSet<string> ();
	private bool host_bound = false;

	[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_register_script_message_handler")]
	private static extern bool wv2_host_register_script_message_handler(string name);

	[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_unregister_script_message_handler")]
	private static extern bool wv2_host_unregister_script_message_handler(string name);

	/**
	 * Emitted when page JS calls `window.webkit.messageHandlers.<name>.postMessage`.
	 * Connect with a detail matching the handler name, e.g.
	 * `script_message_received["foo"]`.
	 */
	[Signal(detailed = true)]
	public signal void script_message_received(JavaScriptResult values);

	/**
	 * Registers a script message handler(WebKitGTK 6 signature).
	 *
	 * @param world_name null means the default world; non-null is accepted but
	 *                   ignored(single world on WebView2).
	 */
	public bool register_script_message_handler(string name, string? world_name) {
		if (name == null || name.length == 0) {
			return false;
		}
		if (handlers.contains(name)) {
			return false;
		}
		handlers.add(name);
		if (host_bound && !wv2_host_register_script_message_handler(name)) {
			handlers.remove(name);
			return false;
		}
		return true;
	}

	public void unregister_script_message_handler(string name, string? world_name) {
		if (!handlers.remove(name)) {
			return;
		}
		if (host_bound) {
			wv2_host_unregister_script_message_handler(name);
		}
	}

	internal void bind_host() {
		if (host_bound) {
			return;
		}
		host_bound = true;
		foreach (var name in handlers) {
			wv2_host_register_script_message_handler(name);
		}
	}

	internal void unbind_host() {
		host_bound = false;
	}

	internal void emit_script_message(string name, string message_json) {
		/* WebMessageReceived is a WebView2 event. Emitting into app code here would
		 * let callers run ExecuteScript sync(evaluate_javascript) and deadlock
		 * inside sync_await — same rule as PrintOperation's deferred signals. */
		var handler = name;
		var json = message_json;
		Idle.add(() => {
			var result = new JavaScriptResult(json);
			GLib.Signal.emit_by_name(this, "script-message-received::%s".printf(handler), result);
			return false;
		});
	}
}

}
