namespace WebView2Gtk {

public class CookieManager : Object {
	public void set_accept_policy (CookieAcceptPolicy policy) {
	}

	public void set_persistent_storage (string filename, CookiePersistentStorage storage) {
	}

	public async GLib.List<Soup.Cookie> get_cookies (
		string uri,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		string? raw = null;
		if (!wv2_get_cookies_sync (uri, out raw)) {
			throw new NetworkError.FAILED ("get_cookies failed");
		}
		var list = new GLib.List<Soup.Cookie> ();
		if (raw == null || raw.strip () == "") {
			return list;
		}
		GLib.Uri origin;
		try {
			origin = GLib.Uri.parse (uri, GLib.UriFlags.NONE);
		} catch (GLib.Error e) {
			throw e;
		}
		foreach (var line in raw.split ("\n")) {
			var header = line.strip ();
			if (header == "") {
				continue;
			}
			var cookie = Soup.Cookie.parse (header, origin);
			if (cookie != null) {
				list.append (cookie);
			}
		}
		return list;
	}

	public async bool add_cookie (
		Soup.Cookie cookie,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		if (!wv2_add_cookie_sync (
			cookie.get_name (),
			cookie.get_value (),
			cookie.get_domain (),
			cookie.get_path (),
			cookie.get_http_only (),
			cookie.get_secure ()
		)) {
			throw new NetworkError.FAILED ("add_cookie failed");
		}
		return true;
	}
}

}
