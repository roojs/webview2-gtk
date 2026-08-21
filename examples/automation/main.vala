/* Automation setup smoke — WebKitGTK-shaped APIs on WebView2Gtk (plan 3.0 / 3.2).
 *
 * Setup only: no WebDriver, no click/type.
 *
 *   --inspector-port <n>   (default 19222; also WV2GTK_INSPECTOR_PORT)
 *   --smoke               quit shortly after start (remote CI)
 */

using Gtk;
using WebView2Gtk;

public static int main(string[] args) {
	var insp = (uint16) 19222;
	var smoke = false;
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

	Environment.set_variable(
		"WEBKIT_INSPECTOR_SERVER",
		"127.0.0.1:%u".printf(insp),
		true
	);

	var app = new Gtk.Application(
		"com.webview2gtk.automation",
		ApplicationFlags.DEFAULT_FLAGS
	);
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

		window.set_child(view);
		view.load_html(
			"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>automation fill smoke</title>
<style>
body{font-family:sans-serif;margin:2rem}
#q{font-size:1.25rem;width:20rem;padding:0.4rem}
</style></head><body>
<h1>Fill smoke</h1>
<input id="q" type="text" autocomplete="off">
</body></html>""",
			null
		);

		GLib.message(
			"inspector 127.0.0.1:%u — CDP --remote-debugging-port(WEBKIT_INSPECTOR_SERVER)",
			insp
		);
		window.present();
		if (smoke) {
			/*
			 * Quit after automation_started. Close the window first so WebView2
			 * tears down before process exit — avoids the common Chromium
			 * "Failed to unregister class Chrome_WidgetWin_0" scare on abrupt quit.
			 */
			Timeout.add(2500, () => {
				window.close();
				Idle.add(() => {
					app.quit();
					return false;
				});
				return false;
			});
		}
	});

	return app.run(gtk_args);
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
	}
}
