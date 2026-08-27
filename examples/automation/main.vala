/* Automation setup smoke — WebKitGTK-shaped APIs on WebView2Gtk (plan 3.0 / 3.2).
 *
 * Setup only: no WebDriver, no click/type.
 *
 *   --inspector-port <n>   (default 19222; also WV2GTK_INSPECTOR_PORT)
 *   --smoke               two WebViews + Win32Atspi walk; holds ~2.5s then quits
 */

using Gtk;
using WebView2Gtk;
using Win32Atspi;

public static int main(string[] args) {
	var insp = (uint16) 19222;
	var smoke = false;
	var smoke_status = 1;
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
		gtk_args += args[i];
	}

	Environment.set_variable("WEBKIT_INSPECTOR_SERVER", "127.0.0.1:%u".printf(insp), true);

	var app = new Gtk.Application("com.webview2gtk.automation", ApplicationFlags.DEFAULT_FLAGS);
	app.activate.connect(() => {
		var window = new Gtk.ApplicationWindow(app);
		window.set_title("webview2-gtk automation");
		window.set_default_size(900, 700);

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
	return smoke ? smoke_status : code;
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
