# Nakka-Labs — Design Bible

> Status: the one file to read before starting any new app's visual
> identity. Replaces `DESIGN_LANGUAGE.md` (same content, consolidated and
> tightened). Lives in `clantab-ios` for now since it's the only connected
> repo and the most advanced app; belongs at the portfolio level (a
> `nakka-labs` org profile repo, or `tiny-tools`'s shared design system)
> once one of those exists. Every rule below is portfolio-wide — decided
> once, applied to all four apps — even though only ClanTab is built out
> enough to show it yet.
>
> For a minimalist, flat, system-font portfolio, almost everything below
> reduces to two decisions: **the font treatment** (§1) and **the color
> formula** (§2). Everything after that is reinforcement, not identity.
> A visual reference canvas applying all of this to all four apps exists
> at https://claude.ai/code/artifact/ef84d6ca-6134-448a-b057-9127197e2df7
> — optional, not required reading; this file is the source of truth.

## Why a shared language, not shared assets

Native iOS apps (ClanTab, LoopTimer, Habit Tracker) can't literally share
a font bundle or component library across separate Xcode projects without
real plumbing, and the PWAs in `tiny-tools` already have their own shared
design system per the stack decision. What *can* be shared for free is a
small set of construction rules applied consistently per-repo — the same
reason Apple's own first-party apps look related without sharing pixels.

## 1. Typography — the identity

System fonts only for body text and chrome: SF Pro (iOS) / system-ui or
Inter (web). Zero cost, zero maintenance, no bundling or licensing for
the 95% of the UI that's reading, not signature.

One deliberate, portfolio-wide exception — the single highest-leverage
move in this document: a **distinct display typeface**, used only for
each app's wordmark and its hero numerals (ClanTab's balance, LoopTimer's
countdown, Habit Tracker's streak count, PitchLab's detected pitch). Free
and self-hosted (a Google Fonts family, not a paid license), same face
across all four apps so it reads as one portfolio's signature rather than
four unrelated choices. This supersedes the earlier "`ui-rounded` (SF
Rounded) for hero numerals" rule — same instinct (numbers-first apps
deserve a felt signature), stronger execution: a genuinely distinct face
reads as designed, where a system font at a different weight reads as a
tweak. Touches nothing else — not body text, not chrome, not iconography.

**Number formatting is part of the signature, not an afterthought.**
Every hero numeral uses tabular (fixed-width, non-proportional) figures —
so a value that updates in place doesn't jiggle the layout around it —
and one consistent thousands-separator/decimal style across all four
apps. Cheap (a font-feature flag, not new design work) and it's the kind
of detail that reads as "an app, not a tutorial project" the moment a
number changes on screen.

## 2. Color — one formula, one hue per app

`oklch(55% 0.16 H)` — lightness and chroma fixed, hue (`H`) varies per
app. Current assignments: **ClanTab** 250 (blue), **LoopTimer** 35
(orange), **Habit Tracker** 150 (green), **PitchLab** 305 (magenta).
Picking a hue for the next app: use the same formula, pick whichever
unused hue angle best fits that app's feel — don't eyeball a new color
from scratch. That's it; this isn't a bigger system than that.

The same construction generalizes past app-level branding: within an app
that has many like things a person needs to tell apart at a glance, hash a
stable identifier to a hue and reuse the formula at a different
lightness/chroma band per use, rather than hand-picking colors one at a
time. ClanTab's per-category colors (`CategoryColor`, pastel band) and
per-member identity colors (`MemberColor`, a higher-chroma band) are the
same formula at two bands, not two separate systems — treat any future
"N things need distinct colors" problem in any app the same way before
reaching for anything hand-picked.

**Surfaces sit on a short elevation scale, not two flat tones.** One
named set of greys — recessed *well* → *canvas* → *card* → *raised* —
resolved per light/dark, rather than scattered `secondary.opacity(…)`
guesses. ClanTab's is `App/ClanTab/Surface.swift`.

**Neutrals are tinted, never pure greyscale.** Body text, chrome, and
those surface tones mix in a little of the app's own hue rather than
sitting at true `oklch(L% 0 0)` grey. The same trick Linear/Arc use to
make a "monochrome" UI not read as a default system theme — barely
perceptible on its own, felt as soon as it's missing. ClanTab's
`Surface.swift` tiers carry a fixed `chroma 0.007` at 250° (about 4% of
the accent's `0.16` — the "10-15% of the hue" figure clips ugly at the
near-white tiers, so it landed lower); the brightest light tiers are
pulled just off pure white so the tint has room to show. System
semantic text colours (`.secondary` etc.) are left alone — tinting
those app-wide fights the system controls they sit beside.

