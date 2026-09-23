# Handoff

## Resume here

Build the first web export and look at it. Need Godot 4.5.2 stable linux + the web_nothreads_release export template locally (download from godotengine releases; templates install to ~/.local/share/godot/export_templates/4.5.2.stable/ - only web_nothreads_* is needed, extract selectively from the tpz). Then: godot/build.sh, open export/index.html in the cloud browser, screenshot at 390x844, judge the foam honestly vs the three.js build, iterate the shader. Movie-maker frames for quick checks: xvfb-run godot --rendering-driver opengl3 --resolution 390x844 --write-movie /tmp/f.png --fixed-fps 30 --quit-after 90. After the water passes, port lighting (warm sun + ambient to taste), then the town grammar (grid cells, plinth/stilts, levels, arches, roofs with ink trim, windows, doors), then tap-to-build interaction and local save.

## Blocked

- Pages deploy: waiting on the main agent's go (branch-only until then).

## Failed approaches

| Approach | Why it failed | Date |
| --- | --- | --- |
| (kin pipeline lesson) Prototype kept only in scratch workspace | Lost twice in sandbox rebuilds - source lives on this branch from day one | 2026-09-22 |
| (kin pipeline lesson) Side-view layout for a living scene | Crowded and flat; top-down/orbit read better | 2026-09-22 |

## Discoveries

- Godot 4 Compatibility renderer DOES support hint_depth_texture, so depth-based shoreline foam works on WebGL2 - this is the engine-bound win over the single-file three.js setup.
- SDFGI/real-time GI is NOT available on the Compatibility renderer: warmth must come from baked lightmaps + tuned ambient + sun color.
- KIN pipeline: web export wasm is ~38 MB raw / ~9 MB gzip; boot 2.7-3.4 s once files are local; build.sh injects a strict CSP with per-script sha256 hashes; Godot's default shell can show raw engine errors on boot failure (custom shell is a known follow-up).
- QA frames without a browser: xvfb-run godot --rendering-driver opengl3 --write-movie --fixed-fps 30 --quit-after N.
