# Bug — `PrintOperation` ignores page setup; variable fonts print as Type3

**Status:** ✅ page setup fixed in **0.6.6**. Roboto Flex stays Type3 (Skia).  
**Date:** 2026-09-28  
**Component:** `lib/webview2gtk/PrintOperation.vala` + `lib/host/win32-ui-webview2-print.c`  
**API parity:** WebKitGTK `WebKit.PrintOperation` (`set_page_setup`, `set_print_settings`, `print`)  
**Upstream:** WebView2 `ICoreWebView2_7::PrintToPdf` / `ICoreWebView2PrintSettings`. Skia PDF turns a variable font (or WOFF2 that still has an `fvar` table) into a PDF Type3 font. No `PrintSettings` flag changes that.

ℹ️ Plan emoji: 🔷 user req, 💩 LLM suggestion, ⏳ backlog, 🚫 veto.

A private app hit this. Full pages stay in that app’s tree. This file is the library repro only.

---

## Symptom

Caller sets an A4 `Gtk.PageSetup` (5 mm margins) and `Gtk.PrintSettings` scale 100, then `print()`.

The file is a real PDF (`%PDF-1.4`, Producer `Skia/PDF`). It is not a PNG. Two things are still wrong:

1. **Page box is US Letter.** `pdfinfo` shows about **612 × 792 pt**. A4 is **595.28 × 841.89 pt**. WebView2’s default paper is 8.5 × 11 in with 0.5 in margins. The caller’s page setup never arrives.
2. **Variable webfont text looks like a pixel image** in the Windows PDF viewer. `pdffonts` shows those faces as **Type3**. A static face in the same kind of print (Arial, or another installed TrueType) is **CID TrueType** and stays sharp. Type3 glyphs here are PDF path drawings (`d0`/`d1`, `m`/`l`/`c`, `f`), not embedded bitmaps. Viewers still rasterize Type3, so the page looks blocky and “not a PDF” even when `pdftotext` can read the words.

---

## Cause

`set_page_setup()` is empty. `set_print_settings()` keeps the object only to read the output path. `PrintToPdf` is called with settings that set **`ShouldPrintBackgrounds = TRUE`** and nothing else (`create_print_settings_with_backgrounds` in `win32-ui-webview2-print.c`).

```vala
public void set_page_setup(Gtk.PageSetup page_setup) {
}
```

Scale, paper size, orientation, and margins are dropped.

Type3 is separate and is **not** fixed by page size. Skia’s PDF backend cannot embed a variable font (the `fvar` table survives WOFF2 decode) as TrueType, so it emits Type3. `ICoreWebView2PrintSettings` has no switch for that. `Page.printToPDF` over DevTools uses the same Skia backend.

---

## What to implement

🔷 Forward the WebKit-shaped page setup and scale into `ICoreWebView2PrintSettings` before `PrintToPdf`. Keep `ShouldPrintBackgrounds = TRUE`.

| Caller | WebView2 (`ICoreWebView2PrintSettings`) |
|---|---|
| `PageSetup.get_paper_width/height(Gtk.Unit.INCH)` | `put_PageWidth` / `put_PageHeight` (inches; default 8.5 × 11) |
| `get_top/bottom/left/right_margin(Gtk.Unit.INCH)` | `put_MarginTop` / `Bottom` / `Left` / `Right` (inches; default 0.5) |
| `PageSetup` orientation | `put_Orientation` (`PORTRAIT` / `LANDSCAPE`) |
| `PrintSettings.get_scale()` (percent, 100 = 100%) | `put_ScaleFactor` (0.1–2.0, 1.0 = 100%). Clamp into that range. |
| (already) | `put_ShouldPrintBackgrounds(TRUE)` |

Store the `PageSetup` passed to `set_page_setup()`. Extend `vala_webview2_host_print_to_pdf_sync` so those numbers reach `apply` on the settings object created today. If width or height is ≤ 0, leave WebView2’s paper default (no page setup was set).

🚫 Do not inject CSS or rewrite `font-family` inside the library.  
🚫 Do not switch the print path to DevTools `Page.printToPDF` to “get TrueType”. Same Skia rule.  
💩 If, after the settings are forwarded, Roboto Flex in the repro is still Type3: record that in this bug as a WebView2/Skia limit and stop. Callers that need sharp text in the Windows viewer have to use a static face. There is nothing else in this API to set.

---

## Repro

Smoke: `examples/hello --smoke-print` (`AGENT_WIN_HOST=snappr-win ./scripts/agent-remote-build.sh hello-print`).

