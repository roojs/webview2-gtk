/* Minimal hello — script message round-trip (WebKitGTK-shaped).
 *
 *   webview2gtk-hello.exe
 *   webview2gtk-hello.exe --smoke-policy-ignore
 */

using Gtk;
using WebView2Gtk;

private const string PDF_URI =
	"https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf";

private bool smoke_policy_ignore = false;
private int smoke_status = 1;
private bool smoke_done = false;
private bool html_finished = false;
private Gtk.ApplicationWindow? window = null;
private WebView? web = null;

private static string mime_from(Soup.MessageHeaders headers) {
	var raw = headers.get_one("Content-Type");
	if (raw == null || raw.length == 0) {
		return "";
	}
	var semi = raw.index_of_char(';');
	string type;
	if (semi < 0) {
		type = raw;
	} else {
		type = raw.substring(0, semi);
	}
	return type.strip().down();
}

private void finish_smoke(bool ok, string why) {
	if (smoke_done) {
		return;
	}
	smoke_done = true;
	if (ok) {
		print("TEST_PASS\n");
		smoke_status = 0;
	} else {
		print("TEST_FAIL (%s)\n", why);
		smoke_status = 1;
	}
	if (window != null) {
		window.close();
	}
}

private void run_hello(WebView view) {
	var html = """
		<html><body style="font-family:sans-serif;margin:2em">
		<h1>Hello WebView2</h1>
		<p>Script message: <code>window.webkit.messageHandlers.ping.postMessage</code></p>
		<pre id="out">waiting…</pre>
		<script>
		function send() {
			window.webkit.messageHandlers.ping.postMessage({ hello: "world" });
		}
		if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ping) {
			send();
		} else {
			setTimeout(send, 200);
		}
		</script>
		</body></html>
	""";

	view.resource_load_started.connect((resource, request) => {
		print("resource_load_started %s\n", request.uri);
		resource.finished.connect(() => {
			print("resource finished %s\n", resource.uri);
		});
		resource.failed.connect((err) => {
			print("resource failed %s: %s\n", resource.uri, err.message);
		});
	});
	var mgr = view.get_user_content_manager();
	mgr.script_message_received["ping"].connect((values) => {
		var json = values.to_json();
		print("script-message-received::ping %s\n", json);
		var script = "document.getElementById('out').textContent = 'host saw: ' + JSON.stringify("
			+ json + ");";
		view.evaluate_javascript.begin(script, -1, null, null, null, (obj, res) => {
				try {
					view.evaluate_javascript.end(res);
				} catch (Error e) {
					warning("evaluate_javascript: %s", e.message);
				}
			});
	});
	mgr.register_script_message_handler("ping", null);
	view.load_html(html, null);
}

private void run_smoke_policy_ignore(WebView view) {
	view.decide_policy.connect((decision, type) => {
		if (type != PolicyDecisionType.RESPONSE) {
			return false;
		}
		var rd = decision as ResponsePolicyDecision;
		if (rd == null || !rd.is_main_frame_main_resource()) {
			return false;
		}
		var mime = mime_from(rd.response.http_headers);
		print("decide_policy RESPONSE mime=%s uri=%s\n", mime, rd.response.uri);
		if (mime == "text/html" || mime == "application/xhtml+xml" || mime == "") {
			return false;
		}
		decision.ignore();
		return true;
	});
	view.load_changed.connect((load_event) => {
		if (load_event != LoadEvent.FINISHED || smoke_done) {
			return;
		}
		if (!html_finished) {
			html_finished = true;
			print("smoke-policy-ignore html FINISHED\n");
			view.load_uri(PDF_URI);
			return;
		}
		print("smoke-policy-ignore unexpected FINISHED uri=%s\n", view.get_uri());
		finish_smoke(false, "FINISHED after PDF load");
	});
	view.load_failed.connect((load_event, failing_uri, error) => {
		if (smoke_done) {
			return false;
		}
		print("smoke-policy-ignore load_failed %s: %s\n", failing_uri, error.message);
		if (!(error is NetworkError.CANCELLED)) {
			finish_smoke(false, "load_failed not cancelled");
			return true;
		}
		if (failing_uri.index_of("dummy.pdf") < 0) {
			finish_smoke(false, "cancelled uri was not the PDF");
			return true;
		}
		var tries = 0;
		Timeout.add(200, () => {
			if (smoke_done) {
				return Source.REMOVE;
			}
			tries++;
			var live = view.get_uri();
			print("smoke-policy-ignore after ignore uri=%s loading=%s try=%d\n",
				live, view.is_loading ? "yes" : "no", tries);
			if (live.index_of("dummy.pdf") < 0) {
				finish_smoke(true, "");
				return Source.REMOVE;
			}
			if (tries >= 25) {
				finish_smoke(false, "PDF URI still committed");
				return Source.REMOVE;
			}
			return Source.CONTINUE;
		});
		return true;
	});
	view.load_html(
		"<html><head><title>policy html</title></head><body><h1>policy html</h1></body></html>",
		null
	);
	Timeout.add(30000, () => {
		if (!smoke_done) {
			print("smoke-policy-ignore timeout html_finished=%s uri=%s\n",
				html_finished ? "yes" : "no",
				view.get_uri());
			finish_smoke(false, "timeout");
		}
		return Source.REMOVE;
	});
}

public static int main(string[] args) {
	string[] gtk_args = {};
	for (var i = 0; i < args.length; i++) {
		if (i == 0) {
			gtk_args += args[i];
			continue;
		}
		if (args[i] == "--smoke-policy-ignore") {
			smoke_policy_ignore = true;
			continue;
		}
		gtk_args += args[i];
	}

	var app = new Gtk.Application("com.webview2gtk.hello", ApplicationFlags.FLAGS_NONE);
	app.activate.connect(() => {
		window = new Gtk.ApplicationWindow(app);
		window.set_title("webview2-gtk hello");
		window.set_default_size(640, 480);

		web = new WebView();
		web.set_hexpand(true);
		web.set_vexpand(true);
		if (smoke_policy_ignore) {
			run_smoke_policy_ignore(web);
		} else {
			run_hello(web);
		}
		window.set_child(web);
		window.present();
	});
	app.run(gtk_args);
	return smoke_policy_ignore ? smoke_status : 0;
}
