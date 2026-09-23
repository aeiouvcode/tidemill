# Handoff

## Resume here

Next cycle: P5 water foam - add a foam/shoreline band where town cells meet water (water vertex colors or ring geometry at exposed cell edges), then full P1 wall-edge ink outlines. Working file is index.html at repo root. Loop per cycle: headless chrome renders at 390x844 + 1280x800, side-by-side vs the reference, web-edit deploy via config-c, hash-verify served bytes, then port the same edits into the File project (checkout file-01M326APDF9KDM14DSBAG1NCCD, edit src/tidemill.ts, build, exercise preview, publish) and report the File URL.

## Blocked

- Nothing.

## Failed approaches

| Approach | Why it failed | Date |
| --- | --- | --- |
| Headless chrome screenshot of the Instinct File preview URL | Shell sits on "Loading..." / "This is taking longer than expected." - the File shell needs the cloud browser | 2026-09-23 |
| sRGB hex values pushed raw into vertex colors under ACES tonemapping | Unlit geometry double-brightened to pastel; ink trim/doors rendered pale mauve until sRGB->linear conversion in rgb() | 2026-09-23 |

## Discoveries

- GitHub's CodeMirror .cm-content textContent only holds the virtualized viewport. Verify editor content via the EditorView state (walk element props for .view.state.doc), not the DOM.
- form-input mode=value replaces a full CodeMirror document correctly at 24KB+.
- The File's sandboxed iframe blocks localStorage (opaque origin): town saves don't persist in the File surface; they work on Pages.
- Live-deploy rule that works: poll the Pages URL until the served file hash matches the local file, then load it once in a browser.
