# Renders Klaro launcher/splash assets from the geometry in klaro-icon-handoff.md
# (matches klaro-k-enhanced.svg / klaro-k-mark.svg exactly).
# Run: python render_assets.py  -> writes PNGs into ../../assets/brand/
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "brand"))
os.makedirs(OUT, exist_ok=True)

SS = 4  # supersampling factor

# K paths on the 64-unit grid (from the SVGs): stem + two arms, joint at (22,32)
K_SEGMENTS = [((22, 16), (22, 48)), ((22, 32), (45, 17)), ((22, 32), (45, 49))]
STROKE_UNITS = 12.0

# Sheen lines (enhanced variant): thin highlights on upper-left edges
SHEEN_ENH = [((19.6, 18), (19.6, 46)), ((23.2, 30.2), (43, 16.8))]
SHEEN_ENH_W = 2.1
# Mark variant (transparent, for dark UI)
SHEEN_MARK = [((19.7, 17.5), (19.7, 46.5)), ((23, 30.5), (43.3, 16.7))]
SHEEN_MARK_W = 2.3


def draw_stroke(draw, segments, width_px, to_px, fill=255):
    """Stroke segments with round caps/joins (circle at every endpoint)."""
    r = width_px / 2.0
    for (a, b) in segments:
        ax, ay = to_px(a)
        bx, by = to_px(b)
        draw.line([(ax, ay), (bx, by)], fill=fill, width=max(1, round(width_px)))
        for (x, y) in ((ax, ay), (bx, by)):
            draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def k_mask(canvas_px, design_px, segments, width_units, offset_units=(0, 0)):
    """Grayscale (L) supersampled mask of the K stroke."""
    size = canvas_px * SS
    img = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(img)
    unit = design_px * SS / 64.0  # 64-unit grid scaled to design box
    origin = (size - design_px * SS) / 2.0  # design box centered on canvas

    def to_px(p):
        return (
            origin + (p[0] + offset_units[0]) * unit,
            origin + (p[1] + offset_units[1]) * unit,
        )

    draw_stroke(draw, segments, width_units * unit, to_px)
    return img


def linear_gradient(canvas_px, design_px, p1, p2, stops):
    """Linear gradient RGBA image. p1/p2 in the SVG's 512-space, stops [(t,hex)]."""
    size = canvas_px * SS
    scale = design_px * SS / 512.0
    origin = (size - design_px * SS) / 2.0
    x1, y1 = origin + p1[0] * scale, origin + p1[1] * scale
    x2, y2 = origin + p2[0] * scale, origin + p2[1] * scale
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    dx, dy = x2 - x1, y2 - y1
    t = ((xx - x1) * dx + (yy - y1) * dy) / (dx * dx + dy * dy)
    t = np.clip(t, 0.0, 1.0)
    ts = [s[0] for s in stops]
    cols = [tuple(int(s[1][i:i + 2], 16) for i in (1, 3, 5)) for s in stops]
    out = np.zeros((size, size, 4), dtype=np.uint8)
    out[..., 3] = 255
    for c in range(3):
        chan = np.interp(t, ts, [col[c] for col in cols])
        out[..., c] = chan.astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def radial_gradient(size_px, center, radius, stops):
    """Radial gradient RGBA (stops: (t, hex, alpha0to1)). center/radius as fractions."""
    yy, xx = np.mgrid[0:size_px, 0:size_px].astype(np.float32)
    cx, cy, r = center[0] * size_px, center[1] * size_px, radius * size_px
    t = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    t = np.clip(t, 0.0, 1.0)
    ts = [s[0] for s in stops]
    cols = [tuple(int(s[1][i:i + 2], 16) for i in (1, 3, 5)) for s in stops]
    alphas = [s[2] * 255 for s in stops]
    out = np.zeros((size_px, size_px, 4), dtype=np.uint8)
    for c in range(3):
        out[..., c] = np.interp(t, ts, [col[c] for col in cols]).astype(np.uint8)
    out[..., 3] = np.interp(t, ts, alphas).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def tint(mask, rgba):
    solid = Image.new("RGBA", mask.size, rgba)
    out = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    out.paste(solid, (0, 0), mask)
    return out


def through_mask(gradient_img, mask):
    out = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    out.paste(gradient_img, (0, 0), mask)
    return out


