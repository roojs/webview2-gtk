/* Automation setup smoke — WebKitGTK-shaped APIs on WebView2Gtk (plan 3.0 / 3.2).
 *
 * Setup only: no WebDriver, no click/type.
 *
 *   --inspector-port <n>   (default 19222; also WV2GTK_INSPECTOR_PORT)
 *   --smoke               two WebViews side-by-side + Win32Atspi walk; holds ~2.5s then quits
 *   --smoke-stack         Gtk.Stack (one unmapped) + two-phase Win32Atspi walk
 */

using Gtk;
using WebView2Gtk;
using Win32Atspi;

const string STACK_PRIMARY_TITLE = "stack primary document";
const string STACK_SECONDARY_TITLE = "stack secondary document";

private int smoke_status = 1;
private bool smoke = false;
private bool smoke_stack = false;

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

private bool doc_name_hit(string doc_name, string want) {
	if (doc_name == "" || want == "") {
		return false;
	}
	return doc_name == want || doc_name.contains(want) || want.contains(doc_name);
}

private void walk_print_docs(out int n, out bool primary_hit, out bool secondary_hit) {
	n = 0;
	primary_hit = false;
	secondary_hit = false;
	Win32Atspi.init();
	var desktop = Win32Atspi.get_desktop(0);
	for (var i = 0; i < desktop.get_child_count(); i++) {
		var app_acc = desktop.get_child_at_index(i);
		for (var j = 0; j < app_acc.get_child_count(); j++) {
			var frame = app_acc.get_child_at_index(j);
			for (var k = 0; k < frame.get_child_count(); k++) {
				var doc = frame.get_child_at_index(k);
				var role = doc.get_role_name();
				if (role != "document frame" && role != "document text") {
					continue;
				}
				n++;
				var doc_name = doc.get_name() != null ? doc.get_name() : "";
				var doc_uri = "";
				var hl = doc.get_hyperlink();
				if (hl != null && hl.get_n_anchors() > 0) {
					doc_uri = hl.get_uri(0);
				}
				var title_hit = doc_name_hit(doc_name, STACK_PRIMARY_TITLE);
				print("a11y_doc name=%s uri=%s title_hit=%s\n",
					doc_name, doc_uri, title_hit ? "yes" : "no");
				if (title_hit) {
					primary_hit = true;
				}
				if (doc_name_hit(doc_name, STACK_SECONDARY_TITLE)) {
					secondary_hit = true;
				}
			}
		}
	}
	print("a11y_documents=%d\n", n);
}

private void print_webview_state(string label, WebView primary, WebView secondary) {
	var p_uri = primary.get_uri() != null ? primary.get_uri() : "";
	var s_uri = secondary.get_uri() != null ? secondary.get_uri() : "";
	var p_title = primary.get_title() != null ? primary.get_title() : "";
	var s_title = secondary.get_title() != null ? secondary.get_title() : "";
	print("%s primary_mapped=%s secondary_mapped=%s\n",
		label,
		primary.get_mapped() ? "yes" : "no",
		secondary.get_mapped() ? "yes" : "no");
	print("webview primary uri=%s title=%s\n", p_uri, p_title);
	print("webview secondary uri=%s title=%s\n", s_uri, s_title);
}

private void pick_primary(string want_url, string want_title) {
	print("PICK primary title=%s url=%s\n", want_title, want_url);
	Win32Atspi.init();
	var desktop = Win32Atspi.get_desktop(0);
	for (var i = 0; i < desktop.get_child_count(); i++) {
		var app_acc = desktop.get_child_at_index(i);
		for (var j = 0; j < app_acc.get_child_count(); j++) {
			var frame = app_acc.get_child_at_index(j);
			for (var k = 0; k < frame.get_child_count(); k++) {
				var doc = frame.get_child_at_index(k);
				var role = doc.get_role_name();
				if (role != "document frame" && role != "document text") {
					continue;
				}
				var doc_name = doc.get_name() != null ? doc.get_name() : "";
				if (doc_name_hit(doc_name, want_title)) {
					print("PICK primary → OK\n");
					return;
				}
			}
		}
	}
	print("PICK primary title=%s → FAIL (not in tree)\n", want_title);
}

private void finish_quit(Gtk.ApplicationWindow window, Gtk.Application app) {
	Timeout.add(400, () => {
		window.close();
		Idle.add(() => {
			app.quit();
			return false;
		});
		return Source.REMOVE;
	});
}

