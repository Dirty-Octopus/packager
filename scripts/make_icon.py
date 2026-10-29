#!/usr/bin/env python3
"""Render the Packager app icon (1024px) without external assets."""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import math

S = 4                      # supersample factor
N = 1024 * S


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def linear_gradient(size, c0, c1, angle=45):
    w = h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    rad = math.radians(angle)
    t = (xx * math.cos(rad) + yy * math.sin(rad))
    t = (t - t.min()) / (t.max() - t.min())
    t = t[..., None]
    c0 = np.array(c0, dtype=np.float32)
    c1 = np.array(c1, dtype=np.float32)
    arr = c0 * (1 - t) + c1 * t
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def vertical_gradient(size, c0, c1):
    w, h = size
    yy = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    c0 = np.array(c0, dtype=np.float32)
    c1 = np.array(c1, dtype=np.float32)
    arr = c0[None, :] * (1 - yy) + c1[None, :] * yy
    arr = np.repeat(arr[:, None, :], w, axis=1)
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def pt(x, y):
    return (x * S, y * S)


def poly(draw, points, fill, outline=None, width=0):
    draw.polygon([(x * S, y * S) for x, y in points], fill=fill, outline=outline)


def blur_layer(layer, radius):
    return layer.filter(ImageFilter.GaussianBlur(radius * S))


