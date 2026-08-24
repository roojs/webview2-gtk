/* Repro: management WebView claims the single COM host first; primary stays blank.
 *
 * Library limit: one WebView2 host per process. If a second WebView widget is
 * already attached (management), primary set_start_child + load_uri in the same
 * turn can leave the splash pane blank with no load_changed.
 *
 *   webview2gtk-paned-insert.exe [url]
 *   --auto-signin
 *   --workaround   Idle after show before primary load_uri
 *   --smoke        exit 1 unless primary FINISHED
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

private WebView? primary = null;
private WebView? management = null;
private Gtk.Label status;
private Gtk.Stack stack;
private Gtk.Stack browser_stack;
private Gtk.Paned paned;
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
	return "%s ready=%s mapped=%s size=%dx%d uri=%s title=%s".printf(
		name,
		view.ready ? "yes" : "no",
		view.get_mapped() ? "yes" : "no",
		view.get_width(),
		view.get_height(),
		view.get_uri(),
		view.get_title()
	);
}

private void refresh_status() {
	status.label = "%s\n%s\nprimary_finished=%s".printf(
		diag_line(primary, "primary"),
		diag_line(management, "mgmt"),
		primary_finished ? "yes" : "no"
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

private void sign_in() {
	if (signed_in) {
		return;
	}
	signed_in = true;

	print("sign-in: show primary + load_uri (mgmt already holds COM host)\n");
	print("  before primary %s\n", diag_line(primary, "primary"));
	print("  before mgmt    %s\n", diag_line(management, "mgmt"));

	browser_stack.set_visible_child_name("primary");
	stack.set_visible_child_name("app");

	if (use_workaround) {
		Idle.add(() => {
			print("workaround Idle: primary load_uri %s\n", start_uri);
			primary.load_uri(start_uri);
			refresh_status();
			return Source.REMOVE;
		});
	} else {
		primary.load_uri(start_uri);
	}
	print("  after primary %s\n", diag_line(primary, "primary"));
	refresh_status();
}

private void show_management() {
	browser_stack.set_visible_child_name("management");
	Idle.add(() => {
		print("management Idle load_uri https://example.org/\n");
		management.load_uri("https://example.org/");
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
	print("smoke attached=%s size_ok=%s load_finished=%s\n",
		attached_ok ? "yes" : "no",
		size_ok ? "yes" : "no",
		primary_finished ? "yes" : "no");
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

	var app = new Gtk.Application("com.webview2gtk.paned-insert", ApplicationFlags.FLAGS_NONE);
	app.activate.connect(() => {
		window = new Gtk.ApplicationWindow(app);
		window.set_title("webview2-gtk paned-insert");
		window.set_default_size(960, 640);

		primary = new WebView();
		primary.load_changed.connect(on_primary_load_changed);
		management = new WebView();
		management.load_changed.connect(on_mgmt_load_changed);

		stack = new Gtk.Stack();

		var login = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
		login.set_valign(Gtk.Align.CENTER);
		login.set_halign(Gtk.Align.CENTER);
		var login_label = new Gtk.Label(
			"Sign in.\nManagement WebView is already mapped (claims COM host)."
		);
		login_label.set_justify(Gtk.Justification.CENTER);
		var signin_btn = new Gtk.Button.with_label("Sign in");
		signin_btn.clicked.connect(sign_in);
		login.append(login_label);
		login.append(signin_btn);

		paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
		paned.set_hexpand(true);
		paned.set_vexpand(true);
		paned.set_wide_handle(true);
		paned.set_position(640);

		browser_stack = new Gtk.Stack();
		browser_stack.set_hexpand(true);
		browser_stack.set_vexpand(true);
		browser_stack.add_named(wrap_webview(primary), "primary");
		browser_stack.add_named(wrap_webview(management), "management");
		/* Management visible first so it can attach before sign-in. */
		browser_stack.set_visible_child_name("management");
		paned.set_start_child(browser_stack);

		var side = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
		side.set_margin_start(8);
		side.set_margin_end(8);
		side.set_margin_top(8);
		side.set_margin_bottom(8);
		side.set_size_request(260, -1);

		status = new Gtk.Label("waiting for sign-in");
		status.set_wrap(true);
		status.set_xalign(0);
		status.set_selectable(true);

		var hint = new Gtk.Label(
			"Want primary blank after sign-in (mgmt already attached).\n"
			+ "“Show management” Idle path often still works."
		);
		hint.set_wrap(true);
		hint.set_xalign(0);

		var mgmt_btn = new Gtk.Button.with_label("Show management (Idle load)");
		mgmt_btn.clicked.connect(show_management);

		side.append(hint);
		side.append(status);
		side.append(mgmt_btn);
		paned.set_end_child(side);
		paned.set_resize_end_child(false);
		paned.set_shrink_end_child(false);

		/* App page is built but login is shown — paned still maps under Stack? */
		stack.add_named(login, "login");
		stack.add_named(paned, "app");
		stack.set_visible_child_name("app");
		/* Force management on-screen briefly so COM attach happens, then login. */
		Timeout.add(600, () => {
			print("pre-login mgmt attach probe %s\n", diag_line(management, "mgmt"));
			management.load_uri("about:blank");
			stack.set_visible_child_name("login");
			refresh_status();
			if (auto_signin) {
				Timeout.add(400, () => {
					sign_in();
					return Source.REMOVE;
				});
			}
			return Source.REMOVE;
		});

		window.set_child(stack);
		window.present();

		print("startup: show app/management first so COM attaches, then login\n");
		refresh_status();

		Timeout.add(400, () => {
			refresh_status();
			return Source.CONTINUE;
		});

		if (smoke) {
			Timeout.add(10000, () => {
				finish_smoke();
				return Source.REMOVE;
			});
		}
	});
	app.run(gtk_args);
	return smoke ? smoke_status : 0;
}