def scale_alpha(img, factor):
    r, g, b, a = img.split()
    a = a.point(lambda v: int(v * factor))
    return Image.merge("RGBA", (r, g, b, a))


def render_mark(canvas_px, design_px, variant="enhanced", shadow=True):
    """Transparent K mark. variant: 'enhanced' (icon) or 'mark' (in-app dark UI)."""
    size = canvas_px * SS
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    face_mask = k_mask(canvas_px, design_px, K_SEGMENTS, STROKE_UNITS)

    if variant == "enhanced":
        fold_off, fold_is_grad = (1.15, 1.5), True
        face_stops = [(0.0, "#C2B6FF"), (0.52, "#7C66FF"), (1.0, "#3F6BFF")]
        face_p1, face_p2 = (150, 122), (372, 402)
        sheen, sheen_w, sheen_col, sheen_op = SHEEN_ENH, SHEEN_ENH_W, "#E6E1FF", 0.6
    else:
        fold_off, fold_is_grad = (1.8, 2.4), False
        face_stops = [(0.0, "#9A8CFF"), (1.0, "#3F6BFF")]
        face_p1, face_p2 = (160, 135), (372, 392)
        sheen, sheen_w, sheen_col, sheen_op = SHEEN_MARK, SHEEN_MARK_W, "#CFC9FF", 0.5

    if shadow:
        sh = k_mask(canvas_px, design_px, K_SEGMENTS, STROKE_UNITS)
        blur = 11 * (design_px * SS / 512.0)
        sh = sh.filter(ImageFilter.GaussianBlur(blur))
        dy = round(10 * (design_px * SS / 512.0))
        layer = tint(sh, (0x03, 0x03, 0x0F, int(0.6 * 255)))
        out.alpha_composite(layer, (0, dy))

    fold_mask = k_mask(canvas_px, design_px, K_SEGMENTS, STROKE_UNITS, fold_off)
    if fold_is_grad:
        fold_grad = linear_gradient(canvas_px, design_px, (180, 150), (372, 420),
                                    [(0.0, "#3C429A"), (1.0, "#171B4A")])
        out.alpha_composite(through_mask(fold_grad, fold_mask))
    else:
        out.alpha_composite(tint(fold_mask, (0x26, 0x30, 0x6E, 255)))

    face_grad = linear_gradient(canvas_px, design_px, face_p1, face_p2, face_stops)
    out.alpha_composite(through_mask(face_grad, face_mask))

    sheen_mask = k_mask(canvas_px, design_px, sheen, sheen_w)
    out.alpha_composite(scale_alpha(tint(sheen_mask, (*(int(sheen_col[i:i + 2], 16) for i in (1, 3, 5)), 255)), sheen_op))

    return out.resize((canvas_px, canvas_px), Image.LANCZOS)


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path)
    print("wrote", name, img.size)


# 1) Adaptive icon foreground: 1024, design box 80% => K (~70% of box) lands in safe zone
save(render_mark(1024, int(1024 * 0.80), "enhanced"), "icon_fg.png")

# 2) Adaptive icon background: tile + glow + vignette (full bleed square)
bg = Image.new("RGBA", (1024, 1024), "#0C0B14")
bg.alpha_composite(radial_gradient(1024, (0.5, 0.36), 0.62,
                                   [(0.0, "#352C8F", 0.95), (0.7, "#161334", 0.35), (1.0, "#0C0B14", 0.0)]))
bg.alpha_composite(radial_gradient(1024, (0.5, 0.5), 0.72,
                                   [(0.62, "#000000", 0.0), (1.0, "#000000", 0.45)]))
save(bg.convert("RGB"), "icon_bg.png")

# 3) Monochrome layer (Android 13+ themed icons): plain white K silhouette
mono_mask = k_mask(1024, int(1024 * 0.80), K_SEGMENTS, STROKE_UNITS).resize((1024, 1024), Image.LANCZOS)
save(tint(mono_mask, (255, 255, 255, 255)), "icon_mono.png")

# 4) Android 12+ native splash icon: 1152x1152, content within central 768 circle
save(render_mark(1152, 700, "enhanced"), "splash_mark_1152.png")

# 5) Pre-Android-12 splash image + in-app brand mark (transparent, dark-UI variant)
save(render_mark(512, 460, "mark", shadow=False), "klaro_mark.png")
