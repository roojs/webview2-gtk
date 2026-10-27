/* CookieManager / NetworkSession smokes:
 *   --smoke         add_cookie before COM attach, then load_uri (bug 2026-08-25)
 *   --smoke-mirror  get_all_cookies + replace_cookies round-trip (bug 2026-09-07)
 *   --smoke-changed CookieManager.changed fires on add/replace (bug 2026-09-07)
 *   --smoke-replace-startup  large fire-and-forget replace at construct (bug 2026-09-09)
 *   --smoke-persist TEXT set_persistent_storage survives “restart” (bug 2026-09-09)
 *   --smoke-proxy   CUSTOM to TEST-NET closed proxy → navigate fails closed (plan 6.0)
 *   --smoke-proxy-direct  dummy local host proxy on, then example.com must FINISH (pass-through)
 *   --smoke-proxy-late  dummy hop, attach, then CUSTOM TEST-NET — must not paint example.com
 *   --smoke-reload-bypass  direct first load, then reload through WV2GTK_TEST_PROXY
 *
 *   webview2gtk-add-cookie.exe [url]
 *   webview2gtk-add-cookie.exe --smoke
 *   webview2gtk-add-cookie.exe --smoke-mirror
 *   webview2gtk-add-cookie.exe --smoke-changed
 *   webview2gtk-add-cookie.exe --smoke-replace-startup
 *   webview2gtk-add-cookie.exe --smoke-persist
 *   webview2gtk-add-cookie.exe --smoke-proxy
 *   webview2gtk-add-cookie.exe --smoke-proxy-direct
 *   webview2gtk-add-cookie.exe --smoke-proxy-late
 *   webview2gtk-add-cookie.exe --smoke-reload-bypass
 *
 * See docs/bugs/done/2026-08-25-add-cookie-before-attach.md
 *     docs/bugs/done/2026-09-07-cookie-manager-get-all-replace.md
 *     docs/bugs/done/2026-09-07-cookie-manager-changed-signal.md
 *     docs/bugs/done/2026-09-09-cookie-manager-replace-cookies-large-av.md
 *     docs/bugs/2026-09-09-cookie-manager-set-persistent-storage.md
 *     docs/bugs/done/2026-09-10-network-session-set-proxy-settings-stub.md
 */

using Gtk;
using Soup;
using WebView2Gtk;

private const string COOKIE_NAME = "wv2gtk_probe";
private const string COOKIE_VALUE = "before_attach";
private const string PERSIST_NAME = "wv2gtk_persist";
private const string PERSIST_VALUE = "phase1_text";

