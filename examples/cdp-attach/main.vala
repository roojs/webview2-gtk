/* CDP attach + fill smoke (plan 3.0 / 3.3).

AI SLOP - just for testing -- not reviewed
 *
 * External client against webview2gtk-automation's --remote-debugging-port.
 * Proves fill via CDP — not a WebView fill API.
 *
 *   webview2gtk-automation.exe --inspector-port 19222
 *   webview2gtk-cdp-attach.exe [port] [fill-text]
 */

int main(string[] args)
{
	var port = 19222;
	var fill_text = "webview2gtk-cdp-fill";
	if (args.length > 1) {
		port = int.parse(args[1]);
	}
	if (args.length > 2) {
		fill_text = args[2];
	}

	var loop = new GLib.MainLoop();
	int exit_code = 1;
	run.begin(port, fill_text, (obj, res) => {
		try {
			run.end(res);
			print("ATTACH_FILL_PASS\n");
			exit_code = 0;
		} catch (GLib.Error e) {
			stderr.printf("cdp-attach: %s\n", e.message);
			exit_code = 1;
		}
		loop.quit();
	});
	loop.run();
	return exit_code;
}

async void run(int port, string fill_text) throws GLib.Error
{
	var base_url = "http://127.0.0.1:%d".printf(port);
	var session = new Soup.Session();
	session.set_timeout(8);

	stderr.printf("CDP /json/version ...\n");
	var ver_msg = new Soup.Message("GET", "%s/json/version".printf(base_url));
	var ver_bytes = yield session.send_and_read_async(ver_msg, GLib.Priority.DEFAULT, null);
	if (ver_msg.status_code != 200) {
		throw new GLib.IOError.FAILED(
			"Cannot reach %s/json/version (HTTP %u) — is webview2gtk-automation.exe running?",
			base_url,
			ver_msg.status_code
		);
	}
	stderr.printf("  %s\n", bytes_to_string(ver_bytes));

	stderr.printf("CDP /json/list ...\n");
	var list_msg = new Soup.Message("GET", "%s/json/list".printf(base_url));
	var list_bytes = yield session.send_and_read_async(list_msg, GLib.Priority.DEFAULT, null);
	if (list_msg.status_code != 200) {
		throw new GLib.IOError.FAILED("/json/list HTTP %u", list_msg.status_code);
	}

	var ws_url = pick_page_ws_url(bytes_to_string(list_bytes));
	stderr.printf("  ws = %s\n", ws_url);

	var http_ws = ws_url
		.replace("ws://", "http://")
		.replace("wss://", "https://");
	var ws_msg = new Soup.Message("GET", http_ws);
	stderr.printf("WebSocket CDP attach ...\n");
	var conn = yield session.websocket_connect_async(
		ws_msg,
		null,
		null,
		GLib.Priority.DEFAULT,
		null
	);
	stderr.printf("  attached\n");

	var expr = (
		"(() => {"
		+ "  const q = document.querySelector('#q');"
		+ "  if (!q) return { ok: false, err: 'no #q' };"
		+ "  q.focus();"
		+ "  q.value = '';"
		+ "  q.value = %s;".printf(json_quote(fill_text))
		+ "  q.dispatchEvent(new Event('input', { bubbles: true }));"
		+ "  return { ok: true, value: q.value };"
		+ "})()"
	);

	var msg_id = 1;
	var payload = new Json.Builder();
	payload.begin_object();
	payload.set_member_name("id");
	payload.add_int_value(msg_id);
	payload.set_member_name("method");
	payload.add_string_value("Runtime.evaluate");
	payload.set_member_name("params");
	payload.begin_object();
	payload.set_member_name("expression");
	payload.add_string_value(expr);
	payload.set_member_name("returnByValue");
	payload.add_boolean_value(true);
	payload.end_object();
	payload.end_object();
	var generator = new Json.Generator();
	generator.set_root(payload.get_root());
	var request_text = generator.to_data(null);

	var reply = yield cdp_wait_reply(conn, msg_id, request_text);
	conn.close(Soup.WebsocketCloseCode.NORMAL, "done");

	var robj = reply.get_object();
	if (robj.has_member("error")) {
		var gen = new Json.Generator();
		gen.set_root(robj.get_member("error"));
		throw new GLib.IOError.FAILED("CDP error: %s", gen.to_data(null));
	}

	var result = robj.get_object_member("result");
	if (result == null || !result.has_member("result")) {
		throw new GLib.IOError.FAILED("CDP reply missing result.result");
	}
	var inner = result.get_object_member("result");
	if (inner == null || !inner.has_member("value")) {
		throw new GLib.IOError.FAILED("CDP reply missing result.result.value");
	}
	var val = inner.get_object_member("value");
	var gen2 = new Json.Generator();
	gen2.set_root(inner.get_member("value"));
	stderr.printf("evaluate => %s\n", gen2.to_data(null));

	var ok = false;
	var got = "";
	if (val != null) {
		ok = val.has_member("ok") && val.get_boolean_member("ok");
		if (val.has_member("value")) {
			got = val.get_string_member("value");
		}
	}
	if (!ok || got != fill_text) {
		throw new GLib.IOError.FAILED("Fill did not stick (expected value=%s)", fill_text);
	}
}

