"""Build the Baked Pasta logo set: mark, lockups (light/dark) and the GitHub social preview.

The wordmark is set in Fraunces (SIL Open Font License) and converted to outlines, so the
SVGs need no font. Usage, from the repo root:

    python3 -m venv /tmp/logo-venv && /tmp/logo-venv/bin/pip install fonttools
    curl -fLo /tmp/Fraunces.ttf 'https://github.com/google/fonts/raw/main/ofl/fraunces/Fraunces%5BSOFT,WONK,opsz,wght%5D.ttf'
    FRAUNCES_TTF=/tmp/Fraunces.ttf /tmp/logo-venv/bin/python scripts/logo/build_logo.py
    rsvg-convert assets/logo/social-preview.svg -o assets/logo/social-preview.png
"""
import json, os, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FONT = Path(os.environ["FRAUNCES_TTF"])
OUT = HERE.parent.parent / "assets" / "logo"
OUT.mkdir(parents=True, exist_ok=True)

GREEN, TOMATO, GOLD, GOLD_END = "#14302B", "#D9481C", "#F2B544", "#FBE3A6"
CREAM = "#F6ECDC"


def outline(text, size, wght=720):
    r = subprocess.run([sys.executable, "-I", str(HERE / "outline.py"), str(FONT), text, str(size), str(wght), "0"],
                       capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


def mark(dish=GREEN, line=GREEN, hole=GREEN, uid="z"):
    """The mark's drawing on a 64x64 grid (no <svg> wrapper)."""
    return f'''<defs><g id="{uid}">
<path d="M0 -7 H20 A4 7 0 0 1 20 7 H0 Z" fill="{GOLD}" stroke="{line}" stroke-width="2.75" stroke-linejoin="round"/>
<ellipse rx="4" ry="7" fill="{GOLD_END}" stroke="{line}" stroke-width="2.75"/>
<ellipse rx="1.8" ry="3.7" fill="{hole}"/>
</g></defs>
<use href="#{uid}" transform="translate(22 17) rotate(-12)"/>
<path d="M27 12.6 Q33 10.8 39 9.6 Q42 9 42.5 11 Q43 13 41 14 Q40 16.5 38.5 15.5 Q37.5 14.8 36 15.6 Q33 18 31.5 16 Q30 15 28.6 16.4 Q26.5 17.5 26.3 15 Z" fill="{TOMATO}"/>
<use href="#{uid}" transform="translate(8 28) rotate(4)"/>
<use href="#{uid}" transform="translate(56 28) scale(-1 1) rotate(4)"/>
<path d="M4 36 Q4 31 9 32 Q14 33 17 30.5 Q20 28 23 31 Q26 34 30 30.5 Q33 28 36 31 Q39 34 42 31 Q45 28 48 30.5 Q51 33 55 32 Q60 31 60 36 Z" fill="{TOMATO}"/>
<rect class="dish" x="1" y="35" width="62" height="7" rx="3.5" fill="{dish}"/>
<path class="dish" d="M7 41 H57 L54 52 Q52.8 56 48.8 56 H15.2 Q11.2 56 10 52 Z" fill="{dish}"/>'''


def svg(view_w, view_h, body, label="Baked Pasta"):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {view_w:g} {view_h:g}" role="img" '
            f'aria-label="{label}">{body}</svg>\n')


def write(name, content):
    (OUT / name).write_text(content)


SIZE = 40
baked, pasta, space = outline("baked", SIZE), outline("pasta", SIZE), outline("a a", SIZE)["width"] - 2 * outline("a", SIZE)["width"]


def wordmark(x, baseline, word_color, accent=TOMATO, scale=1.0):
    gap = space * 0.9
    return (f'<g transform="translate({x:g} {baseline:g}) scale({scale:g})">'
            f'<path d="{baked["d"]}" fill="{word_color}"/>'
            f'<path transform="translate({baked["width"] + gap:.2f} 0)" d="{pasta["d"]}" fill="{accent}"/></g>'), \
        (baked["width"] + gap + pasta["width"]) * scale


# Mark
write("baked-pasta-mark.svg", svg(64, 64, mark()))
write("baked-pasta-mark-on-dark.svg", svg(64, 64, mark(dish=CREAM)))

# Sandbox portal (menu/): its header is always dark; the tab icon follows the OS theme.
MENU = OUT.parent.parent / "menu"
(MENU / "logo.svg").write_text(svg(64, 64, mark(dish=CREAM)))
(MENU / "favicon.svg").write_text(svg(64, 64, f"<style>@media (prefers-color-scheme: dark){{.dish{{fill:{CREAM}}}}}</style>" + mark()))

# Lockups: mark + wordmark; the baseline sits so the x-height centres on the dish rim.
for name, word_color, dish in [("baked-pasta-lockup.svg", GREEN, GREEN), ("baked-pasta-lockup-on-dark.svg", CREAM, CREAM)]:
    words, w = wordmark(80, 44, word_color)
    write(name, svg(80 + w + 2, 64, mark(dish=dish) + words))

# GitHub social preview, 1280x640 with a 40px safe margin.
tag = outline("Everything ziti needs, layered and baked.", 30, wght=420)
sub = outline("Zero-trust demo environments built on OpenZiti", 22, wght=420)
words, w = wordmark(0, 0, GREEN, scale=2.2)
mark_px = 300
text_w = max(wordmark(0, 0, GREEN, scale=2.2)[1], tag["width"], sub["width"])
left = round((1280 - (mark_px + 56 + text_w)) / 2)
text_x = left + mark_px + 56
body = (f'<rect width="1280" height="640" fill="{CREAM}"/>'
        f'<rect x="0" y="616" width="1280" height="24" fill="{GREEN}"/>'
        f'<g transform="translate({left} 150) scale({mark_px / 64:g})">{mark()}</g>'
        f'<g transform="translate({text_x} 300)">{words}</g>'
        f'<path transform="translate({text_x + 4} 368)" d="{tag["d"]}" fill="{GREEN}"/>'
        f'<path transform="translate({text_x + 4} 412)" d="{sub["d"]}" fill="{GREEN}" opacity=".7"/>')
write("social-preview.svg", svg(1280, 640, body))
