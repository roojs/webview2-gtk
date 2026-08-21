namespace WebView2Gtk {

public enum SnapshotRegion {
	VISIBLE,
	FULL_DOCUMENT
}

public enum SnapshotOptions {
	NONE
}

public enum NetworkProxyMode {
	DEFAULT,
	CUSTOM,
	NONE
}

public enum TLSErrorsPolicy {
	IGNORE,
	FAIL
}

public enum HardwareAccelerationPolicy {
	ON_DEMAND,
	ALWAYS,
	NEVER
}

public enum CookieAcceptPolicy {
	ALWAYS,
	NEVER,
	NO_THIRD_PARTY
}

public enum CookiePersistentStorage {
	TEXT,
	SQLITE
}

/** WebKitGTK-shaped — media autoplay policy for {@link WebsitePolicies}. */
public enum AutoplayPolicy {
	ALLOW,
	ALLOW_WITHOUT_SOUND,
	DENY
}

/** WebKitGTK-shaped subset — used by {@link WebView.load_failed}. */
public errordomain NetworkError {
	FAILED,
	TRANSPORT,
	UNKNOWN_PROTOCOL,
	CANCELLED,
	FILE_DOES_NOT_EXIST;
}

}
