# Checkpoint

Completed atomic steps, newest last. Do not redo anything listed here.

| Date | Step | Evidence (commit, URL, screenshot) |
| --- | --- | --- |
| 2026-09-23 | Branch godot-prototype created from main (three.js build untouched on main) | branch listing |
| 2026-09-23 | Pipeline cribbed from kin-living-pond/godot-prototype: project.godot (GL Compatibility, 390x844), export_presets.cfg (Web, no threads), build.sh (headless export + hashed-script CSP), .gitignore | kin-living-pond godot-prototype branch |
| 2026-09-23 | Water-first scene committed: ocean plane with depth-based shoreline foam shader (hint_depth_texture), wave/sparkle noise, test island + 3 houses for scale, orbiting camera, warm sun | godot/main.gd, godot/shaders/water.gdshader |
| 2026-09-23 | First web export built locally (Godot 4.5.2 headless + web_nothreads templates); boots in headless Chrome | export/index.html via build.sh |
| 2026-09-23 | hint_depth_texture proven EMPTY on the WebGL2 Compatibility export (debug render: all-far buffer); foam pivoted to analytic shore SDF - soft lapping wash verified around the test island on the real export at 390x844 | /tmp/godot-web4.png equivalent |
| 2026-09-23 | Exposure pass: sparkle tamed (blobs -> glints), ambient .85->.55, sun 1.9->1.5 | frames |
