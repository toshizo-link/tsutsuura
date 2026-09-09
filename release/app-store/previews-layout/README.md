# Japanese App Store previews

These four layouts put the approved promotional copy above the **unchanged actual app screenshots**. The art is rendered from editable HTML/CSS; no screenshot pixels, interface text, controls, or proportions are redrawn.

- Canvas: 1320 × 2868 px, opaque RGB PNG.
- App font: the same `Kaisotai-Next-UP-B.otf` bundled with the iOS app.
- Brand: charcoal `#2B2B2B`, 8 px square dots at 64 px intervals, cyan `#2FADD7`, cyan shadow `#1D5D73`, pale paper `#D7F0F7`.
- Headline: 96 px, two lines, cyan emphasis on the second line.
- Screenshot: complete source image at 950 px width, original 1320:2868 aspect ratio, no crop. Square beveled frame.
- Copy and source hashes: `../preview-art-direction.json`.

## View and edit

From the repository root:

```sh
python3 -m http.server 13714 --bind 127.0.0.1
```

Open `http://127.0.0.1:13714/release/app-store/previews-layout/` for the responsive gallery. Append `?page=1`, `?page=2`, `?page=3`, or `?page=4` to render one exact-sized page. Edit `styles.css` for visual styling and `../preview-art-direction.json` for copy. `layout.js` creates the same layout for each page and waits for the local font and source PNGs.

## Reproduce the export

```sh
release/app-store/previews-layout/export.sh
```

The script uses a separate local-only Playwright CLI session and a temporary loopback HTTP server. It never attaches to the user's Chrome, reads a browser profile, or accesses App Store Connect. Set `PREVIEW_PLAYWRIGHT_CLI` to the local Playwright CLI wrapper path on a different machine. Node.js/npm, Python 3 (HTTP serving only), and the Playwright CLI browser must be available.

Captures are made in `output/playwright/tsutsuura-previews/` and copied to `exports/`. `verify.mjs` verifies all four original source SHA-256 hashes, output dimensions, PNG RGB color type, and writes `exports/manifest.json`.

`exports/gallery.png` is a 1600 × 1000 contact sheet for visual review. Only the four `exports/store-*.png` files are App Store uploads.
