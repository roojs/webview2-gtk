/* Consumer-shaped Gtk.Stack + Win32Atspi document pick repro.
 * See ../2026-08-28-win32atspi-hidden-stack-host-missing-document.md
 *
 * Build against an installed webview2gtk-1 (pkg-config) on Windows/MSYS2.
 * Flags:
 *   --google           load https://www.google.com/?hl=en on hidden primary
 *   --restore-primary  map primary before pick (visibility workaround)
 */
using Gtk;
using WebView2Gtk;
using Win32Atspi;

const string PRIMARY_TITLE = "stack primary document";
const string SECONDARY_TITLE = "stack secondary document";
const string GOOGLE_HOME = "https://www.google.com/?hl=en";

private int exit_status = 0;
private bool use_google = false;
/** Map primary before pick — visibility workaround. */
private bool restore_primary = false;

private Gtk.Stack browser_stack;
private WebView primary;
private WebView secondary;
private Gtk.ApplicationWindow? diag_window;
private Gtk.Application? diag_app;

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
	view.set_hexpand(true);
	view.set_vexpand(true);
	scrolled.set_child(view);
	overlay.set_child(scrolled);
	browser.append(overlay);
	return browser;
}

private void print_state(string label) {
	var p_uri = primary.get_uri() != null ? primary.get_uri() : "";
	var s_uri = secondary.get_uri() != null ? secondary.get_uri() : "";
	var p_title = primary.get_title() != null ? primary.get_title() : "";
	var s_title = secondary.get_title() != null ? secondary.get_title() : "";
	print("%s stack=%s primary_mapped=%s secondary_mapped=%s primary_ready=%s secondary_ready=%s\n",
		label,
		browser_stack.get_visible_child_name(),
		primary.get_mapped() ? "yes" : "no",
		secondary.get_mapped() ? "yes" : "no",
		primary.ready ? "yes" : "no",
		secondary.ready ? "yes" : "no");
	print("  webview primary   uri=%s title=%s\n", p_uri, p_title);
	print("  webview secondary uri=%s title=%s\n", s_uri, s_title);
}

/** Title then URI pick over Win32Atspi document frames. */
private bool debug_pick(string want_url, string want_title) {
	print("pick want title=%s url=%s\n", want_title, want_url);
	Win32Atspi.init();
	var desktop = Win32Atspi.get_desktop(0);
	Win32Atspi.Accessible? app = null;
	for (var i = 0; i < desktop.get_child_count(); i++) {
		var candidate = desktop.get_child_at_index(i);
		if (candidate.get_process_id() != (uint) Posix.getpid()) {
			continue;
		}
		app = candidate;
		break;
	}
	if (app == null) {
		print("  PICK FAIL no application node\n");
		return false;
	}
	Win32Atspi.Accessible? by_title = null;
	Win32Atspi.Accessible? by_url = null;
	var find_acc = new Gee.ArrayList<Win32Atspi.Accessible>();
	find_acc.add(app);
	while (find_acc.size > 0) {
		var cur = find_acc.remove_at(find_acc.size - 1);
		var role_name = cur.get_role_name();
		if (role_name == "document text" || role_name == "document frame") {
			var doc_name = cur.get_name() != null ? cur.get_name() : "";
			var doc_uri = "";
			var hl = cur.get_hyperlink();
			if (hl != null && hl.get_n_anchors() > 0) {
				doc_uri = hl.get_uri(0);
			}
			var title_hit = want_title != "" && doc_name != ""
				&& (doc_name == want_title || doc_name.contains(want_title)
					|| want_title.contains(doc_name));
			var url_hit = want_url != "" && doc_uri != ""
				&& (doc_uri == want_url || doc_uri.has_prefix(want_url)
					|| want_url.has_prefix(doc_uri));
			print("  a11y_doc name=%s uri=%s title_hit=%s url_hit=%s\n",
				doc_name, doc_uri, title_hit ? "yes" : "no", url_hit ? "yes" : "no");
			if (title_hit && by_title == null) {
				by_title = cur;
			}
			if (url_hit && by_url == null) {
				by_url = cur;
			}
			if (by_title != null) {
				break;
			}
			continue;
		}
		for (var j = 0; j < cur.get_child_count(); j++) {
			find_acc.add(cur.get_child_at_index(j));
		}
	}
	if (by_title != null) {
		print("  PICK OK by title name=%s\n", by_title.get_name());
		return true;
	}
	if (by_url != null) {
		print("  PICK OK by url name=%s\n", by_url.get_name());
		return true;
	}
	print("  PICK FAIL AT-SPI: no document matching title=%s url=%s\n", want_title, want_url);
	return false;
}

private void window_close_and_quit() {
	if (diag_window != null) {
		diag_window.close();
	}
	if (diag_app != null) {
		diag_app.quit();
	}
}

