# Code documentation (Valadoc markup)

Written for **AI agents** — **mandatory** when an agent adds or changes docblocks. Human contributors may treat this as a helpful guide.

This project uses [Vala’s comment markup](https://valadoc.org/markup.htm). Generated HTML is built with Valadoc (see `docs/meson.build`) and published via `.github/workflows/deploy-docs.yml`.

Gold-standard style for major APIs: **OLLMchat** [`docs/code-documentation.md`](https://github.com/roojs/OLLMchat/blob/main/docs/code-documentation.md) (overview + `== Usage Examples ==` with **block** `{{{ … }}}` samples). Match that depth for `WebView2Gtk.WebView` and `Win32Atspi`.

## Documentation comment structure

```vala
/**
 * Brief description (one line).
 *
 * Optional longer description: paragraphs separated by a blank comment line.
 *
 * @param name description of parameter
 * @return description of return value
 * @throws TypeName when this error is thrown
 */
```

- **Brief**: First line(s) before a blank line; keep short (one sentence).
- **Taglets**: At the end (`@param`, `@return`, `@throws`).
- After every `== … ==` / `=== … ===` headline, put a **blank** documentation line before the next paragraph.
- **Not supported:** `{@code …}` (valadoc error).

## Literals: block `{{{ }}}` vs inline `''…''`

| Form | Use | Do not |
|------|-----|--------|
| Multi-line `{{{ … }}}` | Block code samples only (`== Usage Examples ==`) | Inline in prose |
| `{{{ token }}}` in a sentence | ❌ | Becomes a `<pre>` block mid-paragraph |
| `''Name''` or `{@link Type}` | Inline type / flag / short literal | — |

```vala
/**
 * Good — block sample:
 *
 * {{{
 * var web = new WebView2Gtk.WebView ();
 * web.load_uri ("https://example.com/");
 * }}}
 *
 * Good — inline: ''WebView'', {@link Win32Atspi.Accessible}.
 *
 * Bad — inline triple braces: {{{WebView}}} in running text.
 */
```

## Class and namespace overviews

For public namespaces and entry-point classes:

1. **Brief** — one title sentence.
2. **Overview** — what it is for and related types (orientation, not method-by-method).
3. **`== Usage Examples ==`** with `=== … ===` subsections and real multi-line `{{{ … }}}` samples.
4. Optional **`== Best Practices ==`**.

## Package wiki (`docs/valadoc-wiki/index.valadoc`)

Same rules as OLLMchat:

1. **No** inline `{{{…}}}` — use `''…''` for emphasis.
2. Use **full GitHub Pages URLs** in `[[url|label]]` links so they resolve in the
   summary body, e.g.

```
''[[https://roojs.github.io/webview2-gtk/webview2gtk/WebView2Gtk.WebView.html|WebView2Gtk.WebView]]''
```

3. Valadoc emits those as external links (`target="_blank"`). After valadoc runs,
   **`docs/fix-valadoc-index-links.sh`** (invoked by `docs/run-valadoc.sh`)
   rewrites matching `https://roojs.github.io/webview2-gtk/webview2gtk/…`
   hrefs in `index.htm` to same-directory relative paths (no new tab).
4. Keep wiki links aligned with symbols that exist in `docs/meson.build`.

Do **not** hand-write relative `href`s in the wiki — the post-process expects the
full Pages URL form.

## Keeping Valadoc in sync

When adding or removing public `.vala` under `lib/webview2gtk/`, update the `input: files(...)` list in `docs/meson.build` (include `*Bindings.vala` when public types reference those externs).

## Local build

```bash
meson setup build-docs -Ddocs=true
ninja -C build-docs docs/valadoc
# open build-docs/valadoc/webview2gtk/index.htm
```

Linux is enough (docs-only configure; the library itself remains Windows-only).
