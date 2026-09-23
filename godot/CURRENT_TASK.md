# Current task

**Task:** Port TIDEMILL to Godot 4.5 (Compatibility / WebGL2) on this branch, water-first: depth-based shoreline foam and wave/sparkle shading that three.js could not carry, then lighting, then the town grammar and interaction.
**Spec:** Townscaper official screenshots (Steam app 1291340); three.js main stays the live reference for parity
**Started:** 2026-09-23

## Acceptance criteria

- [ ] Water reads better than the three.js build: depth-based foam at shorelines, animated waves, sun sparkle
- [ ] Movie-maker frames at 390x844 and 1280x800 checked side by side against the reference and the three.js build
- [ ] Web export builds via build.sh (headless export + CSP), boots in a browser with zero CSP violations
- [ ] Deploys to GitHub Pages ONLY on the main agent's go; three.js main untouched

## Non-goals

- Not replacing the live three.js build before parity + approval
- No accounts, backend, analytics
