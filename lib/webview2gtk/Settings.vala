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
}

}
