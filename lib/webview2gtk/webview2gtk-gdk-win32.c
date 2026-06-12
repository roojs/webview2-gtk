/* Map GTK widget bounds to Win32 client coordinates for WebView2. */

#include "webview2gtk-gdk-win32.h"

#include <gtk/gtk.h>
#include <math.h>

gboolean
webview2gtk_widget_bounds_xywh (GtkWidget *widget, int *x, int *y, int *width, int *height)
{
	GtkWidget *root;
	GtkNative *native;
	GdkSurface *surface;
	graphene_rect_t bounds;
	double surf_x;
	double surf_y;
	int scale;
	int w;
	int h;

	g_return_val_if_fail (GTK_IS_WIDGET (widget), FALSE);
	g_return_val_if_fail (x != NULL && y != NULL && width != NULL && height != NULL, FALSE);

	root = gtk_widget_get_root (widget);
	if (root == NULL || !GTK_IS_NATIVE (root)) {
		return FALSE;
	}

	native = GTK_NATIVE (root);

	if (!gtk_widget_compute_bounds (widget, root, &bounds)) {
		return FALSE;
	}

	/* GtkNative layout coords -> GdkSurface / HWND client coords (shadow inset, etc.). */
	gtk_native_get_surface_transform (native, &surf_x, &surf_y);

	surface = gtk_native_get_surface (native);
	scale = surface != NULL ? gdk_surface_get_scale_factor (surface) : 1;

	*x = (int) round ((bounds.origin.x + surf_x) * (double) scale);
	*y = (int) round ((bounds.origin.y + surf_y) * (double) scale);
	w = (int) round (bounds.size.width * (double) scale);
	h = (int) round (bounds.size.height * (double) scale);

	if (w <= 0 || h <= 0) {
		return FALSE;
	}

	*width = w;
	*height = h;
	return TRUE;
}
