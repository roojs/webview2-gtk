/* Win32 AT-SPI-shaped facade over WebView2 UIA(parallel to WebView2Gtk). */

namespace Win32Atspi {

public enum CoordType {
	SCREEN,
	WINDOW,
	PARENT
}

public enum ScrollType {
	TOP_EDGE,
	BOTTOM_EDGE,
	LEFT_EDGE,
	RIGHT_EDGE,
	ANYWHERE
}

public enum KeySynthType {
	PRESS,
	RELEASE,
	PRESSRELEASE,
	STRING
}

public class ComponentExtents : Object {
	public int x { get; set; }
	public int y { get; set; }
	public int width { get; set; }
	public int height { get; set; }
}

public class Text : Object {
	private string text;

	public Text(string text) {
		this.text = text ?? "";
	}

	public int get_character_count() {
		return (int) this.text.char_count();
	}

	public string get_text(int start_offset, int end_offset) {
		/* Typical AT-SPI clients ask 0..nchars — return full value. */
		return this.text ?? "";
	}
}

public class Hyperlink : Object {
	private string uri;

	public Hyperlink(string uri) {
		this.uri = uri ?? "";
	}

	public int get_n_anchors() {
		return this.uri != "" ? 1 : 0;
	}

	public string get_uri(int i) {
		return i == 0 ? this.uri : "";
	}
}

/**
 * One node in the emulated AT-SPI tree(backed by UIA walk cache ids where set).
 */
public class Accessible : Object {
	internal string name = "";
	internal string role_name = "";
	internal string description = "";
	internal uint process_id = 0;
	internal int walk_id = -1;
	internal int x = 0;
	internal int y = 0;
	internal int w = 0;
	internal int h = 0;
	internal string value_text = "";
	internal string uri = "";
	internal bool can_invoke = false;
	internal bool can_set_value = false;

	private Gee.ArrayList<Accessible> children = new Gee.ArrayList<Accessible> ();
	private Gee.ArrayList<string> action_names = new Gee.ArrayList<string> ();
	private Gee.HashMap<string, string> attrs = new Gee.HashMap<string, string> ();
	private Gee.ArrayList<string> ifaces = new Gee.ArrayList<string> ();

	internal void add_child(Accessible child) {
		this.children.add(child);
	}

	internal void add_action(string action_name) {
		this.action_names.add(action_name);
	}

	internal void set_attr(string key, string val) {
		this.attrs.set(key, val);
	}

	internal void add_iface(string name) {
		if (!this.ifaces.contains(name)) {
			this.ifaces.add(name);
		}
	}

	public string get_name() {
		return this.name;
	}

	public string get_role_name() {
		return this.role_name;
	}

	public string get_description() {
		return this.description;
	}

	public uint get_process_id() {
		return this.process_id;
	}

	public int get_child_count() {
		return this.children.size;
	}

	public Accessible get_child_at_index(int index) {
		return this.children.get(index);
	}

	public HashTable<string, string> get_attributes() {
		var ht = new HashTable<string, string> (str_hash, str_equal);
		foreach (var k in this.attrs.keys) {
			ht.insert(k, this.attrs.get(k));
		}
		return ht;
	}

	public GLib.Array<string> get_interfaces() {
		var a = new GLib.Array<string> ();
		foreach (var i in this.ifaces) {
			a.append_val(i);
		}
		return a;
	}

	public int get_n_actions() {
		return this.action_names.size;
	}

	public string get_action_name(int index) {
		return this.action_names.get(index);
	}

	public bool do_action(int index) {
		if (index < 0 || index >= this.action_names.size) {
			return false;
		}
		var web = Bridge.host;
		if (web == null) {
			return this.action_names.get(index) == "default.activate";
		}
		if (this.walk_id < 0) {
			return true;
		}
		/* Editable: focus only. Invokable: InvokePattern. */
		if (this.can_set_value && !this.can_invoke) {
			return wv2_a11y_focus(this.walk_id);
		}
		if (this.can_invoke) {
			return wv2_a11y_invoke(this.walk_id);
		}
		return wv2_a11y_focus(this.walk_id);
	}

