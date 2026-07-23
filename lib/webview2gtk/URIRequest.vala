namespace WebView2Gtk {

/**
 * Minimal WebKit URIRequest stand-in (uri only — enough for OLLMchat).
 */
public class URIRequest : Object {
	public string uri { get; construct; }

	public URIRequest (string uri) {
		Object (uri: uri);
	}
}

}