## 3. App icons

Flat, geometric, single strong silhouette, legible at 40px, no baked-in
text, no photoreal, no drop shadow/3D bevel. One deliberate, portfolio-
wide exception: a tasteful two-stop gradient using the app's own hue
(§2) at two points on the same lightness/chroma formula — never a second,
unrelated color — scoped to the app icon itself and to in-app hero
moments (a completed-timer state, a hit-streak celebration, ClanTab's
balance hero card), never to routine UI chrome, where flat color stays
the default. What varies per app is the **motif** (what the shape is) and
whether that app leans on the gradient or stays fully flat — never the
construction style itself, and never more than the one gradient per icon.

**Generation workflow** (the same process for every app's icon — only the
concept/motif changes per app):

> A minimalist, flat vector app icon for "[App Name]," a [one-line app
> description]. Concept: [the app-specific motif — a single strong,
> literal-but-not-clichéd shape tied to what the app does]. Two-tone (or,
> where the gradient exception above is used, two-stop-gradient) palette
> built from the app's own `oklch(55% 0.16 H)` hue — a confident
> background with a crisp light mark. No gradients beyond the one
> sanctioned stop-pair, no drop shadows, no 3D bevel, no photorealism, no
> text or letters. Square 1024×1024 canvas, full-bleed flat background, no
> transparency (a transparent icon is an App Store rejection), no rounded
> corners baked in (iOS applies its own mask). Generous padding,
> confident negative space, single strong silhouette that reads clearly
> at 60×60px. Style reference: modern iOS utility-app icons (Things 3,
> Bear, Fantastical) — clean, geometric, not cartoonish, not
> generic-fintech/generic-utility. Avoid whatever's overused in that
> app's specific category (for ClanTab: dollar signs, piggy banks,
> wallets, scales/balance-beams, pie charts, overlapping-people icons).

