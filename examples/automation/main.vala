/* Automation setup smoke — WebKitGTK-shaped APIs on WebView2Gtk (plan 3.0 / 3.2).
 *
 * Port of Snappr tests/automation-browser (setup only: no WebDriver, no click/type).
 *
 *   WEBKIT_INSPECTOR_SERVER=127.0.0.1:<port>  (default 19222)
 *   --inspector-port <n>
 *   --smoke   quit shortly after automation_started (remote CI)
 */

using Gtk;
using WebView2Gtk;

class AutomationWindow : Gtk.ApplicationWindow {
	public WebView view { get; private set; }

	public AutomationWindow (Gtk.Application app) {
		Object (
			application: app,
			title: "webview2-gtk automation",
			default_width: 900,
			default_height: 700
		);

		var context = WebContext.get_default ();
		context.set_automation_allowed (true);

		this.view = (WebView) Object.new (
			typeof (WebView),
			"web-context", context,
			"is-controlled-by-automation", true,
			"network-session", context.get_network_session_for_automation (),
			"hexpand", true,
			"vexpand", true
		);

		context.automation_started.connect ((session) => {
			var info = new ApplicationInfo ();
			info.set_name ("WebView2GtkAutomationBrowser");
			info.set_version (0, 1, 0);
			session.set_application_info (info);
			session.create_web_view.connect (() => {
				return this.view;
			});
			/* stderr — survives --smoke quit (stdout may not flush). */
			GLib.message ("automation-started session=%s", session.id);
		});

		this.set_child (this.view);
		this.view.load_html (
			"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>automation fill smoke</title>
<style>
body{font-family:sans-serif;margin:2rem}
#q{font-size:1.25rem;width:20rem;padding:0.4rem}
#out{margin-top:1rem;min-height:1.5rem}
</style></head><body>
<h1>Fill smoke</h1>
<p>Setup-only smoke — click/sendKeys stay with an external driver later.</p>
<input id="q" type="text" autocomplete="off">
<pre id="out"></pre>
<script>
const q=document.getElementById("q");
const out=document.getElementById("out");
q.addEventListener("input",()=>{out.textContent=q.value;});
</script>
</body></html>""",
			null
		);
	}
}

public static int main (string[] args) {
	var insp = (uint16) 19222;
	var smoke = false;
	var env_port = Environment.get_variable ("SNAPPR_INSPECTOR_PORT");
	if (env_port != null && env_port != "") {
		insp = (uint16) int.parse (env_port);
	}

	string[] gtk_args = {};
	gtk_args += args[0];
	for (var i = 1; i < args.length; i++) {
		if (args[i] == "--inspector-port" && i + 1 < args.length) {
			insp = (uint16) int.parse (args[++i]);
			continue;
		}
		if (args[i] == "--smoke") {
			smoke = true;
			continue;
		}
		gtk_args += args[i];
	}

	Environment.set_variable (
		"WEBKIT_INSPECTOR_SERVER",
		"127.0.0.1:%u".printf (insp),
		true
	);

	var app = new Gtk.Application (
		"com.webview2gtk.automation",
		ApplicationFlags.DEFAULT_FLAGS
	);
	app.activate.connect (() => {
		var window = new AutomationWindow (app);
		print (
			"inspector 127.0.0.1:%u — CDP --remote-debugging-port (WEBKIT_INSPECTOR_SERVER)\n",
			insp
		);
		stdout.flush ();
		window.present ();
		if (smoke) {
			Timeout.add (2500, () => {
				app.quit ();
				return false;
			});
		}
	});

	return app.run (gtk_args);
}
