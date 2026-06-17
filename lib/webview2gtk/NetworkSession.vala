namespace WebView2Gtk {

public class NetworkSession : Object {
	private CookieManager _cookie_manager = new CookieManager ();

	public CookieManager get_cookie_manager () {
		return _cookie_manager;
	}

	public void set_proxy_settings (
		NetworkProxyMode mode,
		NetworkProxySettings? settings
	) {
	}

	public void set_tls_errors_policy (TLSErrorsPolicy policy) {
	}
}

}
