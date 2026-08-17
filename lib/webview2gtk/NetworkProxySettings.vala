namespace WebView2Gtk {

public class NetworkProxySettings : Object {
	public string default_proxy_uri;
	public string? http_proxy_uri;

	public NetworkProxySettings(string default_proxy_uri, string? http_proxy_uri = null) {
		this.default_proxy_uri = default_proxy_uri;
		this.http_proxy_uri = http_proxy_uri;
	}
}

}
