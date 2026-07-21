# Code documentation (Valadoc markup)

Written for **AI agents** — **mandatory** when an agent adds or changes docblocks. Human contributors may treat this as a helpful guide.

This project uses [Vala’s comment markup](https://valadoc.org/markup.htm). Generated HTML is built with Valadoc (see `docs/meson.build`) and published via `.github/workflows/deploy-docs.yml`.

Gold-standard style for major APIs: **OLLMchat** `docs/code-documentation.md` (overview + `== Usage Examples ==` with `{{{ … }}}` samples). Match that depth for `WebView2Gtk.WebView` and `Win32Atspi`.

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
- Use `{{{ }}}` for literals; **not** `{@code …}` (valadoc error).
- After every `== … ==` / `=== … ===` headline, put a **blank** documentation line before the next paragraph.

## Class and namespace overviews

For public namespaces and entry-point classes:

1. **Brief** — one title sentence.
2. **Overview** — what it is for and related types (orientation, not method-by-method).
3. **`== Usage Examples ==`** with `=== … ===` subsections and real `{{{ … }}}` samples.
4. Optional **`== Best Practices ==`**.

## Keeping Valadoc in sync

When adding or removing public `.vala` under `lib/webview2gtk/`, update the `input: files(...)` list in `docs/meson.build` (include `*Bindings.vala` when public types reference those externs).

## Local build

```bash
meson setup build-docs -Ddocs=true
ninja -C build-docs docs/valadoc
# open build-docs/valadoc/webview2gtk/index.htm
```

Linux is enough (docs-only configure; the library itself remains Windows-only).
