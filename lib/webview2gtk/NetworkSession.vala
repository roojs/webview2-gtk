namespace WebView2Gtk {

/**
 * WebKitGTK-shaped network session — cookies + download_started.
 */
public class NetworkSession : Object {
	private static bool handlers_installed = false;
	private static weak NetworkSession? active_session = null;

	private CookieManager cookie_manager = new CookieManager();
	private GenericArray<Download> downloads = new GenericArray<Download> ();

	public signal void download_started(Download download);

	public NetworkSession() {
		NetworkSession.active_session = this;
		NetworkSession.ensure_handlers();
	}

	public CookieManager get_cookie_manager() {
		return this.cookie_manager;
	}

	public void set_proxy_settings(
		NetworkProxyMode mode,
		NetworkProxySettings? settings
	) {
	}

	public void set_tls_errors_policy(TLSErrorsPolicy policy) {
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

	private static void ensure_handlers() {
		if (NetworkSession.handlers_installed) {
			return;
		}
		NetworkSession.handlers_installed = true;
		wv2_host_set_download_handlers(NetworkSession.on_host_started, NetworkSession.on_host_progress,
			NetworkSession.on_host_finished, NetworkSession.on_host_failed, null);
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
