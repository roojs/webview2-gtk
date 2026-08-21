# Releasing

This repo's release flow is **tag-driven**.

## What `scripts/release.sh` does

- reads the first `CHANGELOG.md` section and expects `## [X.Y.Z] - Unreleased`
- prints the notes that will become the GitHub Release body
- refuses to run on a dirty working tree
- refuses to reuse an existing local or remote tag unless you pass `--retry`
- creates annotated tag `vX.Y.Z`
- pushes the current branch and the tag to `origin`

`--retry` deletes the existing `vX.Y.Z` tag locally and on `origin`, then retags `HEAD`. Use that only after a failed release CI run.

## GitHub Actions

Pushing `vX.Y.Z` triggers [`.github/workflows/release.yml`](../.github/workflows/release.yml), which:

- builds `webview2gtk-setup.exe`
- builds the MSYS2 package `mingw-w64-ucrt-x86_64-webview2gtk-*.pkg.tar.zst`
- signs the package on tag releases
- renders `release-notes.md` from the matching `CHANGELOG.md` section
- publishes the artifacts and the changelog text as the GitHub Release body

## Changelog format

Before releasing, the first section in `CHANGELOG.md` must look like:

```md
## [0.4.3] - Unreleased
```

After the tag lands, convert that section to a dated entry and add a fresh `## [Unreleased]` section for the next cycle.