	public bool grab_focus() {
		if (this.walk_id < 0) {
			return false;
		}
		return wv2_a11y_focus(this.walk_id);
	}

	/**
	 * Set the field value(UIA ValuePattern). Prefer after {@link grab_focus} for some hosts.
	 */
	public bool set_text_contents(string text) {
		if (this.walk_id < 0 || !this.can_set_value) {
			return false;
		}
		var ok = wv2_a11y_set_value(this.walk_id, text);
		if (ok) {
			this.value_text = text;
		}
		return ok;
	}

	public ComponentExtents get_extents(CoordType coord_type) {
		var e = new ComponentExtents();
		e.x = this.x;
		e.y = this.y;
		e.width = this.w;
		e.height = this.h;
		return e;
	}

	public void scroll_to(ScrollType type) throws Error {
		/* UIA tree already includes off-screen names for our walks; no-op. */
	}

	public Text get_text_iface() {
		var t = this.value_text != "" ? this.value_text : this.name;
		return new Text(t);
	}

	public Hyperlink? get_hyperlink() {
		if (this.uri == "") {
			return null;
		}
		return new Hyperlink(this.uri);
	}
}

internal class Bridge : Object {
	public static WebView2Gtk.WebView? host;
	public static Accessible? desktop;
	public static bool ready;

	private class WalkRow {
		public int id;
		public int parent_id;
		public int x;
		public int y;
		public int w;
		public int h;
		public string name;
		public string role;
		public string value;
		public string uri;
		public bool can_invoke;
		public bool can_set_value;
	}

	private static GenericArray<WalkRow>? walk_accum;

	private static void walk_cb(
		int id,
		int parent_id,
		int x,
		int y,
		int w,
		int h,
		string name,
		string role,
		string value,
		string uri,
		bool can_invoke,
		bool can_set_value,
		void* user_data
	) {
		if (walk_accum == null) {
			return;
		}
		var row = new WalkRow();
		row.id = id;
		row.parent_id = parent_id;
		row.x = x;
		row.y = y;
		row.w = w;
		row.h = h;
		row.name = name;
		row.role = role;
		row.value = value;
		row.uri = uri;
		row.can_invoke = can_invoke;
		row.can_set_value = can_set_value;
		walk_accum.add(row);
	}

	public static void register(WebView2Gtk.WebView web) {
		Bridge.host = web;
		Bridge.desktop = null;
	}

	public static void ensure_tree() throws Error {
		if (Bridge.host == null || !Bridge.host.ready) {
			throw new IOError.FAILED("Win32Atspi: no WebView registered(host not ready)");
		}
		Bridge.rebuild();
	}

	public static void rebuild() {
		walk_accum = new GenericArray<WalkRow> ();
		var ok = wv2_a11y_walk_foreach(walk_cb, null);
		var tree = walk_accum;
		walk_accum = null;
		if (!ok || tree == null) {
			tree = new GenericArray<WalkRow> ();
		}

		var pid = (uint) Posix.getpid();

		var desktop = new Accessible();
		desktop.name = "Desktop";
		desktop.role_name = "desktop frame";
		desktop.process_id = 0;

		var app = new Accessible();
		app.name = "Application";
		app.role_name = "application";
		app.process_id = pid;
		desktop.add_child(app);

		var frame = new Accessible();
		frame.name = "Frame";
		frame.role_name = "frame";
		frame.process_id = pid;
		frame.add_action("default.activate");
		app.add_child(frame);

		var by_id = new Gee.HashMap<int, Accessible> ();
		Accessible? doc = null;

		for (var i = 0; i < tree.length; i++) {
			var n = tree.get(i);
			var acc = accessible_from_tree_node(n, pid);
			by_id.set(n.id, acc);
			if (n.role == "Document") {
				doc = acc;
			} else if (doc == null && n.parent_id < 0) {
				doc = acc;
			}
		}

		for (var i = 0; i < tree.length; i++) {
			var n = tree.get(i);
			if (!by_id.has_key(n.id)) {
				continue;
			}
			var acc = by_id.get(n.id);
			if (n.parent_id < 0) {
				continue;
			}
			if (by_id.has_key(n.parent_id)) {
				by_id.get(n.parent_id).add_child(acc);
			}
		}

		if (doc == null && tree.length > 0 && by_id.has_key(tree.get(0).id)) {
			doc = by_id.get(tree.get(0).id);
		}
		if (doc != null) {
			/* Prefer AT-SPI document role names used by tree walkers. */
			if (doc.role_name != "document text" && doc.role_name != "document frame") {
				doc.role_name = "document frame";
			}
			frame.add_child(doc);
		}

		Bridge.desktop = desktop;
	}