def main():
    # ------------------------------------------------------------------ tile
    bg = linear_gradient(N, (78, 36, 218), (166, 96, 255), angle=42)
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32) / N
    # soft luminous corner, kept subtle so the violet stays saturated
    glow = np.clip(1.0 - np.sqrt((xx - 0.20) ** 2 + (yy - 0.12) ** 2) / 0.55, 0, 1) ** 2
    pink = np.clip(1.0 - np.sqrt((xx - 0.92) ** 2 + (yy - 0.90) ** 2) / 0.62, 0, 1) ** 2
    arr = np.array(bg, dtype=np.float32)
    arr = arr + glow[..., None] * np.array([26, 20, 22], dtype=np.float32)
    arr = arr + pink[..., None] * np.array([44, 18, 30], dtype=np.float32)
    bg = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")

    mask = rounded_mask(N, 228 * S)
    icon = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    icon.paste(bg, (0, 0), mask)

    # subtle top highlight rim
    rim = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim)
    rd.rounded_rectangle([3 * S, 3 * S, N - 4 * S, N - 4 * S], radius=226 * S,
                         outline=(255, 255, 255, 46), width=2 * S)
    icon = Image.alpha_composite(icon, Image.composite(rim, Image.new("RGBA", (N, N), (0, 0, 0, 0)), mask))

    # ------------------------------------------------------------------ shadow
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([250 * S, 755 * S, 774 * S, 845 * S], fill=(38, 20, 92, 110))
    shadow = blur_layer(shadow, 22)
    icon = Image.alpha_composite(icon, shadow)

    # ------------------------------------------------------------------ box body
    body = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    body_poly = [(292, 520), (732, 520), (732, 748), (720, 770), (304, 770), (292, 748)]
    # main body gradient
    body_grad = vertical_gradient((440 * S, 260 * S), (253, 251, 255), (232, 226, 246))
    bm = Image.new("L", (N, N), 0)
    ImageDraw.Draw(bm).rounded_rectangle([292 * S, 512 * S, 732 * S, 772 * S], radius=20 * S, fill=255)
    body.paste(body_grad, (292 * S, 512 * S), bm.crop((292 * S, 512 * S, 732 * S, 772 * S)))
    # right side shade
    shade = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shade).polygon(
        [(x * S, y * S) for x, y in [(660, 520), (732, 520), (732, 748), (720, 770), (648, 770)]],
        fill=(90, 68, 140, 26))
    body = Image.alpha_composite(body, shade)

    # opening (dark cavity)
    opening = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    od = ImageDraw.Draw(opening)
    od.ellipse([292 * S, 452 * S, 732 * S, 592 * S], fill=(47, 34, 78, 255))
    # inner gradient
    cav = vertical_gradient((440 * S, 140 * S), (92, 68, 130), (33, 23, 54))
    cm = Image.new("L", (N, N), 0)
    ImageDraw.Draw(cm).ellipse([292 * S, 452 * S, 732 * S, 592 * S], fill=255)
    opening = Image.composite(Image.new("RGBA", (N, N), (0, 0, 0, 0)), opening, Image.new("L", (N, N), 0))
    opening = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    opening.paste(cav, (292 * S, 452 * S), cm.crop((292 * S, 452 * S, 732 * S, 592 * S)))
    # inner shadow at top
    ish = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(ish).ellipse([292 * S, 438 * S, 732 * S, 560 * S], fill=(20, 12, 36, 90))
    ish = blur_layer(ish, 16)
    ish.putalpha(Image.composite(ish.getchannel("A"), Image.new("L", (N, N), 0), cm))
    opening = Image.alpha_composite(opening, ish)

    icon = Image.alpha_composite(icon, body)
    icon = Image.alpha_composite(icon, opening)

    # ------------------------------------------------------------------ back flap
    back = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    bd = ImageDraw.Draw(back)
    bd.polygon([pt(352, 468), pt(672, 468), pt(650, 366), pt(374, 366)],
               fill=(248, 245, 255, 255), outline=(222, 214, 240, 255))
    # crease
    bd.line([pt(352, 468), pt(672, 468)], fill=(205, 195, 228, 255), width=int(2.5 * S))
    bd.line([pt(374, 366), pt(650, 366)], fill=(255, 255, 255, 255), width=int(2 * S))
    icon = Image.alpha_composite(icon, back)

    # ------------------------------------------------------------------ side flaps
    flaps = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flaps)
    # left flap (folded outward/left)
    fd.polygon([pt(300, 528), pt(190, 586), pt(224, 664), pt(328, 606)],
               fill=(252, 250, 255, 255), outline=(223, 215, 241, 255))
    # right flap
    fd.polygon([pt(724, 528), pt(834, 586), pt(800, 664), pt(696, 606)],
               fill=(246, 242, 255, 255), outline=(219, 210, 238, 255))
    # crease shadows
    fd.line([pt(300, 528), pt(328, 606)], fill=(214, 205, 234, 255), width=int(2 * S))
    fd.line([pt(724, 528), pt(696, 606)], fill=(210, 201, 231, 255), width=int(2 * S))
    icon = Image.alpha_composite(icon, flaps)

    # ------------------------------------------------------------------ rim
    rim2 = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    r2 = ImageDraw.Draw(rim2)
    r2.ellipse([292 * S, 452 * S, 732 * S, 592 * S], outline=(255, 255, 255, 255), width=int(9 * S))
    r2.arc([292 * S, 452 * S, 732 * S, 592 * S], 200, 340, fill=(228, 221, 243, 255), width=int(3 * S))
    icon = Image.alpha_composite(icon, rim2)

    # ------------------------------------------------------------------ front flap
    front = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    fm = Image.new("L", (N, N), 0)
    flap = [(336, 574), (688, 574), (664, 672), (360, 672)]
    ImageDraw.Draw(fm).polygon([pt(x, y) for x, y in flap], fill=255)
    fg = vertical_gradient((360 * S, 104 * S), (255, 255, 255), (240, 233, 252))
    front.paste(fg, (332 * S, 570 * S), fm.crop((332 * S, 570 * S, 692 * S, 674 * S)))
    fdr = ImageDraw.Draw(front)
    fdr.polygon([pt(x, y) for x, y in flap], outline=(219, 210, 238, 255), width=int(1.6 * S))
    # fold shadow along top edge
    fsh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(fsh).polygon([pt(336, 574), pt(688, 574), pt(682, 594), pt(342, 594)],
                                fill=(75, 54, 118, 58))
    fsh = blur_layer(fsh, 7)
    front = Image.alpha_composite(front, fsh)
    # subtle bottom shade of flap
    fsh2 = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(fsh2).polygon([pt(360, 646), pt(664, 646), pt(664, 672), pt(360, 672)],
                                 fill=(116, 92, 158, 22))
    fsh2 = blur_layer(fsh2, 9)
    front = Image.alpha_composite(front, fsh2)
    icon = Image.alpha_composite(icon, front)

    # ------------------------------------------------------------------ small seam marks
    marks = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    md = ImageDraw.Draw(marks)
    # flap crease lines
    md.line([pt(360, 590), pt(360, 666)], fill=(226, 218, 241, 170), width=int(1.2 * S))
    md.line([pt(664, 590), pt(664, 666)], fill=(226, 218, 241, 170), width=int(1.2 * S))
    icon = Image.alpha_composite(icon, marks)

    # ------------------------------------------------------------------ finish
    icon = icon.resize((1024, 1024), Image.LANCZOS)
    icon.save("Resources/AppIcon.png")
    print("wrote Resources/AppIcon.png")


if __name__ == "__main__":
    main()
