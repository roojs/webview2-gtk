/* Minimal hello — script message round-trip (WebKitGTK-shaped). */

using Gtk;
using WebView2Gtk;

public static int main (string[] args) {
	var app = new Gtk.Application ("com.webview2gtk.hello", ApplicationFlags.FLAGS_NONE);
	app.activate.connect (() => {
		var html = """
			<html><body style="font-family:sans-serif;margin:2em">
			<h1>Hello WebView2</h1>
			<p>Script message: <code>window.webkit.messageHandlers.ping.postMessage</code></p>
			<pre id="out">waiting…</pre>
			<script>
			function send() {
				window.webkit.messageHandlers.ping.postMessage({ hello: "world" });
			}
			if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ping) {
				send();
			} else {
				setTimeout(send, 200);
			}
			</script>
			</body></html>
		""";

		var window = new Gtk.ApplicationWindow (app);
		window.set_title ("webview2-gtk hello");
		window.set_default_size (640, 480);

		var web = new WebView ();
		var mgr = web.get_user_content_manager ();
		mgr.script_message_received["ping"].connect ((values) => {
			var json = values.to_json ();
			print ("script-message-received::ping %s\n", json);
			var script = "document.getElementById('out').textContent = 'host saw: ' + JSON.stringify("
				+ json + ");";
			web.evaluate_javascript.begin (
				script,
				-1, null, null, null,
				(obj, res) => {
					try {
						web.evaluate_javascript.end (res);
					} catch (Error e) {
						warning ("echo failed: %s", e.message);
					}
				}
			);
		});
		mgr.register_script_message_handler ("ping", null);

		web.load_html (html, null);
		web.set_hexpand (true);
		web.set_vexpand (true);
		window.set_child (web);
		window.present ();
	});
	return app.run (args);
}
