/* Map GTK widget bounds to Win32 client coordinates for WebView2. */

#include "webview2gtk-gdk-win32.h"

#include <gtk/gtk.h>
#include <math.h>

gboolean
webview2gtk_widget_bounds (GtkWidget *widget, GdkRectangle *bounds)
{
	GtkWidget *root;
	GtkNative *native;
	GdkSurface *surface;
	graphene_rect_t layout;
	double surf_x;
	double surf_y;
	int scale;
	int width;
	int height;

	g_return_val_if_fail (GTK_IS_WIDGET (widget), FALSE);
	g_return_val_if_fail (bounds != NULL, FALSE);

	root = gtk_widget_get_root (widget);
	if (root == NULL || !GTK_IS_NATIVE (root)) {
		return FALSE;
	}

	native = GTK_NATIVE (root);

	if (!gtk_widget_compute_bounds (widget, root, &layout)) {
		return FALSE;
	}

	/* GtkNative layout coords -> GdkSurface / HWND client coords (shadow inset, etc.). */
	gtk_native_get_surface_transform (native, &surf_x, &surf_y);

	surface = gtk_native_get_surface (native);
	scale = surface != NULL ? gdk_surface_get_scale_factor (surface) : 1;

	width = (int) round (layout.size.width * (double) scale);
	height = (int) round (layout.size.height * (double) scale);
	if (width <= 0 || height <= 0) {
		return FALSE;
	}

	bounds->x = (int) round ((layout.origin.x + surf_x) * (double) scale);
	bounds->y = (int) round ((layout.origin.y + surf_y) * (double) scale);
	bounds->width = width;
	bounds->height = height;
	return TRUE;
}
