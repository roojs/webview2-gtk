/* CookieManager smokes:
 *   --smoke         add_cookie before COM attach, then load_uri (bug 2026-08-25)
 *   --smoke-mirror  get_all_cookies + replace_cookies round-trip (bug 2026-09-07)
 *   --smoke-changed CookieManager.changed fires on add/replace (bug 2026-09-07)
 *
 *   webview2gtk-add-cookie.exe [url]
 *   webview2gtk-add-cookie.exe --smoke
 *   webview2gtk-add-cookie.exe --smoke-mirror
 *   webview2gtk-add-cookie.exe --smoke-changed
 *
 * See docs/bugs/done/2026-08-25-add-cookie-before-attach.md
 *     docs/bugs/done/2026-09-07-cookie-manager-get-all-replace.md
 *     docs/bugs/done/2026-09-07-cookie-manager-changed-signal.md
 */

using Gtk;
using Soup;
using WebView2Gtk;

private const string COOKIE_NAME = "wv2gtk_probe";
private const string COOKIE_VALUE = "before_attach";

private string start_uri;
private bool smoke = false;
private bool smoke_mirror = false;
private bool smoke_changed = false;
private int smoke_status = 1;
private bool smoke_done = false;
private bool add_ok = false;
private string add_err;
private bool load_finished = false;
private bool cookie_found = false;
private int changed_count = 0;

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

private bool jar_has(GLib.List<Cookie> list, string name, string value, string domain_hint) {
	foreach (unowned Cookie c in list) {
		print("all %s=%s domain=%s path=%s\n",
			c.get_name(), c.get_value(), c.get_domain(), c.get_path());
		if (c.get_name() != name || c.get_value() != value) {
			continue;
		}
		var d = c.get_domain() ?? "";
		if (d == domain_hint || d == "." + domain_hint || d.has_suffix(domain_hint)) {
			return true;
		}
	}
	return false;
}

private async void run_smoke_mirror() {
	var mgr = web.network_session.get_cookie_manager();
	print("smoke-mirror wait ready %s\n", diag_line());
	while (!web.ready) {
		Idle.add(run_smoke_mirror.callback);
		yield;
	}
	print("smoke-mirror ready %s\n", diag_line());

	var a = new Cookie("mirror_a", "one", "a.example", "/", 3600);
	a.set_http_only(false);
	a.set_secure(false);
	var b = new Cookie("mirror_b", "two", "b.example", "/", 3600);
	b.set_http_only(false);
	b.set_secure(false);

	try {
		yield mgr.add_cookie(a);
		yield mgr.add_cookie(b);
		print("smoke-mirror added a+b\n");
	} catch (Error e) {
		print("smoke-mirror add failed: %s\n", e.message);
		finish_mirror(false);
		return;
	}

	GLib.List<Cookie> all;
	try {
		all = yield CookieManagerExt.get_all_cookies(mgr);
	} catch (Error e) {
		print("smoke-mirror get_all failed: %s\n", e.message);
		finish_mirror(false);
		return;
	}
	var have_a = jar_has(all, "mirror_a", "one", "a.example");
	var have_b = jar_has(all, "mirror_b", "two", "b.example");
	print("smoke-mirror get_all have_a=%s have_b=%s count~=%u\n",
		have_a ? "yes" : "no", have_b ? "yes" : "no", all.length());
	if (!have_a || !have_b) {
		finish_mirror(false);
		return;
	}

	var replacement = new GLib.List<Cookie> ();
	var only = new Cookie("mirror_c", "three", "c.example", "/", 3600);
	only.set_http_only(false);
	only.set_secure(false);
	replacement.append(only);

	try {
		yield CookieManagerExt.replace_cookies(mgr, replacement);
		print("smoke-mirror replace ok (CookieManagerExt)\n");
	} catch (Error e) {
		print("smoke-mirror replace failed: %s\n", e.message);
		finish_mirror(false);
		return;
	}

	try {
		all = yield CookieManagerExt.get_all_cookies(mgr);
	} catch (Error e) {
		print("smoke-mirror get_all after replace failed: %s\n", e.message);
		finish_mirror(false);
		return;
	}
	have_a = jar_has(all, "mirror_a", "one", "a.example");
	have_b = jar_has(all, "mirror_b", "two", "b.example");
	var have_c = jar_has(all, "mirror_c", "three", "c.example");
	print("smoke-mirror after replace have_a=%s have_b=%s have_c=%s\n",
		have_a ? "yes" : "no", have_b ? "yes" : "no", have_c ? "yes" : "no");
	finish_mirror(!have_a && !have_b && have_c);
}

