"""ClanTab's one custom empty-state glyph (DESIGN_BIBLE.md §4's single sanctioned
exception to SF-Symbols-only): a flat mark reused across every genuine zero-state
-- "no groups yet", "no expenses yet", "nothing to chart yet".

Motif: an empty rounded "tab" (outline, not filled -> nothing in it yet) holding
the app's "=" mark -- "a shared tab, waiting for its first expense". Rendered as
a template image (single colour + alpha) so SwiftUI tints it per theme.

Run from the repo root:  python3 docs/branding/make-empty-state.py   (needs Pillow)
"""
from PIL import Image, ImageDraw

INK = (30, 32, 36, 255)  # any opaque colour; the asset is template-rendered
SS = 4


def build(px):
    S = px * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # The empty tab: a thick rounded-rect OUTLINE, tilted a touch so it feels
    # placed, not boxed-in. Drawn upright then rotated.
    pad = int(S * 0.16)
    card = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    stroke = int(S * 0.072)
    cd.rounded_rectangle(
        [pad, pad, S - pad, S - pad],
        radius=int(S * 0.20),
        outline=INK,
        width=stroke,
    )

    # The "=" inside: two solid rounded bars, a bit shy of half the card wide.
    inner_w = S - 2 * pad
    bar_w = int(inner_w * 0.46)
    bar_h = int(inner_w * 0.11)
    bar_r = bar_h // 2
    cx = cy = S // 2
    gap = int(bar_h * 1.5)
    for sign in (-1, 1):
        y = cy + sign * (gap // 2 + bar_h // 2)
        cd.rounded_rectangle(
            [cx - bar_w // 2, y - bar_h // 2, cx + bar_w // 2, y + bar_h // 2],
            radius=bar_r, fill=INK,
        )

    card = card.rotate(-5, resample=Image.BICUBIC, center=(cx, cy))
    img = Image.alpha_composite(img, card)
    return img.resize((px, px), Image.LANCZOS)


for scale in (1, 2, 3):
    px = 128 * scale
    suffix = "" if scale == 1 else f"@{scale}x"
    out = f"App/ClanTab/Assets.xcassets/EmptyStateGlyph.imageset/empty-state{suffix}.png"
    build(px).save(out)
    print("wrote", out)
