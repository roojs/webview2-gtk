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

	private async void* wait_cookie_host(GLib.Cancellable? cancellable, string op) throws GLib.Error {
		if (this.session == null) {
			throw new NetworkError.FAILED("%s failed", op);
		}
		this.session.apply_pending_cookies();
		while (this.session == null
			|| this.session.cookie_host_handle() == null
			|| !wv2_host_is_ready(this.session.cookie_host_handle())) {
			if (this.session == null) {
				throw new NetworkError.FAILED("%s failed", op);
			}
			if (cancellable != null && cancellable.is_cancelled()) {
				throw new IOError.CANCELLED("%s cancelled", op);
			}
			Idle.add(wait_cookie_host.callback);
			yield;
			this.session.apply_pending_cookies();
		}
		var host = this.session.cookie_host_handle();
		if (host == null) {
			throw new NetworkError.FAILED("%s failed", op);
		}
		return host;
	}

	private static GLib.Uri origin_for_set_cookie_line(string header) throws GLib.Error {
		string? domain = null;
		foreach (var part in header.split(";")) {
			var bit = part.strip();
			if (!bit.down().has_prefix("domain=")) {
				continue;
			}
			domain = bit.substring(7).strip();
			break;
		}
		if (domain != null && domain != "") {
			if (domain.has_prefix(".")) {
				domain = domain.substring(1);
			}
			return GLib.Uri.parse("https://%s/".printf(domain), GLib.UriFlags.NONE);
		}
		return GLib.Uri.parse("https://localhost/", GLib.UriFlags.NONE);
	}

	private static GLib.List<Soup.Cookie> parse_cookie_lines(string? raw) throws GLib.Error {
		var list = new GLib.List<Soup.Cookie> ();
		if (raw == null || raw.strip() == "") {
			return list;
		}
		foreach (var line in raw.split("\n")) {
			var header = line.strip();
			if (header == "") {
				continue;
			}
			var origin = origin_for_set_cookie_line(header);
			var cookie = Soup.Cookie.parse(header, origin);
			if (cookie != null) {
				list.append(cookie);
			}
		}
		return list;
	}

	public async GLib.List<Soup.Cookie> get_cookies(
		string uri,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		var host = yield this.wait_cookie_host(cancellable, "get_cookies");
		string? raw = null;
		if (!wv2_get_cookies_sync(host, uri, out raw)) {
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

	/**
	 * Every cookie in the session profile (WebKitGTK-shaped get_all_cookies).
	 * WebView2: GetCookies with a null URI.
	 */
	public async GLib.List<Soup.Cookie> get_all_cookies(
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		var host = yield this.wait_cookie_host(cancellable, "get_all_cookies");
		string? raw = null;
		if (!wv2_get_cookies_sync(host, null, out raw)) {
			throw new NetworkError.FAILED("get_all_cookies failed");
		}
		return parse_cookie_lines(raw);
	}

	/**
	 * Replace the session jar with cookies (clear then add).
	 * Empty list clears all cookies under the profile.
	 */
	public async bool replace_cookies(
		GLib.List<Soup.Cookie> cookies,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		var host = yield this.wait_cookie_host(cancellable, "replace_cookies");
		if (!wv2_delete_all_cookies_sync(host)) {
			throw new NetworkError.FAILED("replace_cookies failed");
		}
		foreach (unowned Soup.Cookie cookie in cookies) {
			if (cancellable != null && cancellable.is_cancelled()) {
				throw new IOError.CANCELLED("replace_cookies cancelled");
			}
			if (!wv2_add_cookie_sync(
				host,
				cookie.get_name(),
				cookie.get_value() ?? "",
				cookie.get_domain() ?? "",
				cookie.get_path() ?? "/",
				cookie.get_http_only(),
				cookie.get_secure()
			)) {
				throw new NetworkError.FAILED("replace_cookies failed");
			}
		}
		return true;
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
