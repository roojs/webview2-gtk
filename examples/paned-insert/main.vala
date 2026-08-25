/* Repro: orphaned browser stack + automation WebViews (consumer sign-in path).
 *
 * Login: paned start = login panel; browser Stack (primary+mgmt) constructed orphaned.
 * Sign-in: set_start_child(browser_stack) + load_uri (often 0×0), then end-child
 * churn like session-loading, then second load_uri at real size.
 * Both WebViews use WebViewAuto + WEBKIT_INSPECTOR_SERVER (CDP env options).
 *
 * Expect primary load_changed FINISHED. Fail = blank / never finished.
 *
 *   webview2gtk-paned-insert.exe [url]
 *   --auto-signin
 *   --workaround   Idle after set_start_child before load_uri
 *   --smoke        auto-signin, assert FINISHED + size, quit
 *
 * See docs/bugs/2026-08-24-pending-navigate-first-paned-insert.md
 */

using Gtk;
using WebView2Gtk;

private string start_uri;
private bool auto_signin = false;
private bool use_workaround = false;
private bool smoke = false;
private int smoke_status = 1;
private bool smoke_done = false;
private bool primary_finished = false;
private bool signed_in = false;
private int load_uri_count = 0;

private WebView? primary = null;
private WebView? management = null;
private Gtk.Label status;
private Gtk.Stack browser_stack;
private Gtk.Paned paned;
private Gtk.Box? login_panel = null;
private Gtk.Box? session_loading = null;
private Gtk.Box? sidebar = null;
private Gtk.ApplicationWindow? window = null;

private Gtk.Widget wrap_webview(WebView view) {
	var browser = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
	browser.set_hexpand(true);
	browser.set_vexpand(true);

	var overlay = new Gtk.Overlay();
	overlay.set_hexpand(true);
	overlay.set_vexpand(true);

	var scrolled = new Gtk.ScrolledWindow();
	scrolled.set_hexpand(true);
	scrolled.set_vexpand(true);

	var inner = new Gtk.Overlay();
	inner.set_hexpand(true);
	inner.set_vexpand(true);

	view.set_hexpand(true);
	view.set_vexpand(true);
	inner.set_child(view);
	scrolled.set_child(inner);
	overlay.set_child(scrolled);

	var freeze = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
	freeze.set_visible(false);
	overlay.add_overlay(freeze);

	browser.append(overlay);
	return browser;
}

private string diag_line(WebView? view, string name) {
	if (view == null) {
		return "%s: (null)".printf(name);
	}
	return "%s ready=%s mapped=%s size=%dx%d opacity=%.2f uri=%s title=%s".printf(
		name,
		view.ready ? "yes" : "no",
		view.get_mapped() ? "yes" : "no",
		view.get_width(),
		view.get_height(),
		view.get_opacity(),
		view.get_uri(),
		view.get_title()
	);
}

private void refresh_status() {
	status.label = "%s\n%s\nprimary_finished=%s loads=%d\npaned_start=%s".printf(
		diag_line(primary, "primary"),
		diag_line(management, "mgmt"),
		primary_finished ? "yes" : "no",
		load_uri_count,
		paned.get_start_child() == browser_stack ? "browser_stack" : "login_panel"
	);
}

private void on_primary_load_changed(LoadEvent load_event) {
	print("primary load_changed %d %s\n", (int) load_event, diag_line(primary, "primary"));
	if (load_event == LoadEvent.FINISHED) {
		primary_finished = true;
		if (smoke) {
			Idle.add(() => {
				finish_smoke();
				return Source.REMOVE;
			});
		}
	}
}

private void on_mgmt_load_changed(LoadEvent load_event) {
	print("mgmt load_changed %d %s\n", (int) load_event, diag_line(management, "mgmt"));
}

private void do_load_uri(string reason) {
	load_uri_count++;
	print("load_uri #%d (%s) %s\n", load_uri_count, reason, diag_line(primary, "primary"));
	if (use_workaround && load_uri_count == 1) {
		Idle.add(() => {
			print("workaround Idle: primary load_uri %s\n", start_uri);
			primary.load_uri(start_uri);
			refresh_status();
			return Source.REMOVE;
		});
		return;
	}
	primary.load_uri(start_uri);
	refresh_status();
}

