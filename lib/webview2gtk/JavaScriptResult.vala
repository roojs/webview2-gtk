namespace WebView2Gtk {

public class JavaScriptResult : Object {
	private string _json;

	public JavaScriptResult (string json) {
		_json = json;
	}

	public string to_json (int indent = 0) {
		return _json;
	}

	/** JSC.Value-shaped helper — unwrap JSON string literals. */
	public string to_string () {
		if (_json == null || _json == "" || _json == "null") {
			return "";
		}
		if (_json.has_prefix ("\"") && _json.has_suffix ("\"")) {
			try {
				var parser = new Json.Parser ();
				parser.load_from_data (_json, -1);
				var root = parser.get_root ();
				if (root.get_value_type () == Type.STRING) {
					return root.get_string ();
				}
			} catch (GLib.Error e) {
			}
		}
		return _json;
	}

	public int32 to_int32 () {
		if (_json == null || _json == "" || _json == "null") {
			return 0;
		}
		return int.parse (_json);
	}
}

}
