namespace WebView2Gtk {

/**
 * WebKitGTK-shaped URI response metadata.
 *
 * Main-document emissions populate {@link uri}, {@link status_code}, and {@link http_headers}.
 */
public sealed class URIResponse : Object {
	public string uri { get; construct; }
	public uint status_code { get; construct; }
	public Soup.MessageHeaders http_headers { get; construct; }

	public URIResponse(string uri, uint status_code, Soup.MessageHeaders http_headers) {
		Object(uri: uri, status_code: status_code, http_headers: http_headers);
	}

	public unowned string get_uri() {
		return this.uri;
	}

	public uint get_status_code() {
		return this.status_code;
	}

	public unowned Soup.MessageHeaders get_http_headers() {
		return this.http_headers;
	}
}

}
