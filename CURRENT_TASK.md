# Current task

**Task:** Two tracks. (A) Three.js main: close remaining reference distance - full ink outlines on wall edges (P1), wall texture (P6), richer grammar (P7). (B) Godot 4 (Compatibility/WebGL2) branch: port the scene prioritizing the engine-bound gaps (water shading, foam, lighting); crib the kin-living-pond godot-prototype pipeline.
**Spec:** Townscaper official screenshots (Steam app 1291340), side-by-side audits each cycle
**Started:** 2026-09-23

## Acceptance criteria

- [ ] Track A: side-by-side vs reference at 390px and desktop shows ink outlines on wall/roof edges, non-flat walls, and at least one new grammar element
- [ ] Track B: Godot project source lives on its own branch from day one with state files; web export builds; scene port started with water/foam/lighting first
- [ ] Three.js main stays live and untouched by track B; the Godot build deploys to Pages only on the main agent's go
- [ ] Live Pages bytes hash-match the tested local file after every track-A deploy; Instinct File revision republished per milestone

## Non-goals

- No imported component or micro-interaction libraries; original builds only
- No dark-terminal/green-accent reskin; the warm harbor identity stays
- Desktop polish never at the expense of the 390px phone read (primary grading axis)
- Track B does not touch main or Pages without explicit approval
