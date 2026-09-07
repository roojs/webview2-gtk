namespace WebView2Gtk {

/**
 * Static C-shaped twins of {@link CookieManager.get_all_cookies} /
 * {@link CookieManager.replace_cookies} (`*_async` / `*_finish`) for apps that
 * share a sealed WebKit CookieManager on Linux and call through a supplement
 * type on both platforms.
 */
public class CookieManagerExt : Object {
	public static void get_all_cookies_async(CookieManager cookie_manager, 
		GLib.Cancellable? cancellable, GLib.AsyncReadyCallback callback)
	{
		cookie_manager.get_all_cookies.begin(cancellable, callback);
	}

	public static GLib.List<Soup.Cookie> get_all_cookies_finish(CookieManager cookie_manager, GLib.AsyncResult result) throws
		GLib.Error
	{
		return cookie_manager.get_all_cookies.end(result);
	}

	public static void replace_cookies_async(CookieManager cookie_manager, GLib.List<Soup.Cookie> cookies, 
		GLib.Cancellable? cancellable, GLib.AsyncReadyCallback callback)
	{
		cookie_manager.replace_cookies.begin(cookies, cancellable, callback);
	}

	public static bool replace_cookies_finish(CookieManager cookie_manager, GLib.AsyncResult result) throws
		GLib.Error
	{
		return cookie_manager.replace_cookies.end(result);
	}
}

}