private string start_uri;
private bool smoke = false;
private bool smoke_mirror = false;
private bool smoke_changed = false;
private bool smoke_replace_startup = false;
private bool smoke_persist = false;
private bool smoke_proxy = false;
private bool smoke_proxy_direct = false;
private bool smoke_proxy_late = false;
private bool smoke_reload_bypass = false;
private bool proxy_load_failed = false;
private bool proxy_saw_example = false;
private string reload_test_uri;
private string reload_test_proxy;
private int reload_phase = 0;
private bool reload_saw_started = false;
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
	Error? ext_err = null;
	all = null;
	ext_err = null;
	CookieManagerExt.get_all_cookies_async(mgr, null, (o, r) => {
		try {
			all = CookieManagerExt.get_all_cookies_finish(mgr, r);
		} catch (Error e) {
			ext_err = e;
		}
		Idle.add(run_smoke_mirror.callback);
	});
	yield;
	if (ext_err != null) {
		print("smoke-mirror get_all failed: %s\n", ext_err.message);
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

	ext_err = null;
	var replace_ok = false;
	CookieManagerExt.replace_cookies_async(mgr, replacement, null, (o, r) => {
		try {
			replace_ok = CookieManagerExt.replace_cookies_finish(mgr, r);
		} catch (Error e) {
			ext_err = e;
		}
		Idle.add(run_smoke_mirror.callback);
	});
	yield;
	if (ext_err != null || !replace_ok) {
		print("smoke-mirror replace failed: %s\n",
			ext_err != null ? ext_err.message : "false");
		finish_mirror(false);
		return;
	}
	print("smoke-mirror replace ok (CookieManagerExt *_async/*_finish)\n");

	all = null;
	ext_err = null;
	CookieManagerExt.get_all_cookies_async(mgr, null, (o, r) => {
		try {
			all = CookieManagerExt.get_all_cookies_finish(mgr, r);
		} catch (Error e) {
			ext_err = e;
		}
		Idle.add(run_smoke_mirror.callback);
	});
	yield;
	if (ext_err != null) {
		print("smoke-mirror get_all after replace failed: %s\n", ext_err.message);
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

/**
 * TEXT jar: write via session A, reload via session B (same path).
 * SQLITE is not smoke-tested here — it calls GLib.error (process abort).
 */
private async void run_smoke_persist() {
	var path = Path.build_filename(
		Environment.get_tmp_dir(),
		"wv2gtk-smoke-persist-cookies.txt"
	);
	print("smoke-persist path=%s\n", path);
	try {
		FileUtils.remove(path);
	} catch (Error e) {
	}

	var writer = new NetworkSession();
	var writer_mgr = writer.get_cookie_manager();
	writer_mgr.set_persistent_storage(path, CookiePersistentStorage.TEXT);
	var cookie = new Cookie(PERSIST_NAME, PERSIST_VALUE, "persist.example", "/", 3600);
	cookie.set_http_only(false);
	cookie.set_secure(false);
	try {
		yield writer_mgr.add_cookie(cookie);
	} catch (Error e) {
		print("smoke-persist add failed: %s\n", e.message);
		finish_persist(false);
		return;
	}
	if (!FileUtils.test(path, FileTest.EXISTS)) {
		print("smoke-persist file missing after add\n");
		finish_persist(false);
		return;
	}

	var reader = new NetworkSession();
	var reader_mgr = reader.get_cookie_manager();
	reader_mgr.set_persistent_storage(path, CookiePersistentStorage.TEXT);
	GLib.List<Cookie> all;
	try {
		all = yield reader_mgr.get_all_cookies();
	} catch (Error e) {
		print("smoke-persist get_all failed: %s\n", e.message);
		finish_persist(false);
		return;
	}
	var found = false;
	foreach (unowned Cookie c in all) {
		if (c.get_name() == PERSIST_NAME && (c.get_value() ?? "") == PERSIST_VALUE) {
			found = true;
			break;
		}
	}
	print("smoke-persist count=%u found=%s\n", all.length(), found ? "yes" : "no");
	finish_persist(found);
}

private void finish_persist(bool ok) {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	if (ok) {
		print("TEST_PASS\n");
		smoke_status = 0;
	} else {
		print("TEST_FAIL (set_persistent_storage TEXT)\n");
		smoke_status = 1;
	}
	if (window != null) {
		window.close();
	}
}

private void finish_proxy(bool ok) {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	print(
		"smoke-proxy load_failed=%s saw_example=%s\n",
		proxy_load_failed ? "yes" : "no",
		proxy_saw_example ? "yes" : "no"
	);
	if (ok) {
		print("TEST_PASS\n");
		smoke_status = 0;
	} else {
		print("TEST_FAIL (CUSTOM proxy did not fail-closed)\n");
		smoke_status = 1;
	}
	if (window != null) {
		window.close();
	}
}

private void start_smoke_proxy() {
	/*
	 * Unreachable TEST-NET proxy. 127.0.0.1 is the pass-through
	 * sentinel — 192.0.2.1:1 must fail-closed if CUSTOM is chained.
	 */
	web.network_session.set_proxy_settings(
		NetworkProxyMode.CUSTOM,
		new NetworkProxySettings("http://192.0.2.1:1", null)
	);
	print("smoke-proxy set CUSTOM http://192.0.2.1:1 before present\n");
	web.load_failed.connect((load_event, failing_uri, error) => {
		print("smoke-proxy load_failed %s: %s\n", failing_uri, error.message);
		proxy_load_failed = true;
		Idle.add(() => {
			finish_proxy(true);
			return Source.REMOVE;
		});
		return false;
	});
	web.load_changed.connect((load_event) => {
		if (load_event != LoadEvent.FINISHED || smoke_done) {
			return;
		}
		var title = web.get_title() ?? "";
		print("smoke-proxy FINISHED title=%s\n", title);
		if (title.down().contains("example domain")) {
			proxy_saw_example = true;
			finish_proxy(false);
		}
	});
	web.load_uri("https://example.com/");
}

private void finish_proxy_direct(bool ok) {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	print(
		"smoke-proxy-direct load_failed=%s saw_example=%s\n",
		proxy_load_failed ? "yes" : "no",
		proxy_saw_example ? "yes" : "no"
	);
	if (ok) {
		print("TEST_PASS\n");
		smoke_status = 0;
	} else {
		print("TEST_FAIL (dummy local host proxy did not load Example Domain)\n");
		smoke_status = 1;
	}
	if (window != null) {
		window.close();
	}
}

/**
 * Consumer bootstrap: local host proxy already on via dummy CUSTOM. This
 * view’s session is DEFAULT — no extra upstream. Pass = example.com paints.
 */
private void start_smoke_proxy_direct() {
	print("smoke-proxy-direct load https://example.com/ (pass-through)\n");
	web.load_failed.connect((load_event, failing_uri, error) => {
		print("smoke-proxy-direct load_failed %s: %s\n", failing_uri, error.message);
		if (failing_uri != null && failing_uri.down().has_prefix("about:")) {
			return false;
		}
		proxy_load_failed = true;
		Idle.add(() => {
			finish_proxy_direct(false);
			return Source.REMOVE;
		});
		return false;
	});
	web.load_changed.connect((load_event) => {
		if (load_event != LoadEvent.FINISHED || smoke_done) {
			return;
		}
		var title = web.get_title() ?? "";
		print("smoke-proxy-direct FINISHED title=%s\n", title);
		if (title.down().contains("example domain")) {
			proxy_saw_example = true;
			finish_proxy_direct(true);
		}
	});
	web.load_uri("https://example.com/");
}

private bool smoke_proxy_late_started = false;

private void start_smoke_proxy_late_navigate() {
	if (smoke_proxy_late_started || smoke_done) {
		return;
	}
	smoke_proxy_late_started = true;
	print("smoke-proxy-late set CUSTOM http://192.0.2.1:1 after attach\n");
	web.network_session.set_proxy_settings(
		NetworkProxyMode.CUSTOM,
		new NetworkProxySettings("http://192.0.2.1:1", null)
	);
	web.load_failed.connect((load_event, failing_uri, error) => {
		print("smoke-proxy-late load_failed %s: %s\n", failing_uri, error.message);
		if (failing_uri != null && failing_uri.down().has_prefix("about:")) {
			return false;
		}
		proxy_load_failed = true;
		Idle.add(() => {
			finish_proxy(true);
			return Source.REMOVE;
		});
		return false;
	});
	web.load_changed.connect((load_event) => {
		if (load_event != LoadEvent.FINISHED || smoke_done) {
			return;
		}
		var title = web.get_title() ?? "";
		print("smoke-proxy-late FINISHED title=%s\n", title);
		if (title.down().contains("example domain")) {
			proxy_saw_example = true;
			finish_proxy(false);
		}
	});
	web.load_uri("https://example.com/");
}

private void start_smoke_proxy_late() {
	print("smoke-proxy-late wait for ready then CUSTOM TEST-NET\n");
	Timeout.add(100, () => {
		if (smoke_done) {
			return Source.REMOVE;
		}
		if (!web.ready) {
			return Source.CONTINUE;
		}
		start_smoke_proxy_late_navigate();
		return Source.REMOVE;
	});
}

private void finish_reload_bypass(bool ok, string why) {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	if (ok) {
		print("TEST_PASS\n");
		smoke_status = 0;
	} else {
		print("TEST_FAIL (reload bypass: %s)\n", why);
		smoke_status = 1;
	}
	if (window != null) {
		window.close();
	}
}

private void start_smoke_reload_bypass() {
	if (reload_test_uri == "" || reload_test_proxy == "") {
		finish_reload_bypass(false, "WV2GTK_TEST_URI or WV2GTK_TEST_PROXY is not set");
		return;
	}
	web.network_session.set_proxy_settings(
		NetworkProxyMode.CUSTOM,
		new NetworkProxySettings(reload_test_proxy, null)
	);
	print("smoke-reload-bypass first load through configured upstream\n");
	web.load_failed.connect((load_event, failing_uri, error) => {
		if (smoke_done || (failing_uri != null && failing_uri.down().has_prefix("about:"))) {
			return false;
		}
		print("smoke-reload-bypass load_failed phase=%d uri=%s: %s\n",
			reload_phase, failing_uri, error.message);
		finish_reload_bypass(false, "load failed in phase %d".printf(reload_phase));
		return false;
	});
	web.load_changed.connect((load_event) => {
		if (smoke_done) {
			return;
		}
		if (load_event == LoadEvent.STARTED && reload_phase == 2) {
			reload_saw_started = true;
			print("smoke-reload-bypass SECOND_LOAD_STARTED\n");
			return;
		}
		if (load_event != LoadEvent.FINISHED) {
			return;
		}
		if (reload_phase == 0) {
			reload_phase = 1;
			print("smoke-reload-bypass FIRST_LOAD_FINISHED\n");
			/* Leave the completion callback before submitting another navigation. */
			Timeout.add(100, () => {
				if (smoke_done) {
					return Source.REMOVE;
				}
				reload_phase = 2;
				reload_saw_started = false;
				var started = GLib.get_monotonic_time();
				web.reload_bypass_cache();
				var elapsed_ms = (GLib.get_monotonic_time() - started) / 1000.0;
				print("smoke-reload-bypass RELOAD_RETURNED elapsed_ms=%.1f\n", elapsed_ms);
				if (elapsed_ms > 1000.0) {
					finish_reload_bypass(false, "reload call took %.1f ms".printf(elapsed_ms));
				}
				return Source.REMOVE;
			});
			return;
		}
		if (reload_phase == 2) {
			print("smoke-reload-bypass SECOND_LOAD_FINISHED\n");
			finish_reload_bypass(
				reload_saw_started,
				reload_saw_started ? "" : "second load had no STARTED event"
			);
		}
	});
	web.load_uri(reload_test_uri);
}

private string big_cookie_value(int len) {
	var sb = new StringBuilder();
	for (var i = 0; i < len; i++) {
		sb.append_c((char) ('a' + (i % 26)));
	}
	return sb.str;
}

private GLib.List<Cookie> build_large_replace_list() {
	var list = new GLib.List<Cookie> ();
	const int COUNT = 320;
	for (var i = 0; i < COUNT; i++) {
		var domain = "h%03d.example".printf(i % 40);
		var name = "n%03d".printf(i);
		string value;
		if (i == 10 || i == 200) {
			value = big_cookie_value(3500);
		} else {
			value = "v%d".printf(i);
		}
		var c = new Cookie(name, value, domain, "/", 3600);
		c.set_http_only(false);
		c.set_secure(false);
		list.append(c);
	}
	return list;
}

/**
 * Fire-and-forget replace_cookies_async at construct with a large multi-host
 * list (incl. oversized values), overlapping load_uri — must not AV.
 */
private void start_smoke_replace_startup() {
	var mgr = web.network_session.get_cookie_manager();
	var list = build_large_replace_list();
	print("smoke-replace-startup fire replace count=%u ready=%s\n",
		list.length(), web.ready ? "yes" : "no");
	CookieManagerExt.replace_cookies_async(mgr, list, null, (o, r) => {
		Error? err = null;
		var ok = false;
		/* Use async source object — this frame returns before the callback. */
		var cm = (CookieManager) o;
		try {
			ok = CookieManagerExt.replace_cookies_finish(cm, r);
		} catch (Error e) {
			err = e;
		}
		Idle.add(() => {
			verify_smoke_replace_startup.begin(ok, err);
			return Source.REMOVE;
		});
	});
	/* Overlap with other WebView / network work while replace runs. */
	web.load_uri("about:blank");
	web.load_uri("https://example.com/");
}

private async void verify_smoke_replace_startup(bool replace_ok, Error? err) {
	if (smoke_done) {
		return;
	}
	if (err != null || !replace_ok) {
		print("smoke-replace-startup replace failed: %s\n",
			err != null ? err.message : "false");
		finish_replace_startup(false);
		return;
	}
	print("smoke-replace-startup replace finished, verifying jar\n");
	var mgr = web.network_session.get_cookie_manager();
	GLib.List<Cookie> all;
	try {
		all = yield mgr.get_all_cookies();
	} catch (Error e) {
		print("smoke-replace-startup get_all failed: %s\n", e.message);
		finish_replace_startup(false);
		return;
	}
	var have_small = false;
	var have_big = false;
	foreach (unowned Cookie c in all) {
		var name = c.get_name();
		var value = c.get_value() ?? "";
		var d = c.get_domain() ?? "";
		if (name == "n000" && value == "v0"
			&& (d == "h000.example" || d == ".h000.example" || d.has_suffix("h000.example"))) {
			have_small = true;
		}
		if (name == "n010" && value.length >= 3000) {
			have_big = true;
		}
	}
	print("smoke-replace-startup count=%u have_small=%s have_big=%s\n",
		all.length(), have_small ? "yes" : "no", have_big ? "yes" : "no");
	finish_replace_startup(all.length() >= 300 && have_small && have_big);
}

private void finish_replace_startup(bool ok) {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	if (ok) {
		print("TEST_PASS\n");
		smoke_status = 0;
	} else {
		print("TEST_FAIL (replace_cookies large startup)\n");
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
	reload_test_uri = "";
	reload_test_proxy = "";
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
		if (args[i] == "--smoke-replace-startup") {
			smoke_replace_startup = true;
			continue;
		}
		if (args[i] == "--smoke-persist") {
			smoke_persist = true;
			continue;
		}
		if (args[i] == "--smoke-proxy") {
			smoke_proxy = true;
			continue;
		}
		if (args[i] == "--smoke-proxy-direct") {
			smoke_proxy_direct = true;
			continue;
		}
		if (args[i] == "--smoke-proxy-late") {
			smoke_proxy_late = true;
			continue;
		}
		if (args[i] == "--smoke-reload-bypass") {
			smoke_reload_bypass = true;
			continue;
		}
		if (args[i].has_prefix("-")) {
			gtk_args += args[i];
			continue;
		}
		start_uri = args[i];
	}
	if (smoke_reload_bypass) {
		var configured_uri = Environment.get_variable("WV2GTK_TEST_URI");
		var configured_proxy = Environment.get_variable("WV2GTK_TEST_PROXY");
		if (configured_uri != null) {
			reload_test_uri = configured_uri;
		}
		if (configured_proxy != null) {
			reload_test_proxy = configured_proxy;
		}
	}

	var app = new Gtk.Application("com.webview2gtk.add-cookie", ApplicationFlags.FLAGS_NONE);
	app.activate.connect(() => {
		window = new Gtk.ApplicationWindow(app);
		window.set_title("webview2-gtk add-cookie");
		window.set_default_size(800, 560);

		if (smoke_proxy || smoke_proxy_direct || smoke_proxy_late || smoke_reload_bypass) {
			var session = new NetworkSession(null, null);
			session.set_proxy_settings(
				NetworkProxyMode.CUSTOM,
				new NetworkProxySettings("http://127.0.0.1", null)
			);
		}
		web = new WebView();
		web.set_hexpand(true);
		web.set_vexpand(true);
		web.load_changed.connect(on_load_changed);

		var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
		box.set_margin_start(8);
		box.set_margin_end(8);
		box.set_margin_top(8);
		box.set_margin_bottom(8);
		status = new Gtk.Label(
			smoke_mirror ? "mirror…"
			: (smoke_changed ? "changed…"
			: (smoke_replace_startup ? "replace-startup…"
			: (smoke_persist ? "persist…"
			: ((smoke_proxy || smoke_proxy_direct || smoke_proxy_late || smoke_reload_bypass) ? "proxy…" : "injecting…")))));
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
		} else if (smoke_replace_startup) {
			print("startup replace-startup before present %s\n", diag_line());
			start_smoke_replace_startup();
		} else if (smoke_persist) {
			print("startup persist before present %s\n", diag_line());
			run_smoke_persist.begin();
		} else if (smoke_proxy) {
			print("startup proxy before present %s\n", diag_line());
			/* Must latch --proxy-server before first present/env create. */
			start_smoke_proxy();
		} else if (smoke_proxy_direct) {
			print("startup proxy-direct before present %s\n", diag_line());
			start_smoke_proxy_direct();
		} else if (smoke_proxy_late) {
			print("startup proxy-late before present %s\n", diag_line());
			start_smoke_proxy_late();
		} else if (smoke_reload_bypass) {
			print("startup reload-bypass before present %s\n", diag_line());
			start_smoke_reload_bypass();
		} else {
			/* Inject on the same turn as first show — do not wait for ready/map. */
			print("startup before present %s\n", diag_line());
			inject_then_load.begin();
		}
		window.present();
		print("startup after present %s\n", diag_line());
		refresh_status();

		if (smoke || smoke_mirror || smoke_changed || smoke_replace_startup
		    || smoke_persist || smoke_proxy || smoke_proxy_direct
		    || smoke_proxy_late || smoke_reload_bypass) {
			var timeout_ms = smoke_replace_startup ? 60000
				: ((smoke_proxy_direct || smoke_proxy_late || smoke_reload_bypass) ? 60000 : 12000);
			Timeout.add(timeout_ms, () => {
				if (!smoke_done) {
					if (smoke_mirror) {
						print("smoke-mirror timeout\n");
						finish_mirror(false);
					} else if (smoke_changed) {
						print("smoke-changed timeout\n");
						finish_changed(false);
					} else if (smoke_replace_startup) {
						print("smoke-replace-startup timeout\n");
						finish_replace_startup(false);
					} else if (smoke_persist) {
						print("smoke-persist timeout\n");
						finish_persist(false);
					} else if (smoke_proxy) {
						/* Hung / no Example Domain ⇒ fail-closed ⇒ pass. */
						print("smoke-proxy timeout (treat as fail-closed)\n");
						finish_proxy(!proxy_saw_example);
					} else if (smoke_proxy_direct) {
						print("smoke-proxy-direct timeout\n");
						finish_proxy_direct(false);
					} else if (smoke_proxy_late) {
						print("smoke-proxy-late timeout\n");
						if (!smoke_proxy_late_started) {
							finish_proxy(false);
						} else {
							finish_proxy(!proxy_saw_example);
						}
					} else if (smoke_reload_bypass) {
						print("smoke-reload-bypass timeout phase=%d\n", reload_phase);
						finish_reload_bypass(false, "timeout in phase %d".printf(reload_phase));
					} else {
						check_cookies_then_finish.begin();
					}
				}
				return Source.REMOVE;
			});
		}
	});
	app.run(gtk_args);
	return (smoke || smoke_mirror || smoke_changed || smoke_replace_startup
	    || smoke_persist || smoke_proxy || smoke_proxy_direct
	    || smoke_proxy_late || smoke_reload_bypass)
		? smoke_status : 0;
}
