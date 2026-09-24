# Current task

**Build:** Tidemill v4 - live at https://aeiouvcode.github.io/tidemill/ (main b7a40cd0, 2026-09-24).
**Spec:** the user's own Townscaper town, https://oskarstalberg.com/Townscaper/#Gi5zRAhcVVt21Tp1I-EoL5kWb7I-EoL5kutP3_c7

## Next pass (only when asked)

- [ ] Slimmer, softer foam halo
- [ ] Coral shading on the shadow side
- [ ] Arches/stilts under overhangs, stairs, placement pop
- [ ] Ambient occlusion
- [ ] Real-device check at 390px

## Rules

- v4 (index.html + app.js + vendor/) is the only main build. The old single-file loop and the "track A" plan are retired.
- Original code only, local-first, no backend. Minimal UI, no dark-terminal/green skin.
- Deploy only on the main agent's go. Hash-verify the served bytes after every deploy.