	private static Accessible accessible_from_tree_node(WalkRow n, uint pid) {
		var role = atspi_role(n.role);
		var acc = new Accessible();
		acc.name = n.name;
		acc.role_name = role;
		acc.process_id = pid;
		acc.walk_id = n.id;
		acc.x = n.x;
		acc.y = n.y;
		acc.w = n.w;
		acc.h = n.h;
		acc.value_text = n.value;
		acc.uri = n.uri != "" ? n.uri : (n.value.has_prefix("http") ? n.value : "");
		acc.can_invoke = n.can_invoke;
		acc.can_set_value = n.can_set_value;
		if (n.can_invoke || n.can_set_value) {
			acc.add_action("click");
			acc.add_iface("Action");
		}
		if (n.can_set_value || n.value != "" || role == "entry" || role == "combo box"
		    || role == "password text") {
			acc.add_iface("Text");
		}
		if (acc.uri != "" || role == "link") {
			acc.add_iface("Hyperlink");
			if (acc.uri != "") {
				acc.set_attr("computed-role", "link");
			}
		}
		/* Map UIA roles toward common computed-role attribute values. */
		switch (n.role) {
		case "Hyperlink":
			acc.set_attr("computed-role", "link");
			break;
		case "Button":
			acc.set_attr("computed-role", "button");
			break;
		case "ComboBox":
			acc.set_attr("computed-role", "combobox");
			break;
		case "Edit":
			acc.set_attr("computed-role", "textbox");
			break;
		case "Text":
			acc.set_attr("computed-role", "text");
			break;
		}
		return acc;
	}

	private static string atspi_role(string uia) {
		switch (uia) {
		case "Document":
			return "document frame";
		case "Hyperlink":
			return "link";
		case "Button":
			return "push button";
		case "ComboBox":
			return "combo box";
		case "Edit":
			return "entry";
		case "Text":
			return "text";
		case "Group":
			return "panel";
		case "List":
			return "list";
		case "ListItem":
			return "list item";
		case "Image":
			return "image";
		case "TabItem":
			return "page tab";
		default:
			return uia.down();
		}
	}
}

public void init() {
	Bridge.ready = true;
	Bridge.desktop = null;
}

public Accessible get_desktop(int index) {
	try {
		Bridge.ensure_tree();
	} catch (Error e) {
		/* Return empty desktop so callers get a clear later failure. */
		if (Bridge.desktop == null) {
			Bridge.desktop = new Accessible();
			Bridge.desktop.name = "Desktop";
			Bridge.desktop.role_name = "desktop frame";
		}
	}
	return Bridge.desktop;
}

/**
 * Register the WebView that backs this process's AT-SPI tree.
 * Called automatically when {@link WebView2Gtk.WebView} becomes ready.
 */
public void register_webview(WebView2Gtk.WebView web) {
	Bridge.register(web);
}

public void generate_keyboard_event(long keyval, string? keystring, KeySynthType synth) {
	Win32AtspiWin.synthesize(keyval, keystring, synth);
}

}
