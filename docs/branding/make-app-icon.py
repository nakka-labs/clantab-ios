"""Generate ClanTab's app icon (DESIGN_BIBLE.md §3): the bold geometric "=" mark,
now on a two-stop gradient in the app's own hue (250) at oklch 60%->40% lightness,
top to bottom -- the same gradient as the in-app hero moments. Flat, no bevel, no
shadow, full-bleed, opaque, 1024 px.

Run from the repo root:  python3 docs/branding/make-app-icon.py   (needs Pillow)
The "=" geometry is frozen from the prior flat icon; edit the two stop L/C
values or the capsule coords below to iterate.
"""
import math
from PIL import Image, ImageDraw

N = 1024
SS = 4

def oklch_to_lin(L, C, h_deg):
    h = math.radians(h_deg)
    a, b = C * math.cos(h), C * math.sin(h)
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_**3, m_**3, s_**3
    return (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )

def lin_to_srgb8(r, g, b):
    def enc(x):
        x = max(0.0, min(1.0, x))
        return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1/2.4) - 0.055
    return tuple(round(enc(v) * 255) for v in (r, g, b))

# Two stops on the same oklch(L 0.60->0.40, C 0.15->0.14, h 250) line -- the
# in-app hero gradient (RecapCard.brandGradient). Interpolate in OKLCH so the
# midtones stay on-hue.
L0, C0 = 0.60, 0.15
L1, C1 = 0.40, 0.14

grad = Image.new("RGB", (1, N))
gp = grad.load()
for y in range(N):
    t = y / (N - 1)
    L = L0 + (L1 - L0) * t
    C = C0 + (C1 - C0) * t
    gp[0, y] = lin_to_srgb8(*oklch_to_lin(L, C, 250))
img = grad.resize((N, N))

# The mark: two capsules, drawn at SSx then downsampled for clean edges.
mask = Image.new("L", (N * SS, N * SS), 0)
md = ImageDraw.Draw(mask)
bar_x0, bar_x1 = 206 * SS, 818 * SS
bar_h = 121 * SS
r = bar_h // 2
for top_y in (359, 543):
    y0 = top_y * SS
    md.rounded_rectangle([bar_x0, y0, bar_x1, y0 + bar_h], radius=r, fill=255)
mask = mask.resize((N, N), Image.LANCZOS)

mark = Image.new("RGB", (N, N), (250, 251, 253))  # a hair cool of pure white
img = Image.composite(mark, img, mask)

out = "App/ClanTab/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
img.save(out)
print("wrote", out, img.size, img.mode)
print("top stop  #%02X%02X%02X" % gp[0, 0])
print("bot stop  #%02X%02X%02X" % gp[0, N - 1])
