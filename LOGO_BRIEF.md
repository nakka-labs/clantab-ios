# ClanTab — Logo / App Icon Brief

> Status: **done.** Installed at
> `App/ClanTab/Assets.xcassets/AppIcon.appiconset/icon-1024.png`,
> replacing the earlier placeholder. Built directly as vector art (not an
> AI image-gen output) to hit the bible's formula exactly: background is
> the precise sRGB conversion of `oklch(55% 0.16 250)` from
> `DESIGN_BIBLE.md` §2 — `#0074CA` — computed with the standard OKLab
> conversion matrices, not eyeballed (the earlier placeholder's blue,
> `#0A85FF`, was never actually on-formula). Same equals-sign motif as
> the placeholder it replaces, refined proportions, no transparency (flat
> RGB, alpha dropped — a transparent icon is an App Store rejection).
>
> Distinctiveness check status: legibility passed — rendered and
> visually confirmed clear at 180/120/60/40px, matching item 4 below.
> Items 2 (reverse image search) and 3 (trademark search) below need
> tools this session doesn't have (Google Lens/TinEye, USPTO TESS) — run
> those yourself before shipping to the App Store; item 1's shape-not-
> color reasoning still holds since nothing in this category uses a
> plain equals-sign motif as far as a general search turned up.

## Generation prompt

> A minimalist, flat vector app icon for "ClanTab," an expense-splitting
> app for small groups of friends. Concept: a bold, geometric equals sign
> ("=") — evolving the app's existing placeholder icon and its established
> blue accent color, symbolizing settling a balance rather than money
> itself. Two-tone palette: a confident deep blue background with a crisp
> white or light-blue mark — no gradients, no drop shadows, no 3D bevel,
> no photorealism, no text or letters. Square 1024×1024 canvas, full-bleed
> flat background, no transparency, no rounded corners baked in (iOS
> applies its own mask). Generous padding, confident negative space,
> single strong silhouette that reads clearly at 60×60px. Style reference:
> modern iOS utility-app icons (Things 3, Bear, Fantastical) — clean,
> geometric, not cartoonish, not generic-fintech. Avoid: dollar signs,
> piggy banks, wallets, scales/balance-beam icons, pie charts, or
> overlapping-people icons — all overused in the expense-splitting
> category.

**Alternate motifs**, same style constraints, if the equals-sign doesn't
land:
- A simple tab/flag shape with a subtle split down the center — literal
  "clan tab" as a bar tab.
- Three small dots/circles converging into one connecting line —
  small-group-settling-into-one.

## Distinctiveness check (run before picking a finalist)

Same rigor as the name-collision check already done for "ClanTab" itself
— not just eyeballing it next to a couple of apps.

1. **Visual competitor survey.** Pull current App Store icons for
   Splitwise, Settle Up, Tricount, Spliit, Kittysplit, and adjacent
   fintech (Venmo, Cash App, PayPal). As of general knowledge going in —
   verify live, icons refresh over time — Splitwise sits in teal/green,
   Venmo/PayPal in blue, Cash App in bright green, Settle Up in
   purple/blue. Staying in ClanTab's own blue is fine; the bar is a
   distinct *shape*, not a distinct *color* — blue is common territory in
   this space.
2. **Reverse image search** each generated candidate (Google Lens or
   TinEye) before finalizing. Catches an accidental near-duplicate the
   model pulled from training data — more common than expected with
   generic "minimalist flat icon" prompts.
3. **Trademark search** — USPTO TESS / TMview for design marks in
   software/financial-app classes (9, 36, 42) that could read as
   confusingly similar. Real legal exposure, separate from "looks kind of
   alike."
4. **Small-size confusability test — the actual bar.** Render the
   candidate at real iOS sizes (180/120/60/40px) next to 3-4 competitor
   icons at the same size, on both light and dark home screens. A
   full-size side-by-side is the wrong test — nobody sees the icon at
   full size except you, at generation time, once.