private async void run_smoke_changed() {
	var mgr = web.network_session.get_cookie_manager();
	changed_count = 0;
	mgr.changed.connect(() => {
		changed_count++;
		print("cookie_manager.changed count=%d\n", changed_count);
	});
	print("smoke-changed wait ready %s\n", diag_line());
	while (!web.ready) {
		Idle.add(run_smoke_changed.callback);
		yield;
	}
	print("smoke-changed ready %s\n", diag_line());

	var a = new Cookie("chg_a", "one", "chg.example", "/", 3600);
	a.set_http_only(false);
	a.set_secure(false);
	try {
		yield mgr.add_cookie(a);
	} catch (Error e) {
		print("smoke-changed add failed: %s\n", e.message);
		finish_changed(false);
		return;
	}
	if (changed_count < 1) {
		print("smoke-changed no signal after add_cookie\n");
		finish_changed(false);
		return;
	}
	var after_add = changed_count;

	var replacement = new GLib.List<Cookie> ();
	var only = new Cookie("chg_b", "two", "chg.example", "/", 3600);
	only.set_http_only(false);
	only.set_secure(false);
	replacement.append(only);
	try {
		yield mgr.replace_cookies(replacement);
	} catch (Error e) {
		print("smoke-changed replace failed: %s\n", e.message);
		finish_changed(false);
		return;
	}
	if (changed_count <= after_add) {
		print("smoke-changed no signal after replace_cookies\n");
		finish_changed(false);
		return;
	}
	print("smoke-changed ok count=%d\n", changed_count);
	finish_changed(true);
}

private void finish_changed(bool ok) {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	if (ok) {
		print("TEST_PASS\n");
		smoke_status = 0;
	} else {
		print("TEST_FAIL (CookieManager.changed)\n");
		smoke_status = 1;
	}
	if (window != null) {
		window.close();
	}
}

private void finish_mirror(bool ok) {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	if (ok) {
		print("TEST_PASS\n");
		smoke_status = 0;
	} else {
		print("TEST_FAIL (get_all_cookies / replace_cookies mirror)\n");
		smoke_status = 1;
	}
	if (window != null) {
		window.close();
	}
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
		if (args[i] == "--smoke-mirror") {
			smoke_mirror = true;
			continue;
		}
		if (args[i] == "--smoke-changed") {
			smoke_changed = true;
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
		status = new Gtk.Label(smoke_mirror ? "mirror…" : (smoke_changed ? "changed…" : "injecting…"));
		status.set_wrap(true);
		status.set_xalign(0);
		status.set_selectable(true);
		box.append(status);
		box.append(web);

		window.set_child(box);
		if (smoke_mirror) {
			print("startup mirror before present %s\n", diag_line());
			web.load_uri("about:blank");
			run_smoke_mirror.begin();
		} else if (smoke_changed) {
			print("startup changed before present %s\n", diag_line());
			web.load_uri("about:blank");
			run_smoke_changed.begin();
		} else {
			/* Inject on the same turn as first show — do not wait for ready/map. */
			print("startup before present %s\n", diag_line());
			inject_then_load.begin();
		}
		window.present();
		print("startup after present %s\n", diag_line());
		refresh_status();

		if (smoke || smoke_mirror || smoke_changed) {
			Timeout.add(12000, () => {
				if (!smoke_done) {
					if (smoke_mirror) {
						print("smoke-mirror timeout\n");
						finish_mirror(false);
					} else if (smoke_changed) {
						print("smoke-changed timeout\n");
						finish_changed(false);
					} else {
						check_cookies_then_finish.begin();
					}
				}
				return Source.REMOVE;
			});
		}
	});
	app.run(gtk_args);
	return (smoke || smoke_mirror || smoke_changed) ? smoke_status : 0;
}
