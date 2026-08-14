"""Generate the Android status-bar notification icon at every density.

Android does not draw this icon, it draws its *alpha*: the system fills the
opaque pixels with its own colour (white on the status bar, the accent colour
in the shade) and throws the RGB away. So the file has to be a white silhouette
on transparency — a coloured ball would come out looking identical, and a ball
on an opaque white square would come out as a solid block.

Dotto's mark is a ball, and a ball is the whole silhouette. The outline it has
in the game cannot survive here: at 24dp a ring reads as a smudge, and the
inside of it would be punched transparent.

Run: py scripts/make_notification_icon.py
"""

from PIL import Image, ImageDraw
from pathlib import Path

# Android's status bar icon is 24dp square at every density.
DENSITIES = {
    "mdpi": 24,
    "hdpi": 36,
    "xhdpi": 48,
    "xxhdpi": 72,
    "xxxhdpi": 96,
}

# Fraction of the canvas the ball fills. Android reserves a margin inside the
# 24dp box and will happily clip anything that fills it edge to edge; 5/6 keeps
# 2dp clear on each side, which is the documented optical padding.
BALL = 5 / 6

# Drawn this many times larger and scaled down, because PIL's ellipse has hard
# pixel edges. At 24px a jagged circle is obvious.
SUPERSAMPLE = 16

RES = Path(__file__).resolve().parent.parent / "android/app/src/main/res"


def ball(size: int) -> Image.Image:
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    inset = big * (1 - BALL) / 2
    # White, fully opaque: the colour is discarded, the alpha is the icon.
    d.ellipse([inset, inset, big - inset - 1, big - inset - 1],
              fill=(255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    for density, size in DENSITIES.items():
        out = RES / f"drawable-{density}" / "ic_notification.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        ball(size).save(out, "PNG")
        print(f"{out.relative_to(RES.parent.parent.parent.parent)} ({size}x{size})")


if __name__ == "__main__":
    main()
