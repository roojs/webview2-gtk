/* Repro: CookieManager.add_cookie before WebView COM attach.
 *
 * Construct WebView, add_cookie, then load_uri — no wait for ready/map.
 * Pending navigate already queues; cookies currently do not (add_cookie failed).
 *
 *   webview2gtk-add-cookie.exe [url]
 *   --smoke        inject + load, assert cookie in jar after FINISHED, quit
 *
 * See docs/bugs/done/2026-08-25-add-cookie-before-attach.md
 */

using Gtk;
using Soup;
using WebView2Gtk;

private const string COOKIE_NAME = "wv2gtk_probe";
private const string COOKIE_VALUE = "before_attach";

private string start_uri;
private bool smoke = false;
private int smoke_status = 1;
private bool smoke_done = false;
private bool add_ok = false;
private string add_err;
private bool load_finished = false;
private bool cookie_found = false;

private WebView? web = null;
private Gtk.Label status;
private Gtk.ApplicationWindow? window = null;

private string cookie_domain(string uri) {
	try {
		var parsed = GLib.Uri.parse(uri, GLib.UriFlags.NONE);
		var host = parsed.get_host();
		if (host != null && host != "") {
			return host;
		}
	} catch (Error e) {
	}
	return "example.com";
}

private string diag_line() {
	if (web == null) {
		return "web: (null)";
	}
	return "ready=%s mapped=%s size=%dx%d uri=%s add_ok=%s cookie_found=%s".printf(
		web.ready ? "yes" : "no",
		web.get_mapped() ? "yes" : "no",
		web.get_width(),
		web.get_height(),
		web.get_uri(),
		add_ok ? "yes" : "no",
		cookie_found ? "yes" : "no"
	);
}

private void refresh_status() {
	status.label = "%s\nadd_err=%s\nload_finished=%s".printf(
		diag_line(),
		add_err == null || add_err == "" ? "(none)" : add_err,
		load_finished ? "yes" : "no"
	);
}

private async void inject_then_load() {
	var domain = cookie_domain(start_uri);
	var cookie = new Cookie(COOKIE_NAME, COOKIE_VALUE, domain, "/", 3600);
	cookie.set_http_only(false);
	cookie.set_secure(start_uri.has_prefix("https:"));
	print("inject begin %s domain=%s\n", diag_line(), domain);
	try {
		yield web.network_session.get_cookie_manager().add_cookie(cookie);
		add_ok = true;
		print("add_cookie ok %s\n", diag_line());
	} catch (Error e) {
		add_ok = false;
		add_err = e.message;
		print("add_cookie failed: %s %s\n", e.message, diag_line());
	}
	print("load_uri after add_cookie %s\n", diag_line());
	web.load_uri(start_uri);
	refresh_status();
}

private async void check_cookies_then_finish() {
	try {
		var list = yield web.network_session.get_cookie_manager().get_cookies(start_uri);
		foreach (unowned Cookie c in list) {
			print("jar %s=%s domain=%s\n", c.get_name(), c.get_value(), c.get_domain());
			if (c.get_name() == COOKIE_NAME && c.get_value() == COOKIE_VALUE) {
				cookie_found = true;
			}
		}
	} catch (Error e) {
		print("get_cookies failed: %s\n", e.message);
	}
	refresh_status();
	finish_smoke();
}

private void on_load_changed(LoadEvent load_event) {
	print("load_changed %d %s\n", (int) load_event, diag_line());
	if (load_event == LoadEvent.FINISHED) {
		load_finished = true;
		if (smoke) {
			Idle.add(() => {
				check_cookies_then_finish.begin();
				return Source.REMOVE;
			});
		} else {
			refresh_status();
		}
	}
}

private void finish_smoke() {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	refresh_status();
	var ok = add_ok && load_finished && cookie_found;
	print("smoke %s\n", diag_line());
	print("smoke add_ok=%s add_err=%s load_finished=%s cookie_found=%s\n",
		add_ok ? "yes" : "no",
		add_err == null || add_err == "" ? "(none)" : add_err,
		load_finished ? "yes" : "no",
		cookie_found ? "yes" : "no");
	if (ok) {
		print("TEST_PASS\n");
		smoke_status = 0;
	} else {
		print("TEST_FAIL (add_cookie before attach / cookie missing after load)\n");
		smoke_status = 1;
	}
	if (window != null) {
		window.close();
	}
}

public static int main(string[] args) {
	start_uri = "https://example.com/";
	add_err = "";
	string[] gtk_args = {};
	gtk_args += args[0];
	for (var i = 1; i < args.length; i++) {
		if (args[i] == "--smoke") {
			smoke = true;
			continue;
		}
		if (args[i].has_prefix("-")) {
			gtk_args += args[i];
			continue;
		}
		start_uri = args[i];
	}

	var app = new Gtk.Application("com.webview2gtk.add-cookie", ApplicationFlags.FLAGS_NONE);
	app.activate.connect(() => {
		window = new Gtk.ApplicationWindow(app);
		window.set_title("webview2-gtk add-cookie");
		window.set_default_size(800, 560);

		web = new WebView();
		web.set_hexpand(true);
		web.set_vexpand(true);
		web.load_changed.connect(on_load_changed);

		var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
		box.set_margin_start(8);
		box.set_margin_end(8);
		box.set_margin_top(8);
		box.set_margin_bottom(8);
		status = new Gtk.Label("injecting…");
		status.set_wrap(true);
		status.set_xalign(0);
		status.set_selectable(true);
		box.append(status);
		box.append(web);

		window.set_child(box);
		/* Inject on the same turn as first show — do not wait for ready/map. */
		print("startup before present %s\n", diag_line());
		inject_then_load.begin();
		window.present();
		print("startup after present %s\n", diag_line());
		refresh_status();

		if (smoke) {
			Timeout.add(12000, () => {
				if (!smoke_done) {
					check_cookies_then_finish.begin();
				}
				return Source.REMOVE;
			});
		}
	});
	app.run(gtk_args);
	return smoke ? smoke_status : 0;
}
