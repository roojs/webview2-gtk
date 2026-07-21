#!/bin/sh
# Valadoc adds target="_blank" to any URL with a scheme. The package overview wiki
# uses full GitHub Pages URLs so links resolve in the summary body; this pass
# rewrites those internal links to relative hrefs (no new tab).
#
# Valadoc copies the wiki onto both:
#   valadoc/index.html              (site root — Pages entry)
#   valadoc/webview2gtk/index.htm   (package page)
# so both must be rewritten (with different relative prefixes).
set -e
VALADOC_DIR="$1"
if [ -z "$VALADOC_DIR" ] || [ ! -d "$VALADOC_DIR" ]; then
	echo "fix-valadoc-index-links: need valadoc output directory" >&2
	exit 1
fi

PKG_INDEX="$VALADOC_DIR/webview2gtk/index.htm"
ROOT_INDEX="$VALADOC_DIR/index.html"

if [ ! -f "$PKG_INDEX" ]; then
	echo "fix-valadoc-index-links: missing $PKG_INDEX" >&2
	exit 1
fi
if [ ! -f "$ROOT_INDEX" ]; then
	echo "fix-valadoc-index-links: missing $ROOT_INDEX" >&2
	exit 1
fi

# From package dir: Foo.html
perl -pi -e \
	's/href="https:\/\/roojs\.github\.io\/webview2-gtk\/webview2gtk\/([^"]+)" target="_blank"/href="$1"/g' \
	"$PKG_INDEX"

# From site root: webview2gtk/Foo.html
perl -pi -e \
	's/href="https:\/\/roojs\.github\.io\/webview2-gtk\/webview2gtk\/([^"]+)" target="_blank"/href="webview2gtk\/$1"/g' \
	"$ROOT_INDEX"
