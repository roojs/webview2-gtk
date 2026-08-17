namespace WebView2Gtk {

public class JavaScriptResult : Object {
	private string json;

	public JavaScriptResult(string json) {
		this.json = json;
	}

	public string to_json(int indent = 0) {
		return json;
	}

	/** JSC.Value-shaped helper — unwrap JSON string literals. */
	public string to_string() {
		if (json == null || json == "" || json == "null") {
			return "";
		}
		if (json.length >= 2
			&& json.has_prefix("\"")
			&& json.has_suffix("\"")) {
			return json.substring(1, json.length - 2)
				.replace("\\\"", "\"")
				.replace("\\\\", "\\");
		}
		return json;
	}

	public int32 to_int32() {
		if (json == null || json == "" || json == "null") {
			return 0;
		}
		return int.parse(json);
	}
}

}