private void sign_in() {
	if (signed_in) {
		return;
	}
	signed_in = true;

	print("sign-in: set_start_child(browser_stack) + load_uri (stack was orphaned)\n");
	print("  before %s\n", diag_line(primary, "primary"));

	browser_stack.set_visible_child_name("primary");
	paned.set_start_child(browser_stack);
	paned.set_end_child(session_loading);

	print("  after reparent %s\n", diag_line(primary, "primary"));
	do_load_uri("first-signed-in-often-0x0");

	/* Match consumer: leave SIGNED_IN for session-loading, then return with real size. */
	Timeout.add(100, () => {
		print("session-loading tick %s\n", diag_line(primary, "primary"));
		refresh_status();
		return Source.REMOVE;
	});

	Timeout.add(200, () => {
		print("second-signed-in: end=sidebar + load_uri again\n");
		paned.set_end_child(sidebar);
		print("  %s\n", diag_line(primary, "primary"));
		do_load_uri("second-signed-in-expect-real-size");
		refresh_status();
		return Source.REMOVE;
	});
}

private void finish_smoke() {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	refresh_status();
	var attached_ok = primary != null && primary.ready;
	var size_ok = primary != null && primary.get_width() > 32 && primary.get_height() > 32;
	var ok = attached_ok && size_ok && primary_finished;
	print("smoke %s\n", diag_line(primary, "primary"));
	print("smoke mgmt %s\n", diag_line(management, "mgmt"));
	print("smoke attached=%s size_ok=%s load_finished=%s load_uri_count=%d\n",
		attached_ok ? "yes" : "no",
		size_ok ? "yes" : "no",
		primary_finished ? "yes" : "no",
		load_uri_count);
	if (ok) {
		print("TEST_PASS\n");
		smoke_status = 0;
	} else {
		print("TEST_FAIL (blank / not attached / never finished)\n");
		smoke_status = 1;
	}
	if (window != null) {
		window.close();
	}
}

private uint16 prepare_inspector_port() {
	try {
		var probe = new Socket(SocketFamily.IPV4, SocketType.STREAM, SocketProtocol.TCP);
		probe.bind(new InetSocketAddress(new InetAddress.loopback(SocketFamily.IPV4), 0), true);
		var port = (uint16) ((InetSocketAddress) probe.get_local_address()).port;
		probe.close();
		Environment.set_variable("WEBKIT_INSPECTOR_SERVER", "127.0.0.1:%u".printf(port), true);
		print("inspector 127.0.0.1:%u (WEBKIT_INSPECTOR_SERVER)\n", port);
		return port;
	} catch (Error e) {
		warning("inspector port probe failed: %s", e.message);
		return 0;
	}
}

