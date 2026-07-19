#!/usr/bin/env python3
"""Generate the Sequence brand SVGs (app icon + store assets) from the design.

The mark is a diagonal "/" five-in-a-row of poker chips — blue, green, red
(centre, larger), green, blue — on a dark radial-gradient field. Each chip
carries the design-language detailing: a top-light/bottom-shade fill, a dashed
white poker ring and a translucent centre hole, with a soft drop shadow.

Run, then render to PNG with Inkscape (see tool/render_branding.sh).
"""
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "branding")

# Team palette (light / base / dark) for the chip gradients.
TEAMS = {
    "blue":  ("#6f9bf6", "#2f6df0", "#224f97"),
    "green": ("#4fcb96", "#16a36b", "#0f714a"),
    "red":   ("#ec7a72", "#d8453b", "#9b2f28"),
}
ORDER = ["blue", "green", "red", "green", "blue"]  # i = -2..+2


def defs():
    grads = []
    for name, (lo, mid, hi) in TEAMS.items():
        grads.append(
            f'<linearGradient id="g_{name}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{lo}"/>'
            f'<stop offset="0.52" stop-color="{mid}"/>'
            f'<stop offset="1" stop-color="{hi}"/></linearGradient>'
        )
    return (
        '<defs>'
        '<radialGradient id="field" cx="0.5" cy="0.24" r="0.92">'
        '<stop offset="0" stop-color="#2a313d"/>'
        '<stop offset="0.6" stop-color="#1a1f27"/>'
        '<stop offset="1" stop-color="#14181f"/></radialGradient>'
        '<radialGradient id="field_fg" cx="0.16" cy="0.30" r="1.25">'
        '<stop offset="0" stop-color="#2a313d"/>'
        '<stop offset="0.55" stop-color="#191e26"/>'
        '<stop offset="1" stop-color="#13171d"/></radialGradient>'
        + "".join(grads) +
        '<filter id="soft" x="-40%" y="-40%" width="180%" height="180%">'
        '<feGaussianBlur stdDeviation="11"/></filter>'
        '</defs>'
    )


def chip(cx, cy, r, team):
    lo, mid, hi = TEAMS[team]
    ring_r = r * 0.74
    circ = 2 * math.pi * ring_r
    seg = circ / 16.0
    dash = f"{seg*0.6:.1f} {seg*0.4:.1f}"
    sw = r * 0.09
    hole = r * 0.33
    return (
        f'<g>'
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#g_{team})"/>'
        f'<circle cx="{cx}" cy="{cy}" r="{ring_r:.1f}" fill="none" '
        f'stroke="#ffffff" stroke-opacity="0.55" stroke-width="{sw:.1f}" '
        f'stroke-dasharray="{dash}" stroke-linecap="round"/>'
        f'<circle cx="{cx}" cy="{cy}" r="{hole:.1f}" fill="#ffffff" '
        f'fill-opacity="0.16"/></g>'
    )


def mark(cx, cy, r, rc, step, line_w, shadow=True):
    """Five chips on the "/" diagonal, drawn back-to-front (centre on top)."""
    def pos(i):
        return (cx + i * step, cy - i * step)
    x0, y0 = pos(-2)
    x1, y1 = pos(2)
    parts = []
    # Soft drop shadow as a blurred dark layer behind everything.
    if shadow:
        sh = ['<g filter="url(#soft)" fill="#05070b" fill-opacity="0.5">']
        for i in (-2, -1, 0, 1, 2):
            x, y = pos(i)
            rr = rc if i == 0 else r
            sh.append(f'<circle cx="{x}" cy="{y + rr*0.09:.1f}" r="{rr}"/>')
        sh.append('</g>')
        parts.append("".join(sh))
    parts.append(
        f'<line x1="{x0}" y1="{y0}" x2="{x1}" y2="{y1}" stroke="#ffffff" '
        f'stroke-opacity="0.12" stroke-width="{line_w}" stroke-linecap="round"/>'
    )
    # outer pairs first, centre last so it sits on top
    for i in (-2, 2, -1, 1):
        x, y = pos(i)
        parts.append(chip(x, y, r, ORDER[i + 2]))
    parts.append(chip(cx, cy, rc, "red"))
    return "".join(parts)


def write(name, body):
    path = os.path.join(OUT, name)
    with open(path, "w") as f:
        f.write(body)
    print("wrote", os.path.relpath(path))


def svg(w, h, inner):
    return (f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" '
            f'xmlns="http://www.w3.org/2000/svg">{defs()}{inner}</svg>')


# 1) Master app icon — full bleed (iOS + Android legacy).
write("app_icon.svg", svg(1024, 1024,
      '<rect width="1024" height="1024" fill="url(#field)"/>'
      + mark(512, 512, 120, 132, 150, 30)))

# 2) Adaptive foreground — mark only, transparent, padded to the safe zone.
write("app_icon_fg.svg", svg(1024, 1024,
      mark(512, 512, 78, 86, 98, 20, shadow=False)))

# 3) Adaptive background — the dark field only.
write("app_icon_bg.svg", svg(1024, 1024,
      '<rect width="1024" height="1024" fill="url(#field)"/>'))

# 4) Play Store feature graphic — 1024 x 500.
feature = (
    '<rect width="1024" height="500" fill="url(#field_fg)"/>'
    + mark(232, 250, 58, 64, 73, 16)
    + '<text x="500" y="150" font-family="Archivo, Helvetica, Arial, sans-serif" '
      'font-size="13" font-weight="700" letter-spacing="5" fill="#7a8495">'
      'THE CLASSIC BOARD GAME</text>'
    + '<text x="500" y="250" font-family="Archivo, Helvetica, Arial, sans-serif" '
      'font-size="78" font-weight="800" letter-spacing="8" fill="#ffffff">'
      'SEQUENCE</text>'
    + '<text x="500" y="312" font-family="Archivo, Helvetica, Arial, sans-serif" '
      'font-size="26" font-weight="600" fill="#aab2c0">'
      'Play your cards. Build five in a row. Win.</text>'
    + '<circle cx="512" cy="372" r="13" fill="#d8453b"/>'
    + '<circle cx="548" cy="372" r="13" fill="#2f6df0"/>'
    + '<circle cx="584" cy="372" r="13" fill="#16a36b"/>'
)
write("feature_graphic.svg", svg(1024, 500, feature))
print("done")
