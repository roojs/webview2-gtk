/* webview2gtk-cookie-ext.vapi — CookieManagerExt C-shaped get_all / replace.
 * Use: --pkg webview2gtk-cookie-ext (pulls webview2gtk-1 via .deps).
 */

namespace WebView2Gtk {
	[CCode(cheader_filename = "webview2gtk.h")]
	public class CookieManagerExt : GLib.Object {
		public static void get_all_cookies_async(CookieManager cookie_manager,
			GLib.Cancellable? cancellable, GLib.AsyncReadyCallback callback);

		public static GLib.List<Soup.Cookie> get_all_cookies_finish(CookieManager cookie_manager, GLib.AsyncResult result) throws GLib.Error;

		public static void replace_cookies_async(CookieManager cookie_manager, GLib.List<Soup.Cookie> cookies,
			GLib.Cancellable? cancellable, GLib.AsyncReadyCallback callback);

		public static bool replace_cookies_finish(CookieManager cookie_manager, GLib.AsyncResult result) throws GLib.Error;
	}
}
