namespace WebView2Gtk {

/**
 * Static twins of {@link CookieManager.get_all_cookies} /
 * {@link CookieManager.replace_cookies} for apps that share a sealed WebKit
 * CookieManager on Linux and call through a supplement type on both platforms.
 */
public class CookieManagerExt : Object {
	public static async GLib.List<Soup.Cookie> get_all_cookies(
		CookieManager cookie_manager,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		return yield cookie_manager.get_all_cookies(cancellable);
	}

	public static async bool replace_cookies(
		CookieManager cookie_manager,
		GLib.List<Soup.Cookie> cookies,
		GLib.Cancellable? cancellable = null
	) throws GLib.Error {
		return yield cookie_manager.replace_cookies(cookies, cancellable);
	}
}

}