public static int main(string[] args) {
	start_uri = "https://example.com/";
	string[] gtk_args = {};
	gtk_args += args[0];
	for (var i = 1; i < args.length; i++) {
		if (args[i] == "--auto-signin") {
			auto_signin = true;
			continue;
		}
		if (args[i] == "--workaround") {
			use_workaround = true;
			continue;
		}
		if (args[i] == "--smoke") {
			smoke = true;
			auto_signin = true;
			continue;
		}
		if (args[i].has_prefix("-")) {
			gtk_args += args[i];
			continue;
		}
		start_uri = args[i];
	}

	var insp = prepare_inspector_port();

	var app = new Gtk.Application("com.webview2gtk.paned-insert", ApplicationFlags.FLAGS_NONE);
	app.activate.connect(() => {
		window = new Gtk.ApplicationWindow(app);
		window.set_title("webview2-gtk paned-insert");
		window.set_default_size(960, 640);

		var context = WebContext.get_default();
		context.set_automation_allowed(true);
		var ns = context.get_network_session_for_automation();

		primary = new DemoWebViewAuto(context, ns);
		primary.load_changed.connect(on_primary_load_changed);
		management = new DemoWebViewAuto(context, ns);
		management.load_changed.connect(on_mgmt_load_changed);

		context.automation_started.connect((session) => {
			session.set_application_info(new ApplicationInfo());
			session.create_web_view.connect(() => {
				return primary;
			});
			print("automation-started session=%s\n", session.id);
		});

		/* Early CDP connect attempt (consumer does this before first attach). */
		if (insp > 0) {
			Idle.add(() => {
				print("early CDP probe 127.0.0.1:%u (expect refuse until env create)\n", insp);
				return Source.REMOVE;
			});
		}

		browser_stack = new Gtk.Stack();
		browser_stack.set_hexpand(true);
		browser_stack.set_vexpand(true);
		browser_stack.add_named(wrap_webview(primary), "primary");
		browser_stack.add_named(wrap_webview(management), "management");
		browser_stack.set_visible_child_name("primary");

		login_panel = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
		login_panel.set_hexpand(true);
		login_panel.set_vexpand(true);
		login_panel.set_valign(Gtk.Align.CENTER);
		login_panel.set_halign(Gtk.Align.CENTER);
		var login_label = new Gtk.Label(
			"Login panel is paned start child.\nBrowser stack orphaned until sign-in."
		);
		login_label.set_justify(Gtk.Justification.CENTER);
		var signin_btn = new Gtk.Button.with_label("Sign in");
		signin_btn.clicked.connect(sign_in);
		login_panel.append(login_label);
		login_panel.append(signin_btn);

		session_loading = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
		session_loading.set_size_request(260, -1);
		session_loading.append(new Gtk.Label("Loading session…"));

		sidebar = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
		sidebar.set_margin_start(8);
		sidebar.set_margin_end(8);
		sidebar.set_margin_top(8);
		sidebar.set_margin_bottom(8);
		sidebar.set_size_request(260, -1);
		status = new Gtk.Label("waiting for sign-in");
		status.set_wrap(true);
		status.set_xalign(0);
		status.set_selectable(true);
		var hint = new Gtk.Label(
			"Repro: WebViewAuto + CDP env + orphaned stack → set_start_child + load_uri\n"
			+ "then session-loading churn + second load_uri at real size."
		);
		hint.set_wrap(true);
		hint.set_xalign(0);
		sidebar.append(hint);
		sidebar.append(status);

		paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
		paned.set_hexpand(true);
		paned.set_vexpand(true);
		paned.set_wide_handle(true);
		paned.set_position(640);
		paned.set_start_child(login_panel);
		paned.set_end_child(sidebar);
		paned.set_resize_end_child(false);
		paned.set_shrink_end_child(false);

		window.set_child(paned);
		window.present();

		print("startup: login_panel in paned; browser_stack orphaned (WebViewAuto x2)\n");
		print("  %s\n", diag_line(primary, "primary"));
		print("  %s\n", diag_line(management, "mgmt"));
		refresh_status();

		Timeout.add(400, () => {
			refresh_status();
			return Source.CONTINUE;
		});

		if (auto_signin) {
			Timeout.add(800, () => {
				sign_in();
				return Source.REMOVE;
			});
		}

		if (smoke) {
			Timeout.add(12000, () => {
				finish_smoke();
				return Source.REMOVE;
			});
		}
	});
	app.run(gtk_args);
	return smoke ? smoke_status : 0;
}

class DemoWebViewAuto : WebView {
	public DemoWebViewAuto(WebContext context, NetworkSession session) {
		Object(
			orientation: Gtk.Orientation.VERTICAL,
			spacing: 0,
			hexpand: true,
			vexpand: true,
			web_context: context,
			is_controlled_by_automation: true,
			network_session: session,
			website_policies: (WebsitePolicies) Object.new(
				typeof(WebsitePolicies),
				"autoplay", AutoplayPolicy.DENY
			)
		);
		this.get_settings().enable_developer_extras = true;
		this.get_settings().enable_media_stream = false;
		this.get_settings().enable_webrtc = false;
		this.get_settings().media_playback_requires_user_gesture = true;
		this.get_settings().user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
			+ "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36";
		this.is_muted = true;
		this.permission_request.connect((request) => {
			request.deny();
			return true;
		});
		this.query_permission_state.connect((query) => {
			query.finish(PermissionState.DENIED);
			return true;
		});
	}
}
