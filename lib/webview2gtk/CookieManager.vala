namespace WebView2Gtk {

public class CookieManager : Object {
	private weak NetworkSession? session;

	internal CookieManager(NetworkSession session) {
		this.session = session;
	}

	public void set_accept_policy(CookieAcceptPolicy policy) {
	}

	public void set_persistent_storage(string filename, CookiePersistentStorage storage) {
	}

	public async GLib.List<Soup.Cookie> get_cookies(
		string uri,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		if (this.session == null) {
			throw new NetworkError.FAILED("get_cookies failed");
		}
		this.session.apply_pending_cookies();
		while (this.session == null
			|| this.session.cookie_host_handle() == null
			|| !wv2_host_is_ready(this.session.cookie_host_handle())) {
			if (this.session == null) {
				throw new NetworkError.FAILED("get_cookies failed");
			}
			if (cancellable != null && cancellable.is_cancelled()) {
				throw new IOError.CANCELLED("get_cookies cancelled");
			}
			Idle.add(get_cookies.callback);
			yield;
			this.session.apply_pending_cookies();
		}
		var host = this.session.cookie_host_handle();
		string? raw = null;
		if (host == null || !wv2_get_cookies_sync(host, uri, out raw)) {
			throw new NetworkError.FAILED("get_cookies failed");
		}
		var list = new GLib.List<Soup.Cookie> ();
		if (raw == null || raw.strip() == "") {
			return list;
		}
		GLib.Uri origin;
		try {
			origin = GLib.Uri.parse(uri, GLib.UriFlags.NONE);
		} catch (GLib.Error e) {
			throw e;
		}
		foreach (var line in raw.split("\n")) {
			var header = line.strip();
			if (header == "") {
				continue;
			}
			var cookie = Soup.Cookie.parse(header, origin);
			if (cookie != null) {
				list.append(cookie);
			}
		}
		return list;
	}

	public async bool add_cookie(
		Soup.Cookie cookie,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		if (this.session == null) {
			throw new NetworkError.FAILED("add_cookie failed");
		}
		var pending = this.session.enqueue_cookie(
			cookie.get_name(),
			cookie.get_value() ?? "",
			cookie.get_domain() ?? "",
			cookie.get_path() ?? "/",
			cookie.get_http_only(),
			cookie.get_secure()
		);
		while (!pending.done) {
			if (cancellable != null && cancellable.is_cancelled()) {
				throw new IOError.CANCELLED("add_cookie cancelled");
			}
			Idle.add(add_cookie.callback);
			yield;
			this.session.apply_pending_cookies();
		}
		if (!pending.ok) {
			throw new NetworkError.FAILED("add_cookie failed");
		}
		return true;
	}
}

}
