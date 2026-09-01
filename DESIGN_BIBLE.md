# Nakka-Labs — Design Bible

> Status: the one file to read before starting any new app's visual
> identity. Replaces `DESIGN_LANGUAGE.md` (same content, consolidated and
> tightened). Lives in `clantab-ios` for now since it's the only connected
> repo and the most advanced app; belongs at the portfolio level (a
> `nakka-labs` org profile repo, or `tiny-tools`'s shared design system)
> once one of those exists.
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

System fonts only: SF Pro (iOS) / system-ui or Inter (web). Zero cost,
zero maintenance, no bundling or licensing. One deliberate exception,
and it's the single highest-leverage move in this whole document: use
`ui-rounded` (SF Rounded) for **hero numerals** — the balance in
ClanTab, the countdown in LoopTimer, the streak count in Habit Tracker,
the detected pitch in PitchLab. Every one of these apps is numbers-first;
a consistent rounded-numeral treatment against otherwise-plain system
type is a real, felt signature that touches nothing else — not body
text, not chrome, not iconography.

## 2. Color — one formula, one hue per app

`oklch(55% 0.16 H)` — lightness and chroma fixed, hue (`H`) varies per
app. Current assignments: **ClanTab** 250 (blue), **LoopTimer** 35
(orange), **Habit Tracker** 150 (green), **PitchLab** 305 (magenta).
Picking a hue for the next app: use the same formula, pick whichever
unused hue angle best fits that app's feel — don't eyeball a new color
from scratch. That's it; this isn't a bigger system than that.

## 3. App icons

Flat, geometric, single strong silhouette, no gradients/bevels/photoreal,
legible at 40px, no baked-in text. What varies per app is the **motif**
(what the shape is), never the construction style. `LOGO_BRIEF.md` has
the actual generation prompt and a distinctiveness-check process
(competitor survey, reverse image search, trademark search, small-size
confusability test) — read that when actually producing an icon; this
section is the rule, not the workflow.

## 4. In-app iconography — SF Symbols only

No custom icon sets, ever, on the native apps. Free, automatically
themed, automatically Dynamic-Type- and VoiceOver-correct. Not really a
brand choice — a "don't reinvent free infrastructure" rule, stated so
nobody reaches for a custom icon pack mid-project.

## 5. Motion — confirm, don't decorate

A light haptic on every state-confirming action (a timer completing, a
habit checked off, an expense settled), never on navigation or routine
taps — ClanTab's existing `.sensoryFeedback` pattern, made the portfolio
rule. Cheap, consistent, and a felt quality signal even to someone who
never consciously registers the shared icon construction rule.

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
- No custom/licensed fonts.
- No design-tool subscription, no re-running a visual design tool to
  illustrate a decision this file already states in words.

## When to actually reach for a design tool again

Only when there's a genuinely *open* visual question — prototyping a
real screen's layout, choosing between actually different directions for
something new. Not to re-illustrate a rule that's already settled here in
one sentence. Read this file, pick the numbers §1-§2 give you, build.
