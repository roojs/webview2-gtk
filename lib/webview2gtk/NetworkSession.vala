[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_set_proxy_settings")]
extern void wv2_host_set_proxy_settings(int mode, string? proxy_uri);

[CCode(cheader_filename = "webview2gtk-host-api.h", cname = "vala_webview2_host_environment_created")]
extern bool wv2_host_environment_created();

namespace WebView2Gtk {

internal class PendingCookie {
	public string name;
	public string value;
	public string domain;
	public string path;
	public bool http_only;
	public bool secure;
	public bool done;
	public bool ok;
}

/**
 * One replace_cookies operation — clear flag + cookie rows shared with the
 * pending queue so finish_setup can drain them before the first Navigate.
 */
internal class PendingReplace {
	public bool clear_done;
	public bool clear_ok;
	public GenericArray<PendingCookie> cookies = new GenericArray<PendingCookie> ();
	public bool done;
	public bool ok;
}

/**
 * WebKitGTK-shaped network session — cookies + download_started.
 *
 * Download COM handlers are installed per WebView2Host when a WebView binds
 * this session (shared session ⇒ same Vala callbacks on each host).
 */
public class NetworkSession : Object {
	private static weak NetworkSession? active_session = null;

	private CookieManager cookie_manager;
	private GenericArray<Download> downloads = new GenericArray<Download> ();
	private GenericArray<PendingCookie> pending_cookies = new GenericArray<PendingCookie> ();
	private bool pending_clear = false;
	private PendingReplace? active_replace = null;
	private void* cookie_host = null;
	private bool ephemeral = false;
	private NetworkProxyMode proxy_mode = NetworkProxyMode.DEFAULT;
	private NetworkProxySettings? proxy_settings = null;
	private bool proxy_late_warned = false;

	public signal void download_started(Download download);

	public NetworkSession() {
		this.cookie_manager = new CookieManager(this);
		NetworkSession.active_session = this;
	}

	/**
	 * WebKitGTK-shaped — automation sessions are ephemeral; persistent
	 * cookie storage must not apply.
	 */
	internal void mark_ephemeral() {
		this.ephemeral = true;
	}

	internal bool is_ephemeral() {
		return this.ephemeral;
	}

	public CookieManager get_cookie_manager() {
		return this.cookie_manager;
	}

	internal void* cookie_host_handle() {
		return this.cookie_host;
	}

	internal PendingCookie enqueue_cookie(
		string name,
		string value,
		string domain,
		string path,
		bool http_only,
		bool secure
	) {
		var pending = new PendingCookie();
		pending.name = name;
		pending.value = value;
		pending.domain = domain;
		pending.path = path;
		pending.http_only = http_only;
		pending.secure = secure;
		this.pending_cookies.add(pending);
		this.apply_pending_cookies(false);
		return pending;
	}

	/**
	 * Queue DeleteAllCookies + the replacement list. Prefer calling this before
	 * the host is ready so finish_setup drains the jar before first Navigate.
	 */
	internal PendingReplace enqueue_replace(GLib.List<Soup.Cookie> cookies) {
		this.fail_pending_cookies();
		if (this.active_replace != null && !this.active_replace.done) {
			this.active_replace.ok = false;
			this.active_replace.done = true;
		}
		var op = new PendingReplace();
		this.pending_clear = true;
		this.active_replace = op;
		foreach (unowned Soup.Cookie cookie in cookies) {
			var pending = new PendingCookie();
			pending.name = cookie.get_name();
			pending.value = cookie.get_value() ?? "";
			pending.domain = cookie.get_domain() ?? "";
			pending.path = cookie.get_path() ?? "/";
			pending.http_only = cookie.get_http_only();
			pending.secure = cookie.get_secure();
			op.cookies.add(pending);
			this.pending_cookies.add(pending);
		}
		this.apply_pending_cookies(false);
		this.refresh_replace_state(op);
		return op;
	}

	private void refresh_replace_state(PendingReplace op) {
		if (op.done || this.pending_clear || !op.clear_done) {
			return;
		}
		var all_done = true;
		var all_ok = op.clear_ok;
		for (var i = 0; i < op.cookies.length; i++) {
			var c = op.cookies[i];
			if (!c.done) {
				all_done = false;
				break;
			}
			if (!c.ok) {
				all_ok = false;
			}
		}
		if (!all_done) {
			return;
		}
		op.ok = all_ok;
		op.done = true;
		if (this.active_replace == op) {
			this.active_replace = null;
		}
	}

	private bool add_one_pending(PendingCookie pending) {
		pending.ok = wv2_add_cookie_sync(
			this.cookie_host,
			pending.name,
			pending.value,
			pending.domain,
			pending.path,
			pending.http_only,
			pending.secure
		);
		pending.done = true;
		return pending.ok;
	}

	private void prune_done_pending() {
		var remaining = new GenericArray<PendingCookie> ();
		for (var i = 0; i < this.pending_cookies.length; i++) {
			var pending = this.pending_cookies[i];
			if (!pending.done) {
				remaining.add(pending);
			}
		}
		this.pending_cookies = remaining;
	}

	/**
	 * @param drain_all if true, apply clear + every pending cookie now (used
	 * from finish_setup before first Navigate). Otherwise clear then one cookie
	 * per turn with Idle between adds while the UI / navigation is live.
	 */
	internal void apply_pending_cookies(bool drain_all = false) {
		if (this.cookie_host == null || !wv2_host_is_ready(this.cookie_host)) {
			return;
		}

		if (this.pending_clear) {
			var clear_ok = wv2_delete_all_cookies_sync(this.cookie_host);
			this.pending_clear = false;
			if (this.active_replace != null) {
				this.active_replace.clear_ok = clear_ok;
				this.active_replace.clear_done = true;
				if (!clear_ok) {
					this.fail_pending_cookies();
					this.active_replace.ok = false;
					this.active_replace.done = true;
					this.active_replace = null;
					return;
				}
			}
			if (!drain_all && this.pending_cookies.length > 0) {
				Idle.add(() => {
					this.apply_pending_cookies(false);
					return Source.REMOVE;
				});
				return;
			}
			if (this.active_replace != null && this.pending_cookies.length == 0) {
				this.refresh_replace_state(this.active_replace);
				return;
			}
		}

		if (drain_all) {
			for (var i = 0; i < this.pending_cookies.length; i++) {
				var pending = this.pending_cookies[i];
				if (pending.done) {
					continue;
				}
				this.add_one_pending(pending);
			}
			this.pending_cookies = new GenericArray<PendingCookie> ();
			if (this.active_replace != null) {
				this.refresh_replace_state(this.active_replace);
			}
			return;
		}

		PendingCookie? next = null;
		for (var i = 0; i < this.pending_cookies.length; i++) {
			var pending = this.pending_cookies[i];
			if (pending.done) {
				continue;
			}
			next = pending;
			break;
		}
		if (next == null) {
			this.pending_cookies = new GenericArray<PendingCookie> ();
			if (this.active_replace != null) {
				this.refresh_replace_state(this.active_replace);
			}
			return;
		}
		this.add_one_pending(next);
		this.prune_done_pending();
		if (this.active_replace != null) {
			this.refresh_replace_state(this.active_replace);
		}
		if (this.pending_cookies.length > 0) {
			Idle.add(() => {
				this.apply_pending_cookies(false);
				return Source.REMOVE;
			});
		}
	}

	private void fail_pending_cookies() {
		for (var i = 0; i < this.pending_cookies.length; i++) {
			var pending = this.pending_cookies[i];
			if (pending.done) {
				continue;
			}
			pending.ok = false;
			pending.done = true;
		}
		this.pending_cookies = new GenericArray<PendingCookie> ();
		this.pending_clear = false;
	}

	private static void on_apply_pending_cookies(void* user_data) {
		/* finish_setup — drain the full queue before first Navigate. */
		((NetworkSession) user_data).apply_pending_cookies(true);
	}

	/**
	 * WebKitGTK-shaped — set HTTP(S) proxy for this session.
	 *
	 * On Windows, Chromium honors ''--proxy-server'' / ''--no-proxy-server'' only at
	 * WebView2 environment create (process-wide shared env). Call before the first
	 * WebView attaches. Late calls warn once and are stored for a future recreate;
	 * they do not retarget a live environment. All HTTP(S) from that env (main
	 * frame, subresources, XHR) use the latch — a local forwarding proxy can route
	 * by request host.
	 */
	public void set_proxy_settings(
		NetworkProxyMode mode,
		NetworkProxySettings? settings
	) {
		this.proxy_mode = mode;
		this.proxy_settings = (mode == NetworkProxyMode.CUSTOM) ? settings : null;

		string? uri = null;
		if (mode == NetworkProxyMode.CUSTOM) {
			if (settings == null) {
				warning("WebView2Gtk: set_proxy_settings CUSTOM requires NetworkProxySettings");
				mode = NetworkProxyMode.DEFAULT;
				this.proxy_mode = mode;
			} else if (settings.http_proxy_uri != null && settings.http_proxy_uri.length > 0) {
				uri = settings.http_proxy_uri;
			} else {
				uri = settings.default_proxy_uri;
			}
		}

		if (wv2_host_environment_created() && !this.proxy_late_warned) {
			this.proxy_late_warned = true;
			warning(
				"WebView2Gtk: set_proxy_settings after env create — stored only; restart required for Chromium proxy flags"
			);
		}

		wv2_host_set_proxy_settings((int) mode, uri);
	}

	public void set_tls_errors_policy(TLSErrorsPolicy policy) {
	}

	/** Wire this session's download callbacks onto a WebView host. */
	internal void bind_download_host(void* host) {
		if (host == null) {
			return;
		}
		this.cookie_host = host;
		wv2_host_set_cookie_apply(host, NetworkSession.on_apply_pending_cookies, this);
		wv2_host_set_download_handlers(host, NetworkSession.on_host_started,
			NetworkSession.on_host_progress, NetworkSession.on_host_finished,
			NetworkSession.on_host_failed, null);
		/* Host may already be ready (rebind); drain if so. */
		this.apply_pending_cookies(true);
	}

	internal void unbind_download_host(void* host) {
		if (host == null) {
			return;
		}
		wv2_host_set_cookie_apply(host, null, null);
		wv2_host_set_download_handlers(host, null, null, null, null, null);
		if (this.cookie_host == host) {
			this.fail_pending_cookies();
			if (this.active_replace != null && !this.active_replace.done) {
				this.active_replace.ok = false;
				this.active_replace.done = true;
				this.active_replace = null;
			}
			this.cookie_host = null;
		}
	}

	internal void register_download(Download download, int host_id) {
		this.downloads.add(download);
	}

	internal void unregister_download(int host_id) {
		for (var i = 0; i < this.downloads.length; i++) {
			if (this.downloads[i].host_id == host_id) {
				this.downloads.remove_index(i);
				return;
			}
		}
	}

	internal Download? lookup_download(int host_id) {
		for (var i = 0; i < this.downloads.length; i++) {
			if (this.downloads[i].host_id == host_id) {
				return this.downloads[i];
			}
		}
		return null;
	}

	internal void emit_download_started(Download download) {
		this.download_started(download);
		download.schedule_decide_destination();
	}

	private static void on_host_started(
		int id,
		string uri,
		string suggested_filename,
		string mime_type,
		int64 content_length,
		void* user_data
	) {
		Idle.add(() => {
			var session = NetworkSession.active_session;
			if (session == null) {
				wv2_host_download_cancel(id);
				return false;
			}
			var dl = new Download(session, id, uri, suggested_filename, mime_type, content_length);
			session.register_download(dl, id);
			session.emit_download_started(dl);
			return false;
		});
	}

	private static void on_host_progress(int id, uint64 received, void* user_data) {
		Idle.add(() => {
			var session = NetworkSession.active_session;
			if (session == null) {
				return false;
			}
			var dl = session.lookup_download(id);
			if (dl != null) {
				dl.on_progress(received);
			}
			return false;
		});
	}

	private static void on_host_finished(int id, void* user_data) {
		Idle.add(() => {
			var session = NetworkSession.active_session;
			if (session == null) {
				return false;
			}
			var dl = session.lookup_download(id);
			if (dl != null) {
				dl.on_finished();
			}
			return false;
		});
	}

	private static void on_host_failed(int id, string message, void* user_data) {
		Idle.add(() => {
			var session = NetworkSession.active_session;
			if (session == null) {
				return false;
			}
			var dl = session.lookup_download(id);
			if (dl != null) {
				dl.emit_failed(new NetworkError.FAILED("%s", message));
			}
			return false;
		});
	}
}

}
