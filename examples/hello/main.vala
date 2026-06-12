/* Minimal hello — WebView2Gtk.WebView with inline HTML (GTK 4). */

using Gtk;
using WebView2Gtk;

public static int main (string[] args) {
	var app = new Gtk.Application ("com.webview2gtk.hello", ApplicationFlags.FLAGS_NONE);
	app.activate.connect (() => {
		var html = """
			<html><body style="font-family:sans-serif;margin:2em">
			<h1>Hello WebView2</h1>
			<p>Embedded via <code>WebView2Gtk.WebView</code> and <code>gdk_win32_surface_get_handle()</code>.</p>
			</body></html>
		""";

		var window = new Gtk.ApplicationWindow (app);
		window.set_title ("webview2-gtk hello");
		window.set_default_size (640, 480);

		var web = new WebView ();
		web.load_html (html, null);
		web.set_hexpand (true);
		web.set_vexpand (true);
		window.set_child (web);
		window.present ();
	});
	return app.run (args);
}
