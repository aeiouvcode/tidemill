# Handoff

## Resume here

Stand up the Godot 4 (Compatibility/WebGL2) branch. First crib the pipeline: inspect the kin-living-pond repo's godot-prototype branch (project layout, export presets, how the web build is produced and where artifacts live, its state files). Then create branch godot-prototype in aeiouvcode/tidemill, commit project source + state files on day one, and start the scene port: water shader with depth-based foam first, then lighting, then the town geometry grammar. Three.js main stays untouched; the Godot build deploys to Pages ONLY on the main agent's go. After the branch exists, return to track A (three.js): full P1 wall-edge ink outlines. Deploy loop for track A: headless chrome renders at 390x844 + 1280x800, side-by-side vs reference, web-edit deploy via config-c, hash-verify served bytes, port edits into the File project (checkout file-01M326APDF9KDM14DSBAG1NCCD, edit src/tidemill.ts, build, exercise preview, publish), report the File URL.

## Blocked

- Nothing.

## Failed approaches

| Approach | Why it failed | Date |
| --- | --- | --- |
| Uniform wide foam bands along the coastline | Read as a solid glass apron around the town, not foam; fixed with per-edge 4-segment scallops with noise-varied widths and skipped outer segments | 2026-09-23 |
| Headless chrome screenshot of the Instinct File preview URL | Shell sits on "Loading..." / "This is taking longer than expected." - the File shell needs the cloud browser | 2026-09-23 |
| sRGB hex values pushed raw into vertex colors under ACES tonemapping | Unlit geometry double-brightened to pastel; ink trim/doors rendered pale mauve until sRGB->linear conversion in rgb() | 2026-09-23 |

## Discoveries

- GitHub's CodeMirror .cm-content textContent only holds the virtualized viewport. Verify editor content via the EditorView state (walk element props for .view.state.doc), not the DOM.
- form-input mode=value replaces a full CodeMirror document correctly at 24KB+.
- The File's sandboxed iframe blocks localStorage (opaque origin): town saves don't persist in the File surface; they work on Pages.
- Live-deploy rule that works: poll the Pages URL until the served file hash matches the local file, then load it once in a browser.
- Water waves are vertex-displaced each frame (PlaneGeometry 56x56); foam sits at fixed y=.19 above the wave crest with a global opacity breath (matFoam), which reads as a living wash without per-vertex foam animation.
