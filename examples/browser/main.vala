/* Trivial GTK 4 browser — back, forward, reload, URL bar. */

using Gtk;
using WebView2Gtk;

private WebView web;
private Gtk.Entry url_entry;

private void sync_url_entry () {
	if (web.ready) {
		var u = web.get_uri ();
		if (u.length > 0) {
			url_entry.text = u;
		}
	}
}

public static int main (string[] args) {
	var start = "https://example.com/";
	if (args.length > 1) {
		start = args[1];
	}

	var app = new Gtk.Application ("com.webview2gtk.browser", ApplicationFlags.FLAGS_NONE);
	app.activate.connect (() => {
		var window = new Gtk.ApplicationWindow (app);
		window.set_title ("webview2-gtk browser");
		window.set_default_size (960, 640);

		var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
		var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
		bar.set_margin_start (4);
		bar.set_margin_end (4);
		bar.set_margin_top (4);
		bar.set_margin_bottom (4);

		var back_btn = new Gtk.Button.from_icon_name ("go-previous-symbolic");
		var fwd_btn = new Gtk.Button.from_icon_name ("go-next-symbolic");
		var reload_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
		url_entry = new Gtk.Entry () { text = start, hexpand = true };
		var go_btn = new Gtk.Button.with_label ("Go");

		web = new WebView ();
		web.load_uri (start);
		web.set_hexpand (true);
		web.set_vexpand (true);

		back_btn.clicked.connect (() => { web.go_back (); sync_url_entry (); });
		fwd_btn.clicked.connect (() => { web.go_forward (); sync_url_entry (); });
		reload_btn.clicked.connect (() => { web.reload (); });
		go_btn.clicked.connect (() => { web.load_uri (url_entry.text); });
		url_entry.activate.connect (() => { web.load_uri (url_entry.text); });

		bar.append (back_btn);
		bar.append (fwd_btn);
		bar.append (reload_btn);
		bar.append (url_entry);
		bar.append (go_btn);

		root.append (bar);
		root.append (web);
		window.set_child (root);
		window.present ();
	});
	/* GApplication rejects unknown positional args — strip URL before run. */
	return app.run (new string[] { args[0] });
}