private void run_diagnostic(Gtk.ApplicationWindow window, Gtk.Application app) {
	var phase = restore_primary
		? "--- after restore_primary (primary visible) ---"
		: "--- after loads (secondary visible, primary hidden) ---";
	print_state(phase);
	var want_url = primary.get_uri() != null ? primary.get_uri() : "";
	var want_title = primary.get_title() != null ? primary.get_title() : "";
	var pick_ok = debug_pick(want_url, want_title);
	if (restore_primary) {
		if (pick_ok) {
			print("VERDICT=WORKAROUND_OK hidden primary missing from tree; visible primary picks OK\n");
		} else {
			print("VERDICT=LIBRARY_BUG primary visible/mapped but document still missing from tree\n");
		}
	} else {
		if (pick_ok) {
			print("VERDICT=HIDDEN_OK hidden primary picked OK\n");
		} else {
			print("VERDICT=HIDDEN_MISS hidden primary not in tree (library or timing)\n");
		}
	}
	print("DIAG_DONE\n");
	window.close();
	app.quit();
}

private void fail_not_ready(string stage, int tries) {
	print("DIAG_FAIL stage=%s tries=%d primary_ready=%s secondary_ready=%s primary_mapped=%s secondary_mapped=%s\n",
		stage, tries,
		primary.ready ? "yes" : "no",
		secondary.ready ? "yes" : "no",
		primary.get_mapped() ? "yes" : "no",
		secondary.get_mapped() ? "yes" : "no");
	exit_status = 1;
	window_close_and_quit();
}

/**
 * Primary mapped briefly, then secondary shown; primary loads while unmapped
 * (stack + park path).
 */
private void prepare_stack(Gtk.ApplicationWindow window, Gtk.Application app, string secondary_html) {
	diag_window = window;
	diag_app = app;
	var tries = 0;
	Timeout.add(250, () => {
		tries++;
		if (!primary.ready || !primary.get_mapped()) {
			if (tries < 120) {
				return Source.CONTINUE;
			}
			fail_not_ready("primary_attach", tries);
			return Source.REMOVE;
		}
		browser_stack.set_visible_child_name("secondary");
		secondary.load_html(secondary_html, null);
		if (use_google) {
			primary.load_uri(GOOGLE_HOME);
		} else {
			var primary_html = """<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>""" + PRIMARY_TITLE + """</title>
</head><body><p>Primary hidden</p></body></html>""";
			primary.load_html(primary_html, null);
		}
		tries = 0;
		Timeout.add(250, () => {
			tries++;
			if (!secondary.ready) {
				if (tries < 120) {
					return Source.CONTINUE;
				}
				fail_not_ready("secondary_load", tries);
				return Source.REMOVE;
			}
			tries = 0;
			Timeout.add(500, () => {
				tries++;
				var p_uri = primary.get_uri() != null ? primary.get_uri() : "";
				var p_title = primary.get_title() != null ? primary.get_title() : "";
				var settled = true;
				if (use_google) {
					settled = p_uri.has_prefix("https://www.google.com")
						&& p_title != "" && p_title != "about:blank";
				}
				if (!settled && tries < 40) {
					return Source.CONTINUE;
				}
				if (!restore_primary) {
					run_diagnostic(window, app);
					return Source.REMOVE;
				}
				browser_stack.set_visible_child_name("primary");
				tries = 0;
				Timeout.add(250, () => {
					tries++;
					if (!primary.get_mapped() && tries < 40) {
						return Source.CONTINUE;
					}
					run_diagnostic(window, app);
					return Source.REMOVE;
				});
				return Source.REMOVE;
			});
			return Source.REMOVE;
		});
		return Source.REMOVE;
	});
}

public static int main(string[] args) {
	var gtk_args = new string[] { args[0] };
	for (var i = 1; i < args.length; i++) {
		if (args[i] == "--google") {
			use_google = true;
			continue;
		}
		if (args[i] == "--restore-primary") {
			restore_primary = true;
			continue;
		}
		gtk_args += args[i];
	}
	var secondary_html = """<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>""" + SECONDARY_TITLE + """</title>
</head><body><p>Secondary / visible WebView</p></body></html>""";

	print("smoke-hidden-stack spider=%s restore_primary=%s\n",
		use_google ? "google" : "html",
		restore_primary ? "yes" : "no");

	var app = new Gtk.Application("com.webview2gtk.smoke-hidden-stack", ApplicationFlags.FLAGS_NONE);
	app.activate.connect(() => {
		var window = new Gtk.ApplicationWindow(app);
		window.set_title("smoke-hidden-stack");
		window.set_default_size(900, 700);

		var context = WebContext.get_default();
		primary = new PlainWebView(context);
		secondary = new PlainWebView(context);

		browser_stack = new Gtk.Stack();
		browser_stack.set_hexpand(true);
		browser_stack.set_vexpand(true);
		browser_stack.add_named(wrap_webview(primary), "primary");
		browser_stack.add_named(wrap_webview(secondary), "secondary");
		browser_stack.set_visible_child_name("primary");

		window.set_child(browser_stack);
		window.present();

		prepare_stack(window, app, secondary_html);
	});
	app.run(gtk_args);
	return exit_status;
}

class PlainWebView : WebView {
	public PlainWebView(WebContext context) {
		Object(
			orientation: Gtk.Orientation.VERTICAL,
			spacing: 0,
			hexpand: true,
			vexpand: true,
			web_context: context
		);
		this.get_settings().enable_developer_extras = true;
	}
}
