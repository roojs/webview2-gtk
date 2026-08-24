/* Host UIA bindings for Win32Atspi(not part of WebView2Gtk.WebView). */

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_a11y_invoke")]
extern bool wv2_a11y_invoke(int id);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_a11y_set_value")]
extern bool wv2_a11y_set_value(int id, string utf8);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_a11y_focus")]
extern bool wv2_a11y_focus(int id);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_a11y_type_text")]
extern bool wv2_a11y_type_text(string utf8);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_a11y_key_vk")]
extern bool wv2_a11y_key_vk(uint16 vk);

[CCode(has_target = false)]
public delegate void Wv2A11yForeachCb(
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
);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_a11y_walk_foreach")]
extern bool wv2_a11y_walk_foreach(void* host, Wv2A11yForeachCb cb, void* user_data);
