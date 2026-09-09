namespace WebView2Gtk {

public class CookieManager : Object {
	private weak NetworkSession? session;
	private string? persist_path = null;
	private bool persist_text = false;
	private GenericArray<Soup.Cookie> persist_jar = new GenericArray<Soup.Cookie> ();

	/**
	 * WebKitGTK-shaped — emitted after successful {@link add_cookie} /
	 * {@link replace_cookies}. Page Set-Cookie / host jar mutations are not
	 * observed (WebView2 exposes no cookie-change COM event here).
	 */
	public signal void changed();

	internal CookieManager(NetworkSession session) {
		this.session = session;
	}

	public void set_accept_policy(CookieAcceptPolicy policy) {
	}

	/**
	 * WebKitGTK-shaped path jar. {@link CookiePersistentStorage.TEXT} loads and
	 * flushes newline Set-Cookie headers at {@code filename}.
	 * {@link CookiePersistentStorage.SQLITE} is not supported ({@link GLib.error}).
	 * No-op on ephemeral / automation sessions.
	 */
	public void set_persistent_storage(string filename, CookiePersistentStorage storage) {
		if (this.session != null && this.session.is_ephemeral()) {
			return;
		}
		if (storage == CookiePersistentStorage.SQLITE) {
			GLib.error("CookiePersistentStorage.SQLITE is not supported; use CookiePersistentStorage.TEXT");
		}
		if (filename == "") {
			return;
		}
		this.persist_path = filename;
		this.persist_text = true;
		this.persist_jar = new GenericArray<Soup.Cookie> ();
		this.load_persist_file();
	}

	private bool using_persist_jar() {
		return this.persist_text && this.persist_path != null;
	}

	private void load_persist_file() {
		string contents;
		try {
			GLib.FileUtils.get_contents(this.persist_path, out contents);
		} catch (GLib.Error e) {
			return;
		}
		try {
			var list = parse_cookie_lines(contents);
			foreach (unowned Soup.Cookie cookie in list) {
				this.persist_jar.add(cookie.copy());
			}
		} catch (GLib.Error e) {
			GLib.warning("cookie persist load failed path=%s err=%s", this.persist_path, e.message);
		}
	}

	private void flush_persist_file() {
		if (!this.using_persist_jar()) {
			return;
		}
		var builder = new GLib.StringBuilder();
		for (var i = 0; i < this.persist_jar.length; i++) {
			if (builder.len > 0) {
				builder.append_c('\n');
			}
			builder.append(this.persist_jar[i].to_set_cookie_header());
		}
		var dir = GLib.Path.get_dirname(this.persist_path);
		try {
			if (dir != "" && dir != "." && !GLib.FileUtils.test(dir, GLib.FileTest.IS_DIR)) {
				GLib.File.new_for_path(dir).make_directory_with_parents();
			}
			GLib.FileUtils.set_contents(this.persist_path, builder.str);
		} catch (GLib.Error e) {
			GLib.warning("cookie persist flush failed path=%s err=%s", this.persist_path, e.message);
		}
	}

	private void persist_upsert(Soup.Cookie cookie) {
		var name = cookie.get_name();
		var domain = cookie.get_domain() ?? "";
		var path = cookie.get_path() ?? "/";
		for (var i = 0; i < this.persist_jar.length; i++) {
			var existing = this.persist_jar[i];
			if (existing.get_name() != name) {
				continue;
			}
			if ((existing.get_domain() ?? "") != domain) {
				continue;
			}
			if ((existing.get_path() ?? "/") != path) {
				continue;
			}
			this.persist_jar.remove_index(i);
			break;
		}
		this.persist_jar.add(cookie.copy());
	}

	private GLib.List<Soup.Cookie> persist_all_copy() {
		var list = new GLib.List<Soup.Cookie> ();
		for (var i = 0; i < this.persist_jar.length; i++) {
			list.append(this.persist_jar[i].copy());
		}
		return list;
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
		if (this.using_persist_jar()) {
			GLib.Uri origin;
			try {
				origin = GLib.Uri.parse(uri, GLib.UriFlags.NONE);
			} catch (GLib.Error e) {
				throw e;
			}
			var list = new GLib.List<Soup.Cookie> ();
			for (var i = 0; i < this.persist_jar.length; i++) {
				var cookie = this.persist_jar[i];
				if (cookie.applies_to_uri(origin)) {
					list.append(cookie.copy());
				}
			}
			return list;
		}
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
	 * Persist TEXT jar when set; else WebView2 GetCookies with a null URI.
	 */
	public async GLib.List<Soup.Cookie> get_all_cookies(
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		if (this.using_persist_jar()) {
			return this.persist_all_copy();
		}
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
	 *
	 * Queues through the same host-ready / pending path as {@link add_cookie}
	 * so a large list enqueued before attach is drained in finish_setup
	 * before the first Navigate (avoids AV from COM cookie work overlapping
	 * early navigation). When the host is already live, clear then adds with
	 * Idle between COM calls.
	 */
	public async bool replace_cookies(
		GLib.List<Soup.Cookie> cookies,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		if (this.using_persist_jar()) {
			this.persist_jar = new GenericArray<Soup.Cookie> ();
			foreach (unowned Soup.Cookie cookie in cookies) {
				if (cancellable != null && cancellable.is_cancelled()) {
					throw new IOError.CANCELLED("replace_cookies cancelled");
				}
				this.persist_jar.add(cookie.copy());
			}
			this.flush_persist_file();
			this.changed();
			return true;
		}
		if (this.session == null) {
			throw new NetworkError.FAILED("replace_cookies failed");
		}
		var op = this.session.enqueue_replace(cookies);
		while (!op.done) {
			if (cancellable != null && cancellable.is_cancelled()) {
				throw new IOError.CANCELLED("replace_cookies cancelled");
			}
			Idle.add(replace_cookies.callback);
			yield;
			this.session.apply_pending_cookies(false);
		}
		if (!op.ok) {
			throw new NetworkError.FAILED("replace_cookies failed");
		}
		this.changed();
		return true;
	}

	public async bool add_cookie(
		Soup.Cookie cookie,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		if (this.using_persist_jar()) {
			this.persist_upsert(cookie);
			this.flush_persist_file();
			this.changed();
			return true;
		}
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
		this.changed();
		return true;
	}
}

}
