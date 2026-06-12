/* Hand stub until Foundation.json is vendored (POINT, RECT, …). */

namespace Win32.Foundation {
	[CCode (cname = "POINT")]
	public struct Point {
		public int x;
		public int y;
	}

	[CCode (cname = "RECT")]
	public struct Rect {
		public int left;
		public int top;
		public int right;
		public int bottom;
	}

	[CCode (cname = "SIZE")]
	public struct Size {
		public int cx;
		public int cy;
	}
}