**Reproduced** on snappr-win (2026-09-28), `webview2gtk-hello.exe --smoke-print`. Caller asked for A4. `pdfinfo` / `pdffonts` / `pdftotext`:

```text
Page size:       612 x 792 pts (letter)
Producer:        Skia/PDF m153
AAAAAA+ArialMT                       CID TrueType
BAAAAA+Roboto-Flex-18pt              Type 3
CAAAAA+Roboto-Flex-18pt-Bold         Type 3
```

`pdftotext` returns both sentences. Roboto Flex was `font-ready` before `PrintToPdf`.

**After forwarding page setup** (same smoke, 2026-09-28 16:06):

```text
Page size:       594.96 x 841.92 pts (A4)
AAAAAA+ArialMT                       CID TrueType
BAAAAA+Roboto-Flex-18pt              Type 3
CAAAAA+Roboto-Flex-18pt-Bold         Type 3
```

First word bbox is about **x=32.2, y=32.8 pt**. That is the 5 mm margin (14.2 pt) plus the page’s 24 px body margin (18 pt). The old 0.5 in default would have started near 54 pt. `pdftotext` still returns both sentences. Scale sent is 1.0. `ShouldPrintBackgrounds` stays true.

`ICoreWebView2PrintSettings` and `ICoreWebView2PrintSettings2` have no font property. Roboto Flex stays Type3 after every print setting that exists is applied. Callers that need sharp text use a static face. `examples/print` on the same run is A4 (594.96 × 841.92 pt) and CID TrueType for `Arial-BoldMT`, `ArialMT`, and `SegoeUI`.

One window, `load_html`, then print. Needs a network fetch of the Roboto Flex stylesheet (variable font). Output path is whatever you pass as `output-uri`.

```vala
var page_setup = new Gtk.PageSetup();
page_setup.set_orientation(Gtk.PageOrientation.PORTRAIT);
page_setup.set_paper_size(new Gtk.PaperSize(Gtk.PAPER_NAME_A4));
page_setup.set_top_margin(5.0, Gtk.Unit.MM);
page_setup.set_bottom_margin(5.0, Gtk.Unit.MM);
page_setup.set_left_margin(5.0, Gtk.Unit.MM);
page_setup.set_right_margin(5.0, Gtk.Unit.MM);

var settings = new Gtk.PrintSettings();
settings.set_printer("Print to File");
settings.set("output-file-format", "pdf");
settings.set("output-uri", output_path);
settings.set_scale(100.0);
settings.set_print_pages(Gtk.PrintPages.ALL);

var op = new WebView2Gtk.PrintOperation(view);
op.set_page_setup(page_setup);
op.set_print_settings(settings);
op.print();
```

HTML (base `https://example.test/`):

```html
<!DOCTYPE html>
<html><head>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Roboto+Flex:opsz,wght@8..144,400;8..144,700&amp;display=swap">
<style>
  body { margin: 24px; }
  .static { font-family: Arial, sans-serif; font-size: 18px; }
  .variable { font-family: "Roboto Flex", sans-serif; font-size: 18px; font-weight: 400; }
  .variable b { font-weight: 700; }
</style>
</head><body>
<p class="static">Static Arial: The quick brown fox jumps over the lazy dog.</p>
<p class="variable">Variable Roboto Flex: The quick brown fox jumps over the lazy dog. <b>Bold weight.</b></p>
</body></html>
```

Wait until `load_changed` is `FINISHED`, then another couple of seconds so the webfont arrives, then print.

Check:

```text
pdfinfo out.pdf          # Page size
pdffonts out.pdf         # Type3 vs CID TrueType
pdftotext -f 1 -l 1 out.pdf -
```

**Today:** page size Letter; Arial CID TrueType; Roboto Flex Type3; both sentences extract as text. The Windows viewer paints the Type3 line like a pixel image.

---

## Acceptance

1. Same repro: `pdfinfo` page size is **A4** (about 595 × 842 pt), not 612 × 792.
2. Margins follow the 5 mm setup (not the 0.5 in default).
3. Scale 100 stays `ScaleFactor` 1.0. `ShouldPrintBackgrounds` stays true.
4. Arial line is still CID TrueType. `pdftotext` still returns both sentences.
5. Roboto Flex: if it is still Type3, say so in this bug and do not add a font inject. If a WebView2 setting actually embeds it as TrueType, use that setting and show `pdffonts`.