async Json.Node cdp_wait_reply(
	Soup.WebsocketConnection conn,
	int msg_id,
	string request_text
) throws GLib.Error {
	GLib.SourceFunc resume = cdp_wait_reply.callback;
	Json.Node? reply_root = null;
	GLib.Error? reply_err = null;
	ulong mid = 0;
	ulong eid = 0;
	ulong cid = 0;
	uint tid = 0;

	mid = conn.message.connect((type, message) => {
		if (type != Soup.WebsocketDataType.TEXT) {
			return;
		}
		try {
			var parser = new Json.Parser();
			parser.load_from_data((string) message.get_data(), (ssize_t) message.get_size());
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
				return;
			}
			var obj = root.get_object();
			if (!obj.has_member("id") || obj.get_int_member("id") != msg_id) {
				return;
			}
			reply_root = root;
			GLib.Idle.add(() => {
				resume();
				return false;
			});
		} catch (GLib.Error e) {
			reply_err = e;
			GLib.Idle.add(() => {
				resume();
				return false;
			});
		}
	});
	eid = conn.error.connect((e) => {
		reply_err = e;
		GLib.Idle.add(() => {
			resume();
			return false;
		});
	});
	cid = conn.closed.connect(() => {
		if (reply_root == null && reply_err == null) {
			reply_err = new GLib.IOError.FAILED("WebSocket closed before CDP reply");
			GLib.Idle.add(() => {
				resume();
				return false;
			});
		}
	});
	tid = GLib.Timeout.add_seconds(8, () => {
		if (reply_root == null && reply_err == null) {
			reply_err = new GLib.IOError.TIMED_OUT("No CDP response for Runtime.evaluate");
			resume();
		}
		return false;
	});

	conn.send_text(request_text);
	yield;

	conn.disconnect(mid);
	conn.disconnect(eid);
	conn.disconnect(cid);
	if (tid != 0) {
		GLib.Source.remove(tid);
	}
	if (reply_err != null) {
		throw reply_err;
	}
	if (reply_root == null) {
		throw new GLib.IOError.FAILED("No CDP response for Runtime.evaluate");
	}
	return reply_root;
}

string bytes_to_string(GLib.Bytes bytes)
{
	return (string) bytes.get_data();
}

string pick_page_ws_url(string list_json) throws GLib.Error
{
	var parser = new Json.Parser();
	parser.load_from_data(list_json, -1);
	var root = parser.get_root();
	if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
		throw new GLib.IOError.FAILED("/json/list is not an array");
	}
	var arr = root.get_array();
	if (arr.get_length() < 1) {
		throw new GLib.IOError.FAILED("No pages in /json/list");
	}

	Json.Object? page = null;
	for (var i = 0; i < arr.get_length(); i++) {
		var o = arr.get_object_element(i);
		if (o != null && o.get_string_member_with_default("type", "") == "page") {
			page = o;
			break;
		}
	}
	if (page == null) {
		page = arr.get_object_element(0);
	}
	if (page == null) {
		throw new GLib.IOError.FAILED("No page object in /json/list");
	}
	stderr.printf("  page url = %s\n", page.get_string_member_with_default("url", ""));
	var ws = page.get_string_member_with_default("webSocketDebuggerUrl", "");
	if (ws == "") {
		throw new GLib.IOError.FAILED("Page has no webSocketDebuggerUrl");
	}
	return ws;
}

string json_quote(string s)
{
	var node = new Json.Node(Json.NodeType.VALUE);
	node.set_string(s);
	var gen = new Json.Generator();
	gen.set_root(node);
	return gen.to_data(null);
}
