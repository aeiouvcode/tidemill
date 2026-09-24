# Current task

**Build:** Tidemill v4 - live at https://aeiouvcode.github.io/tidemill/ (main b7a40cd0, 2026-09-24).
**Spec:** the user's own Townscaper town, https://oskarstalberg.com/Townscaper/#Gi5zRAhcVVt21Tp1I-EoL5kWb7I-EoL5kutP3_c7

## Improvement loop (dev branch, user said "keep cooking" 2026-09-24 17:32; live push only on his go)

Cycle 1 - live at /next/ (main 9c354aea).
Cycle 2 (dev, not live): bell cap, stilts, landing steps.
Cycle 1: placement pop, arcades under overhangs, auto-framing, coral shadows, slimmer foam.

## Next pass

- [x] Slimmer, softer foam halo (c1)
- [x] Coral shading on the shadow side (c1)
- [x] Arches under overhangs + placement pop (c1)
- [x] Stairs: landing steps down into the sea on some open quay edges (c2)
- [x] Stilts over open water (c2)
- [x] Smooth ogee bell cap, no tile texture (c2)
- [ ] Ambient occlusion
- [ ] Real-device check at 390px

## Rules

- v4 (index.html + app.js + vendor/) is the only main build. The old single-file loop and the "track A" plan are retired.
- Original code only, local-first, no backend. Minimal UI, no dark-terminal/green skin.
- Deploy only on the main agent's go. Hash-verify the served bytes after every deploy.
