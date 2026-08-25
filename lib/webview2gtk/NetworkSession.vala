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
	private void* cookie_host = null;

	public signal void download_started(Download download);

	public NetworkSession() {
		this.cookie_manager = new CookieManager(this);
		NetworkSession.active_session = this;
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
		this.apply_pending_cookies();
		return pending;
	}

	internal void apply_pending_cookies() {
		if (this.cookie_host == null || !wv2_host_is_ready(this.cookie_host)) {
			return;
		}
		for (var i = 0; i < this.pending_cookies.length; i++) {
			var pending = this.pending_cookies[i];
			if (pending.done) {
				continue;
			}
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
		}
		this.pending_cookies = new GenericArray<PendingCookie> ();
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
	}

	private static void on_apply_pending_cookies(void* user_data) {
		((NetworkSession) user_data).apply_pending_cookies();
	}

	public void set_proxy_settings(
		NetworkProxyMode mode,
		NetworkProxySettings? settings
	) {
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
		this.apply_pending_cookies();
	}

	internal void unbind_download_host(void* host) {
		if (host == null) {
			return;
		}
		wv2_host_set_cookie_apply(host, null, null);
		wv2_host_set_download_handlers(host, null, null, null, null, null);
		if (this.cookie_host == host) {
			this.fail_pending_cookies();
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