ClanTab's own instance of this, kept as the worked example: a bold
geometric equals sign ("="), evolving the app's placeholder icon and
established blue, symbolizing settling a balance rather than money
itself. The background is this app's instance of the sanctioned two-stop
gradient — `oklch(60% 0.15 250)` at the top to `oklch(40% 0.14 250)` at
the bottom, interpolated in OKLCH so the midtones stay on-hue — the same
stop-pair as the in-app hero moments (`RecapCard.brandGradient`). Crisp
near-white mark (`#FAFBFD`). Alternate motifs considered: a tab/flag
shape split down the center (literal "clan tab"), or three dots
converging into one line (small-group-settling-into-one). Regenerated
by `docs/branding/make-app-icon.py` (geometry frozen from the prior flat
icon); installed at
`App/ClanTab/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.

**Distinctiveness check** (run before finalizing any app's icon — not
just eyeballing it next to a couple of competitors):

1. **Visual competitor survey.** Pull current App Store icons for the
   category's real players (for ClanTab: Splitwise, Settle Up, Tricount,
   Spliit, Kittysplit, plus adjacent fintech — Venmo, Cash App, PayPal).
   Verify live; icons refresh over time. The bar is a distinct *shape*,
   not a distinct *color* — a shared hue family (most fintech sits in
   blue/green/purple) is common territory in every category.
2. **Reverse image search** each generated candidate (Google Lens or
   TinEye) before finalizing — catches an accidental near-duplicate the
   model pulled from training data, more common than expected with
   generic "minimalist flat icon" prompts.
3. **Trademark search** — USPTO TESS / TMview for design marks in
   software/financial-app classes (9, 36, 42) that could read as
   confusingly similar. Real legal exposure, separate from "looks kind of
   alike."
4. **Small-size confusability test — the actual bar.** Render the
   candidate at real iOS sizes (180/120/60/40px) next to 3-4 competitor
   icons at the same size, on both light and dark home screens. A
   full-size side-by-side is the wrong test — nobody sees the icon at
   full size except the person picking it, once, at generation time.

ClanTab's own check: legibility re-confirmed at 180/120/60/40px on light
and dark after the gradient was added — the "=" stays crisp, the
gradient reads as subtle depth, not muddiness. The motif is unchanged
from the flat version, so the shape-distinctiveness reasoning carries
over (a bold "=" is distinct from Splitwise's split-S, Settle Up,
Tricount, Venmo, Cash App, PayPal — all a different mark; shared blue
hue is common category territory). Reverse-image and trademark search
still need tools this environment doesn't have (Google Lens/TinEye,
USPTO TESS) — run those before submitting to the App Store.

## 4. In-app iconography — SF Symbols only, with one named exception

No custom icon sets, ever, for *functional* UI: buttons, nav, category
glyphs — all SF Symbols. Free, automatically themed, automatically
Dynamic-Type- and VoiceOver-correct. Not really a brand choice — a "don't
reinvent free infrastructure" rule, stated so nobody reaches for a custom
icon pack mid-project.

One deliberate, portfolio-wide exception: a single custom empty-state
illustration per app, reused everywhere that app shows a genuine
zero-state (ClanTab's "no groups yet" / "no expenses yet"; the equivalent
first-run zero-state in each other app). One asset per app, not per
screen or per state — this is a branding moment (the first thing a new
user sees), not functional chrome, so it sits outside the
infrastructure-reuse reasoning above rather than contradicting it.

ClanTab's own instance: an empty rounded "tab" (outline, not filled —
nothing in it yet) holding the app's "=" mark. A template image
(`EmptyStateGlyph`, generated by `docs/branding/make-empty-state.py`),
tinted `.secondary` so it themes automatically. Shared across every
genuine "nothing here yet" state — no groups, no expenses, nothing to
chart, no recurring reminders, empty bin. The transient/positive
outcome states ("Nothing Matches" on a filtered feed, "All Square" on
Settle Across Groups) keep a plain SF Symbol — they aren't zero-state
branding moments.

## 5. Motion & sound — confirm, don't decorate

A light haptic on every state-confirming action (a timer completing, a
habit checked off, an expense settled), never on navigation or routine
taps — ClanTab's existing `.sensoryFeedback` pattern, made the portfolio
rule. Cheap, consistent, and a felt quality signal even to someone who
never consciously registers the shared icon construction rule.

One deliberate, portfolio-wide addition: a short, custom confirmation
sound, played alongside the haptic — never instead of it, so the silent-
switch/Do Not Disturb case still gets a correct confirmation — on the
single most significant confirming action per app (ClanTab: settled up;
LoopTimer: timer complete; Habit Tracker: streak milestone; PitchLab:
pitch matched). One sound design, reused across all four apps at the same
moment-class, not a bespoke sound per app — same instinct as the color
formula: one system, applied consistently, rather than four separate
creative decisions.

ClanTab's own instance: `settled.caf` — a short rising perfect fifth
(C6→G6) on a gentle exponential decay, peak ~0.32 so it sits under
speech, ~0.35s of audible content. Synthesised by
`docs/branding/make-confirmation-sound.py` (16-bit mono → `afconvert` to
`.caf`). Played via `ConfirmationSound.play()` (`AudioServicesPlaySystemSound`,
so it honours the ring/silent switch) in `SettleUpView`'s "Mark as Paid"
handler, alongside the existing `.sensoryFeedback(.success)` haptic —
never the add-expense confirm, only settling up.

**One named spring curve for every confirm-moment transition.** A single
response/dampingFraction pair (name it — e.g. the "`.claimSettle`
spring") reused for every matched-geometry/spring-based transition tied
to a confirming action, across all four apps, the same way the haptic and
sound are one system rather than four. A shared *feel*, not just a shared
rule — the thing that makes four different apps register as the same
hand having built them.

## 6. Naming

Short, compound, coined names. No articles, no punctuation, hints at
function: ClanTab, LoopTimer, PitchLab. "Habit Tracker" is the current
outlier — two literal words, not a coined compound. Not urgent enough to
force a rename; worth keeping in mind on that app's next polish pass.

## 7. Portfolio credit, in-app

A small, consistent "Nakka-Labs" line on each app's Settings/About
screen only — never on the icon, never on primary UI.

## 8. README / repo presentation

The goal is a hiring portfolio, not app-store growth — README structural
consistency across repos is probably higher-leverage than in-app pixel
consistency. Same section order in every repo: badges → screenshots
table → architecture diagram → tech stack table. Same screenshot device
frame and background, same mermaid diagram style. Someone clicking
through 3-4 of these repos in one sitting notices structure before they
notice whether two accent blues are the exact same hex.

## Explicitly not doing (yet)

- No shared component library or design-token file across native repos —
  premature before a second native app is actively being built alongside
  ClanTab.
- No paid or licensed fonts — the §1 display face and all system fonts
  stay free.
- No design-tool subscription, no re-running a visual design tool to
  illustrate a decision this file already states in words.

## When to actually reach for a design tool again

Only when there's a genuinely *open* visual question — prototyping a
real screen's layout, choosing between actually different directions for
something new. Not to re-illustrate a rule that's already settled here in
one sentence. Read this file, pick the numbers §1-§2 give you, build.
