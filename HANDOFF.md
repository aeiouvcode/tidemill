# Handoff

## Current build: Tidemill v4 (live since 2026-09-24 07:31 IST)

Live: https://aeiouvcode.github.io/tidemill/ - commit b7a40cd0 on main.
v4 is the only main build. It replaced the earlier single-file index.html; that build is recoverable at commit 0c650137.

Files:
- index.html - shell + minimal UI (palette, undo / erase / share)
- app.js - the whole game (grid, building grammar, water, input, save)
- vendor/three.module.min.js (three@0.160.0) and vendor/OrbitControls.js (import rewritten to ./three.module.min.js). No CDN at runtime.

## Resume here

Any change to main must start from app.js/index.html at the current head. Never web-edit or redeploy the old single-file index.html - it would overwrite v4.
Deploy loop: build locally, headless-chrome render at 390x844, side-by-side vs the reference, commit via the Git Data API (fast-forward, no force), then poll Pages until the served md5 of every changed file matches local, then load once in the cloud browser.
Deploys go out only on the main agent's go, relaying the user's approval.

## Reference

The user's own Townscaper town: https://oskarstalberg.com/Townscaper/#Gi5zRAhcVVt21Tp1I-EoL5kWb7I-EoL5kutP3_c7
It shows a tall coral-red brick tower with an octagonal gold bell cap and finial, two narrow red gabled houses, a yellow cottage with bushes, a cobbled quay with red trim, thin dark railings and a T-shaped pier, and a soft foam halo on grey-teal water.
v4 opens on a recreation of this town.

## Live pages (2026-09-24 17:48)

- Root https://aeiouvcode.github.io/tidemill/ = original v4 (root index.html/app.js). The user wants it KEPT - never overwrite root.
- https://aeiouvcode.github.io/tidemill/next/ = improvement track (main commit 9c354aea, pass 1). Deploy a new pass by updating next/app.js (and next/ files) on main, only on the user's go.

## Dev branch

Improvement cycles land on branch `dev` first; main (live Pages) moves only on the user's explicit go. Cycle 1 on dev: placement pop (FRESH block routed into a separate group, spring-scaled), arcades + piers under floating blocks, fitView() auto-framing on load/resize, warmer hemisphere/fill light, slimmer foam.

## Open gaps (next pass)

- No ambient occlusion
- Missing grammar: stairs up to raised floors (only sea landing steps so far)
- Not yet checked on a real phone

## Save format

URL hash and localStorage key tidemill.town.v3, format "g11.<base64 blocks>". Grid seed 11 is part of the format. Towns saved by pre-v4 builds do not load.

## Failed approaches

| Approach | Why it failed | Date |
| --- | --- | --- |
| execute-js with nested `await (await fetch())` or long multi-clause scripts for the PAT bridge | Wrapper throws "missing ) after argument list"; one await per statement works | 2026-09-24 |
