"""Generate Plexify's app icons from one definition.

Run from the repo root:

    python tool/make_icons.py

Icons are checked in, because a build must not depend on Python being present.
The generator is checked in too, because a set of PNGs nobody can regenerate is
a set of PNGs nobody can change: the next time the accent colour moves, this is
the only thing that has to be edited.

The mark is the equaliser bars from the sign-in screen (Material's `graphic_eq`
recalled rather than copied), in the app's own accent, on the dark surface the
app actually paints. Four bars, not five: at 48px, five bars and their gaps
turn into a smudge.
"""

import os

from PIL import Image, ImageDraw

# The app's accent, from `PlexifyApp._theme`. Keep these in step.
ACCENT = (92, 156, 255, 255)
SURFACE = (16, 20, 27, 255)

# Bar heights, as a fraction of the mark's overall width, left to right.
# Uneven on purpose: evenly stepped bars read as a chart, not as sound.
BARS = (0.38, 0.78, 0.55, 1.00)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")


def draw_mark(size, colour, width_fraction):
    """The bars alone, centred on a transparent square of `size` pixels."""
    # 4x supersampling. Rounded caps at icon sizes alias badly otherwise, and
    # the launcher renders ic_launcher.png at 48dp without resampling help.
    scale = 4
    canvas = size * scale
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    mark_width = canvas * width_fraction
    bar = mark_width / (len(BARS) + (len(BARS) - 1) * 0.66)
    gap = bar * 0.66
    left = (canvas - mark_width) / 2
    centre = canvas / 2

    for i, height in enumerate(BARS):
        x = left + i * (bar + gap)
        half = mark_width * height / 2
        draw.rounded_rectangle(
            (x, centre - half, x + bar, centre + half),
            radius=bar / 2,
            fill=colour,
        )

    return img.resize((size, size), Image.LANCZOS)


def tile(size):
    """The full icon: mark on a rounded dark tile, for launchers that mask
    nothing themselves."""
    scale = 4
    canvas = size * scale
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle(
        (0, 0, canvas - 1, canvas - 1),
        # Roughly Android's own squircle radius. Exactness does not matter;
        # adaptive launchers re-mask this anyway.
        radius=canvas * 0.22,
        fill=SURFACE,
    )
    img = img.resize((size, size), Image.LANCZOS)
    img.alpha_composite(draw_mark(size, ACCENT, 0.62))
    return img


def write(path, img):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(os.path.relpath(path, ROOT))


def main():
    # Legacy launcher icon, 48dp at each density.
    for bucket, px in (
        ("mdpi", 48),
        ("hdpi", 72),
        ("xhdpi", 96),
        ("xxhdpi", 144),
        ("xxxhdpi", 192),
    ):
        write(os.path.join(RES, f"mipmap-{bucket}", "ic_launcher.png"), tile(px))

        # Adaptive layers are 108dp, of which only the middle 72dp is
        # guaranteed visible and only the middle 66dp is safe from every mask
        # shape. The mark is sized against that safe circle, not the canvas,
        # which is why this fraction is so much smaller than the tile's.
        big = px * 108 // 48
        write(
            os.path.join(RES, f"mipmap-{bucket}", "ic_launcher_foreground.png"),
            draw_mark(big, ACCENT, 0.40),
        )
        # Android 13 themed icons recolour this layer wholesale, so it has to
        # carry shape in its alpha and nothing in its colour.
        write(
            os.path.join(RES, f"mipmap-{bucket}", "ic_launcher_monochrome.png"),
            draw_mark(big, (255, 255, 255, 255), 0.40),
        )

    # Windows wants every size in one file; the taskbar and the alt-tab
    # switcher pick different ones.
    ico = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
    tile(256).save(
        ico,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(os.path.relpath(ico, ROOT))


if __name__ == "__main__":
    main()
