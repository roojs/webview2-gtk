/* GTK 4 / Win32 helpers for embedding WebView2 in a GtkNative surface. */
#pragma once

#include <gtk/gtk.h>
#include <glib.h>

#define __GDKWIN32_H_INSIDE__
#include <gdk/win32/gdkwin32misc.h>
#undef __GDKWIN32_H_INSIDE__

G_BEGIN_DECLS

gboolean webview2gtk_widget_bounds_xywh (GtkWidget *widget, int *x, int *y, int *width, int *height);

G_END_DECLS
