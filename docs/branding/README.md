# Brand assets

One wordmark, reused everywhere — README header, App Store listing, a landing
page. Don't redraw it per surface.

## Wordmark

The "=" mark (brand blue `#0074CA`, `DESIGN_BIBLE.md` §2) + **ClanTab** in
**SF Pro Rounded, Bold** — a system font, and its rounded terminals echo the
mark's capsule bars. Glyphs are flattened to vector paths in the SVGs, so they
render identically without the font installed.

| file | use |
|---|---|
| `wordmark.svg` / `wordmark.png` (1200w) / `wordmark@2x.png` (2400w) | on light backgrounds (blue mark, ink `#15161A` text) |
| `wordmark-white.svg` / `wordmark-white.png` (1200w) | on dark or brand-blue backgrounds (all white) |

Aspect ratio 4324 : 1000 (~4.32 : 1). Keep clear space of at least the mark's
height on every side. Don't recolour, rotate, or restretch it.

The app **icon** and **launch mark** live in `App/ClanTab/Assets.xcassets/`
(`AppIcon`, `LaunchLogo`) — same "=" motif, same blue.

## Regenerating

`swift wordmark.swift <output-dir>` rebuilds all five files from SF Pro Rounded.
Change the font weight or the `blue` / `ink` constants there, not the exported
files.
