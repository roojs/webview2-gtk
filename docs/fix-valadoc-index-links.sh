#!/bin/sh
# Valadoc adds target="_blank" to any URL with a scheme. Rewrite package overview
# GitHub Pages links to same-directory relative hrefs (no new tab).
set -e
INDEX="$1"
if [ ! -f "$INDEX" ]; then
	echo "fix-valadoc-index-links: missing $INDEX" >&2
	exit 1
fi
perl -pi -e \
	's/href="https:\/\/roojs\.github\.io\/webview2-gtk\/webview2gtk\/([^"]+)" target="_blank"/href="$1"/g' \
	"$INDEX"
