namespace WebView2Gtk {

/**
 * WebKitGTK-shaped user content manager — script message handlers for 2.0.
 *
 * Register a named channel, then connect to the detailed
 * `script_message_received` signal. Page JS uses
 * `window.webkit.messageHandlers.<name>.postMessage(…)`.
 *
 * When bound to a WebView host, handler names are registered on that host.
 * Shared managers may bind multiple hosts (one per attached WebView).
 */
public class UserContentManager : Object {
	private Gee.HashSet<string> handlers = new Gee.HashSet<string> ();
	private Gee.ArrayList<void*> bound_hosts = new Gee.ArrayList<void*> ();

	[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_register_script_message_handler")]
	private static extern bool wv2_host_register_script_message_handler(void* host, string name);

	[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_unregister_script_message_handler")]
	private static extern bool wv2_host_unregister_script_message_handler(void* host, string name);

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
		foreach (var host in bound_hosts) {
			if (!wv2_host_register_script_message_handler(host, name)) {
				handlers.remove(name);
				return false;
			}
		}
		return true;
	}

	public void unregister_script_message_handler(string name, string? world_name) {
		if (!handlers.remove(name)) {
			return;
		}
		foreach (var host in bound_hosts) {
			wv2_host_unregister_script_message_handler(host, name);
		}
	}

	internal void bind_host(void* host) {
		if (host == null) {
			return;
		}
		foreach (var h in bound_hosts) {
			if (h == host) {
				return;
			}
		}
		bound_hosts.add(host);
		foreach (var name in handlers) {
			wv2_host_register_script_message_handler(host, name);
		}
	}

	internal void unbind_host(void* host) {
		if (host == null) {
			bound_hosts.clear();
			return;
		}
		for (var i = 0; i < bound_hosts.size; i++) {
			if (bound_hosts[i] == host) {
				bound_hosts.remove_at(i);
				return;
			}
		}
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