private void run_smoke_stack(Gtk.ApplicationWindow window, Gtk.Application app) {
	var context = WebContext.get_default();
	context.set_automation_allowed(true);
	var ns = context.get_network_session_for_automation();
	if (ns == null) {
		error("get_network_session_for_automation returned null");
	}

	var primary = new WebViewAuto(context, ns);
	var secondary = new WebViewAuto(context, ns);
	var stack = new Gtk.Stack();
	stack.set_hexpand(true);
	stack.set_vexpand(true);
	stack.add_named(wrap_webview(primary), "primary");
	stack.add_named(wrap_webview(secondary), "secondary");
	stack.set_visible_child_name("primary");
	window.set_child(stack);
	window.present();

	var tries = 0;
	Timeout.add(250, () => {
		tries++;
		if (!primary.ready || !primary.get_mapped()) {
			if (tries < 120) {
				return Source.CONTINUE;
			}
			print("STACK_SMOKE_FAIL primary_attach tries=%d\n", tries);
			smoke_status = 1;
			finish_quit(window, app);
			return Source.REMOVE;
		}
		stack.set_visible_child_name("secondary");
		tries = 0;
		Timeout.add(250, () => {
			tries++;
			if (!secondary.ready || !secondary.get_mapped()) {
				if (tries < 120) {
					return Source.CONTINUE;
				}
				print("STACK_SMOKE_FAIL secondary_attach tries=%d\n", tries);
				smoke_status = 1;
				finish_quit(window, app);
				return Source.REMOVE;
			}
			secondary.load_html(
				"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>""" + STACK_SECONDARY_TITLE + """</title>
</head><body><p>Secondary WebView</p></body></html>""",
				null
			);
			primary.load_html(
				"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>""" + STACK_PRIMARY_TITLE + """</title>
</head><body><p>Primary WebView hidden</p></body></html>""",
				null
			);
			tries = 0;
			Timeout.add(250, () => {
				tries++;
				var p_title = primary.get_title() != null ? primary.get_title() : "";
				var s_title = secondary.get_title() != null ? secondary.get_title() : "";
				var titles_ok = doc_name_hit(p_title, STACK_PRIMARY_TITLE)
					&& doc_name_hit(s_title, STACK_SECONDARY_TITLE);
				if ((!primary.ready || !secondary.ready || !titles_ok) && tries < 120) {
					return Source.CONTINUE;
				}
				if (!titles_ok) {
					print("STACK_SMOKE_FAIL titles_not_ready primary=%s secondary=%s\n",
						p_title, s_title);
					smoke_status = 1;
					finish_quit(window, app);
					return Source.REMOVE;
				}
				Timeout.add(500, () => {
					print_webview_state("--- Phase A (hidden primary) ---", primary, secondary);
					int n_a;
					bool primary_a;
					bool secondary_a;
					walk_print_docs(out n_a, out primary_a, out secondary_a);
					var want_url = primary.get_uri() != null ? primary.get_uri() : "";
					var want_title = primary.get_title() != null ? primary.get_title() : "";
					pick_primary(want_url, want_title);
					var phase_a_ok = primary_a && secondary_a && n_a >= 2;
					if (!phase_a_ok) {
						print("STACK_SMOKE_FAIL hidden_missing_primary\n");
					}

					stack.set_visible_child_name("primary");
					tries = 0;
					Timeout.add(250, () => {
						tries++;
						if (!primary.get_mapped() && tries < 40) {
							return Source.CONTINUE;
						}
						Timeout.add(500, () => {
							print_webview_state("--- Phase B (visible primary) ---", primary, secondary);
							int n_b;
							bool primary_b;
							bool secondary_b;
							walk_print_docs(out n_b, out primary_b, out secondary_b);
							if (primary_b) {
								print("STACK_SMOKE_NOTE visible_primary_workaround_ok\n");
							}
							var phase_b_ok = primary_b;
							var ok = phase_a_ok && phase_b_ok;
							if (ok) {
								print("STACK_SMOKE_PASS\n");
								smoke_status = 0;
							} else if (phase_a_ok && !phase_b_ok) {
								print("STACK_SMOKE_FAIL visible_primary_missing\n");
								smoke_status = 1;
							} else {
								smoke_status = 1;
							}
							finish_quit(window, app);
							return Source.REMOVE;
						});
						return Source.REMOVE;
					});
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
	var insp = (uint16) 19222;
	var env_port = Environment.get_variable("WV2GTK_INSPECTOR_PORT");
	if (env_port != null && env_port != "") {
		insp = (uint16) int.parse(env_port);
	}

	string[] gtk_args = {};
	gtk_args += args[0];
	for (var i = 1; i < args.length; i++) {
		if (args[i] == "--inspector-port" && i + 1 < args.length) {
			insp = (uint16) int.parse(args[++i]);
			continue;
		}
		if (args[i] == "--smoke") {
			smoke = true;
			continue;
		}
		if (args[i] == "--smoke-stack") {
			smoke_stack = true;
			continue;
		}
		gtk_args += args[i];
	}

	Environment.set_variable("WEBKIT_INSPECTOR_SERVER", "127.0.0.1:%u".printf(insp), true);

	var app = new Gtk.Application("com.webview2gtk.automation", ApplicationFlags.DEFAULT_FLAGS);
	app.activate.connect(() => {
		var window = new Gtk.ApplicationWindow(app);
		window.set_title("webview2-gtk automation");
		window.set_default_size(900, 700);

		if (smoke_stack) {
			run_smoke_stack(window, app);
			return;
		}

		var context = WebContext.get_default();
		context.set_automation_allowed(true);

		var ns = context.get_network_session_for_automation();
		if (ns == null) {
			error("get_network_session_for_automation returned null");
		}

		WebView view = new WebViewAuto(context, ns);
		WebView? view2 = null;

		context.automation_started.connect((session) => {
			var info = new ApplicationInfo();
			info.set_name("WebView2GtkAutomationBrowser");
			info.set_version(0, 1, 0);
			session.set_application_info(info);
			session.create_web_view.connect(() => {
				return view;
			});
			GLib.message("automation-started session=%s", session.id);
		});

		if (smoke) {
			var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			box.set_hexpand(true);
			box.set_vexpand(true);
			view.set_hexpand(true);
			view.set_vexpand(true);
			box.append(view);
			view2 = new WebViewAuto(context, ns);
			view2.set_hexpand(true);
			view2.set_vexpand(true);
			box.append(view2);
			window.set_child(box);
		} else {
			window.set_child(view);
		}

		if (smoke) {
			view.load_html(
				"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>first document</title>
</head><body><p>First WebView</p></body></html>""",
				null
			);
			view2.load_html(
				"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>second document</title>
</head><body><p>Second WebView</p></body></html>""",
				null
			);
		} else {
			view.load_html(
				"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>automation fill smoke</title>
<style>
body{font-family:sans-serif;margin:2rem}
#q{font-size:1.25rem;width:20rem;padding:0.4rem}
</style></head><body>
<h1>Fill smoke</h1>
<input id="q" type="text" autocomplete="off">
<p>Leave this running, then run <code>webview2gtk-cdp-attach.exe</code> to fill the box.</p>
</body></html>""",
				null
			);
		}

		GLib.message("inspector 127.0.0.1:%u — CDP --remote-debugging-port(WEBKIT_INSPECTOR_SERVER)",
			insp);
		window.present();
		if (smoke) {
			SourceFunc finish = () => {
				Timeout.add(2500, () => {
					window.close();
					Idle.add(() => {
						app.quit();
						return false;
					});
					return Source.REMOVE;
				});
				return false;
			};
			var tries = 0;
			Timeout.add(250, () => {
				tries++;
				if (view2 == null || !view.ready || !view2.ready) {
					if (tries < 32) {
						return Source.CONTINUE;
					}
					print("TEST_FAIL (views not ready tries=%d)\n", tries);
					smoke_status = 1;
					finish();
					return Source.REMOVE;
				}

				Win32Atspi.init();
				var desktop = Win32Atspi.get_desktop(0);
				var n = 0;
				var win_ok = true;
				Win32Atspi.Accessible? first_doc = null;
				for (var i = 0; i < desktop.get_child_count(); i++) {
					var app_acc = desktop.get_child_at_index(i);
					for (var j = 0; j < app_acc.get_child_count(); j++) {
						var frame = app_acc.get_child_at_index(j);
						for (var k = 0; k < frame.get_child_count(); k++) {
							var doc = frame.get_child_at_index(k);
							var role = doc.get_role_name();
							if (role != "document frame" && role != "document text") {
								continue;
							}
							n++;
							print("a11y_doc[%d] name=%s\n", n, doc.get_name());
							if (first_doc == null) {
								first_doc = doc;
							}
						}
					}
				}
				print("a11y_documents=%d\n", n);
				if (first_doc != null) {
					var ds = first_doc.get_extents(CoordType.SCREEN);
					var dw = first_doc.get_extents(CoordType.WINDOW);
					print("a11y_window_origin=%d,%d screen=%d,%d\n", dw.x, dw.y, ds.x, ds.y);
					win_ok = dw.x == 0 && dw.y == 0;
					if (first_doc.get_child_count() > 0) {
						var ch = first_doc.get_child_at_index(0);
						var cs = ch.get_extents(CoordType.SCREEN);
						var cw = ch.get_extents(CoordType.WINDOW);
						print("a11y_child window=%d,%d screen=%d,%d\n", cw.x, cw.y, cs.x, cs.y);
						win_ok = win_ok && cw.x == cs.x - ds.x && cw.y == cs.y - ds.y;
					}
				} else {
					win_ok = false;
				}
				var ok = n >= 2 && win_ok;
				print(ok ? "TEST_PASS\n" : "TEST_FAIL\n");
				smoke_status = ok ? 0 : 1;
				finish();
				return Source.REMOVE;
			});
		}
	});

	var code = app.run(gtk_args);
	return (smoke || smoke_stack) ? smoke_status : code;
}

class WebViewAuto : WebView
{
	public WebViewAuto(WebContext context, NetworkSession session)
	{
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
