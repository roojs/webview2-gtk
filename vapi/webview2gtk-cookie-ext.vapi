/* webview2gtk-cookie-ext.vapi — CookieManagerExt static twins of get_all / replace.
 * Use: --pkg webview2gtk-cookie-ext (pulls webview2gtk-1 via .deps).
 */

namespace WebView2Gtk {
	[CCode(cheader_filename = "webview2gtk.h")]
	public class CookieManagerExt : GLib.Object {
		public static async GLib.List<Soup.Cookie> get_all_cookies(CookieManager cookie_manager, GLib.Cancellable? cancellable = null) 
			throws GLib.Error;
		public static async bool replace_cookies(CookieManager cookie_manager, GLib.List<Soup.Cookie> cookies, GLib.Cancellable? cancellable = null) 
			throws GLib.Error;
	}
}
