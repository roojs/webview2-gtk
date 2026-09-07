namespace WebView2Gtk {

public class WebViewSettings : Object {
	public string user_agent { get; set; default = ""; }
	public HardwareAccelerationPolicy hardware_acceleration_policy {
		get;
		set;
		default = HardwareAccelerationPolicy.ON_DEMAND;
	}
	public bool enable_javascript { get; set; default = true; }
	public bool enable_developer_extras { get; set; default = false; }
	/** WebKitGTK-shaped — camera/mic media stream APIs. */
	public bool enable_media_stream { get; set; default = true; }
	/** WebKitGTK-shaped — WebRTC. */
	public bool enable_webrtc { get; set; default = true; }
	/** WebKitGTK-shaped — require a user gesture before media playback. */
	public bool media_playback_requires_user_gesture { get; set; default = false; }
	/**
	 * WebKitGTK-shaped — control navigator.webdriver visibility.
	 * DISABLED merges `--disable-blink-features=AutomationControlled` before
	 * WebView2 environment create (process-wide).
	 */
	public NavigatorWebDriverActivePolicy navigator_webdriver_active_policy {
		get;
		set;
		default = NavigatorWebDriverActivePolicy.AUTO;
	}
}

/** WebKitGTK-shaped free function twin of Settings.set_navigator_webdriver_active_policy. */
public void set_navigator_webdriver_active_policy(
	WebViewSettings settings,
	NavigatorWebDriverActivePolicy policy
) {
	settings.navigator_webdriver_active_policy = policy;
}

/** WebKitGTK-shaped free function twin of Settings.get_navigator_webdriver_active_policy. */
public NavigatorWebDriverActivePolicy get_navigator_webdriver_active_policy(
	WebViewSettings settings
) {
	return settings.navigator_webdriver_active_policy;
}

}
