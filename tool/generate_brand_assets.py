"""Generate portable launcher assets from the supplied final raster artwork.

Requires only Pillow. Canonical inputs live in assets/branding/source; generation
never reads Downloads or depends on the original external icon pack. The earlier
normalized book/ginkgo renderer is retained as the explicit generate_geometric_*
experiment below, not used for production launcher output.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Iterable, Sequence

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# --------------------------------------------------------------------------
# Palette
# --------------------------------------------------------------------------

TILE_TOP = "#FFFFFF"
TILE_BOTTOM = "#F4F9FF"

BOOK_LEFT_PAGE = "#31A5F8"
BOOK_RIGHT_TOP = "#2E90E5"
BOOK_RIGHT_BOTTOM = "#2089E7"
BOOK_TOP = "#3FB0FF"
BOOK_BOTTOM = "#1E8AE8"
BOOK_CREASE = "#1B72C8"
BOOK_SHADOW = "#12539F"

LEAF_BODY = "#D2D2DA"
LEAF_STEM = "#E9FAFF"
LEAF_HOTSPOT = "#FFFFFF"
LEAF_RIM_CORE = "#96E9F6"
LEAF_RIM_OUTER = "#7FE8F8"
LEAF_VEIN = "#E8FAFF"
LEAF_GLOW = "#9CF2FE"

# The supplied final raster pack uses a pure white launcher background.
LAUNCHER_BACKGROUND_TOP = "#FFFFFF"
LAUNCHER_BACKGROUND_BOTTOM = "#FFFFFF"

MASKABLE_MARK_SCALE = 0.78
ADAPTIVE_MARK_SCALE = 0.62
WINDOWS_ICON_SIZES = [
    (16, 16),
    (24, 24),
    (32, 32),
    (48, 48),
    (64, 64),
    (128, 128),
    (256, 256),
]

SUPERSAMPLE = 4096
S = SUPERSAMPLE - 1

# The reference tile is 628 x 632 pixels; geometry below is authored in that
# space and normalized against its own width/height so it maps onto a square.
REF_W = 628.0
REF_H = 632.0


def _rgb(value: str) -> tuple[int, int, int]:
    value = value.removeprefix("#")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def _mix(start: Sequence[int], end: Sequence[int], ratio: float) -> tuple[int, int, int]:
    ratio = min(1.0, max(0.0, ratio))
    return tuple(
        round(a + (b - a) * ratio) for a, b in zip(start, end)  # type: ignore[return-value]
    )


# --------------------------------------------------------------------------
# Geometry helpers
# --------------------------------------------------------------------------


def _n(x: float, y: float) -> tuple[float, float]:
    """Reference pixel coordinate to normalized icon fractions."""
    return (x / REF_W, y / REF_H)


def _px(points: Iterable[tuple[float, float]]) -> list[tuple[float, float]]:
    """Normalized fractions to supersampled pixels."""
    return [(x * S, y * S) for x, y in points]


def _catmull_rom(
    anchors: Sequence[tuple[float, float]], *, steps: int = 24, closed: bool = False
) -> list[tuple[float, float]]:
    """Smooth interpolation through anchors (deterministic Catmull-Rom)."""
    points: list[tuple[float, float]] = []
    count = len(anchors)
    if count < 3:
        return list(anchors)
    limit = count if closed else count - 1
    for index in range(limit):
        p0 = anchors[(index - 1) % count] if closed else anchors[max(0, index - 1)]
        p1 = anchors[index % count]
        p2 = anchors[(index + 1) % count]
        p3 = (
            anchors[(index + 2) % count]
            if closed
            else anchors[min(count - 1, index + 2)]
        )
        for step in range(steps):
            t = step / steps
            t2 = t * t
            t3 = t2 * t
            points.append(
                (
                    0.5
                    * (
                        2 * p1[0]
                        + (-p0[0] + p2[0]) * t
                        + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                        + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3
                    ),
                    0.5
                    * (
                        2 * p1[1]
                        + (-p0[1] + p2[1]) * t
                        + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                        + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3
                    ),
                )
            )
    if not closed:
        points.append(anchors[-1])
    return points


def _cubic(
    start: tuple[float, float],
    control_a: tuple[float, float],
    control_b: tuple[float, float],
    end: tuple[float, float],
    *,
    steps: int = 96,
) -> list[tuple[float, float]]:
    points = []
    for index in range(steps + 1):
        t = index / steps
        inverse = 1 - t
        points.append(
            (
                inverse**3 * start[0]
                + 3 * inverse**2 * t * control_a[0]
                + 3 * inverse * t**2 * control_b[0]
                + t**3 * end[0],
                inverse**3 * start[1]
                + 3 * inverse**2 * t * control_a[1]
                + 3 * inverse * t**2 * control_b[1]
                + t**3 * end[1],
            )
        )
    return points


def _join(*segments: Iterable[tuple[float, float]]) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for segment in segments:
        segment_points = list(segment)
        if points and segment_points and points[-1] == segment_points[0]:
            segment_points = segment_points[1:]
        points.extend(segment_points)
    return points


def _mask_polygon(
    points: Iterable[tuple[float, float]], size: int = SUPERSAMPLE
) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon(list(points), fill=255)
    return mask


def _vertical_gradient(
    size: int, top: Sequence[int], bottom: Sequence[int]
) -> Image.Image:
    """A smooth vertical gradient, built from a 1-pixel column for speed."""
    column = Image.new("RGB", (1, size))
    pixels = column.load()
    for y in range(size):
        pixels[0, y] = _mix(top, bottom, y / max(1, size - 1))
    return column.resize((size, size), Image.Resampling.NEAREST)


def _vertical_alpha(size: int, top: float, bottom: float) -> Image.Image:
    """A vertical alpha ramp, built from a 1-pixel column for speed."""
    column = Image.new("L", (1, size))
    pixels = column.load()
    for y in range(size):
        value = round(top + (bottom - top) * y / max(1, size - 1))
        pixels[0, y] = min(255, max(0, value))
    return column.resize((size, size), Image.Resampling.NEAREST)


def _tapered_stroke(
    curve: Sequence[tuple[float, float]],
    *,
    start_width: float,
    end_width: float,
    size: int = SUPERSAMPLE,
) -> Image.Image:
    """Mask of a stroke whose width tapers along a normalized polyline."""
    left: list[tuple[float, float]] = []
    right: list[tuple[float, float]] = []
    count = len(curve)
    for index, (x, y) in enumerate(curve):
        t = index / max(1, count - 1)
        if index == 0:
            nx, ny = curve[1][0] - x, curve[1][1] - y
        elif index == count - 1:
            nx, ny = x - curve[-2][0], y - curve[-2][1]
        else:
            nx, ny = (
                curve[index + 1][0] - curve[index - 1][0],
                curve[index + 1][1] - curve[index - 1][1],
            )
        length = math.hypot(nx, ny) or 1.0
        nx, ny = -ny / length, nx / length
        width = (start_width + (end_width - start_width) * t) * S / 2
        left.append((x * S + nx * width, y * S + ny * width))
        right.append((x * S - nx * width, y * S - ny * width))
    mask = _mask_polygon(left + right[::-1], size)
    # Round the two ends so the stroke reads as a tube, not a wedge.
    draw = ImageDraw.Draw(mask)
    for point, width in (
        (curve[0], start_width * S / 2),
        (curve[-1], end_width * S / 2),
    ):
        draw.ellipse(
            (
                point[0] * S - width,
                point[1] * S - width,
                point[0] * S + width,
                point[1] * S + width,
            ),
            fill=255,
        )
    return mask


def _soft_disc(
    size: int, centre: tuple[float, float], radius: float, *, strength: float = 1.0
) -> Image.Image:
    """A soft circular falloff mask, in normalized coordinates."""
    column_centre = (round(centre[0] * (size - 1)), round(centre[1] * (size - 1)))
    radius_px = max(1.0, radius * (size - 1))
    # Build small, then upscale: cheap and smooth.
    scale = 8
    small = size // scale
    disc = Image.new("L", (small, small), 0)
    ImageDraw.Draw(disc).ellipse(
        (
            column_centre[0] / scale - radius_px / scale,
            column_centre[1] / scale - radius_px / scale,
            column_centre[0] / scale + radius_px / scale,
            column_centre[1] / scale + radius_px / scale,
        ),
        fill=255,
    )
    disc = disc.filter(ImageFilter.GaussianBlur(radius_px / scale * 0.42))
    disc = disc.resize((size, size), Image.Resampling.BILINEAR)
    return disc.point(lambda value: round(value * strength))


def _outline_band(mask: Image.Image, *, width: float) -> Image.Image:
    """Return the outline of ``mask`` as a band roughly ``width`` pixels wide.

    The erosion is done at a reduced resolution: downscaling then upscaling a
    binary mask with BOX resampling shrinks it by the scale factor, which is both
    correct at icon scale and far cheaper than a 4096px morphological filter.
    """
    size = mask.size[0]
    radius = max(1, round(width / 2))
    small = max(8, size // max(2, radius))
    shrunk = mask.resize((small, small), Image.Resampling.BOX)
    eroded = shrunk.point(lambda value: 255 if value >= 250 else 0)
    eroded = eroded.resize((size, size), Image.Resampling.BILINEAR)
    band = ImageChops.subtract(mask, eroded.point(lambda value: 255 if value >= 128 else 0))
    return band.filter(ImageFilter.GaussianBlur(max(0.5, width * 0.10)))


# --------------------------------------------------------------------------
# Book
# --------------------------------------------------------------------------

BOOK_LEFT = 76.0
BOOK_RIGHT = 551.0
BOOK_TOP_EDGE = 142.0
BOOK_BOTTOM_EDGE = 482.0
BOOK_RADIUS = 28.0
BOOK_NOTCH_DEPTH = 46.0
BOOK_NOTCH_HALF = 105.0

# Measured bottom-edge profile of the right page (reference pixels).
BOOK_NOTCH_RIGHT = [
    (420.0, 482.0),
    (400.0, 484.0),
    (380.0, 487.0),
    (360.0, 492.0),
    (345.0, 497.0),
    (333.0, 504.0),
    (325.0, 512.0),
    (319.0, 520.0),
    (315.5, 527.0),
    (314.0, 529.5),
]


def _book_body_path() -> list[tuple[float, float]]:
    """Rounded rectangle with the soft downward V notch in the bottom centre."""
    left, right = BOOK_LEFT, BOOK_RIGHT
    top, bottom = BOOK_TOP_EDGE, BOOK_BOTTOM_EDGE
    radius = BOOK_RADIUS
    mid = (left + right) / 2.0

    def corner(cx: float, cy: float, start: float, end: float) -> list[tuple[float, float]]:
        points = []
        for index in range(65):
            angle = math.radians(start + (end - start) * index / 64)
            points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
        return points

    right_notch = _catmull_rom(BOOK_NOTCH_RIGHT, steps=16)
    left_notch = [(2 * mid - x, y) for x, y in reversed(right_notch)]

    outline = _join(
        corner(left + radius, top + radius, 180, 270),
        corner(right - radius, top + radius, 270, 360),
        corner(right - radius, bottom - radius, 0, 90),
        right_notch,
        left_notch,
        corner(left + radius, bottom - radius, 90, 180),
    )
    return [_n(x, y) for x, y in outline]


def _render_book(size: int = SUPERSAMPLE) -> Image.Image:
    """RGBA book layer with page split, centre crease and top gloss."""
    outline = _px(_book_body_path())
    mask = _mask_polygon(outline, size)

    body = _vertical_gradient(size, _rgb(BOOK_TOP), _rgb(BOOK_BOTTOM))

    # The left page is flat azure; the right page carries the vertical gradient.
    split = Image.new("L", (size, size), 0)
    ImageDraw.Draw(split).rectangle((0, 0, size // 2, size), fill=255)
    body = Image.composite(
        Image.new("RGB", (size, size), _rgb(BOOK_LEFT_PAGE)), body, split
    )
    body = Image.composite(
        _vertical_gradient(size, _rgb(BOOK_RIGHT_TOP), _rgb(BOOK_RIGHT_BOTTOM)),
        body,
        ImageChops.invert(split),
    )

    # Soft darker crease where the two pages meet.
    crease_half = 0.0060 * S
    crease = Image.new("L", (size, size), 0)
    ImageDraw.Draw(crease).rectangle(
        (size / 2 - crease_half, 0, size / 2 + crease_half, size), fill=255
    )
    crease = crease.filter(ImageFilter.GaussianBlur(crease_half * 1.6))
    body = Image.composite(
        Image.new("RGB", (size, size), _rgb(BOOK_CREASE)),
        body,
        crease.point(lambda value: value * 105 // 255),
    )

    layer = body.convert("RGBA")
    layer.putalpha(mask)

    # Glossy sheen across the top of both pages, clipped to the book.
    sheen = _soft_disc(size, (0.5, 0.150), 0.30, strength=0.42)
    sheen_layer = Image.new("RGBA", (size, size), (*_rgb("#63BEFF"), 0))
    sheen_layer.putalpha(ImageChops.multiply(sheen, mask))
    layer = Image.alpha_composite(layer, sheen_layer)
    return layer


# --------------------------------------------------------------------------
# Ginkgo leaf
# --------------------------------------------------------------------------

# Veins converge here; the blade fans out from this point.
LEAF_BASE = _n(305.0, 345.0)
# Where the blade tapers into the stem.
LEAF_NECK = _n(258.0, 388.0)

# Closed blade outline, clockwise from the neck (reference pixels).
BLADE_ANCHORS = [
    (258.0, 388.0),
    (248.0, 380.0),
    (261.0, 360.0),
    (271.0, 340.0),
    (276.0, 316.0),
    (275.0, 292.0),
    (268.0, 264.0),
    (255.0, 236.0),
    (237.0, 208.0),
    (216.0, 176.0),
    (206.0, 156.0),
    (203.0, 144.0),
    (203.0, 136.0),
    (210.0, 126.0),
    (222.0, 118.0),
    (238.0, 113.0),
    (252.0, 110.0),
    (266.0, 102.0),
    (280.0, 96.0),
    (294.0, 93.0),
    (308.0, 94.0),
    (322.0, 98.0),
    (336.0, 102.0),
    (350.0, 105.0),
    (364.0, 106.0),
    (378.0, 105.0),
    (392.0, 106.0),
    (405.0, 111.0),
    (416.0, 119.0),
    (424.0, 129.0),
    (427.0, 140.0),
    (421.0, 152.0),
    (414.0, 162.0),
    (409.0, 174.0),
    (405.0, 188.0),
    (404.0, 200.0),
    (408.0, 196.0),
    (416.0, 186.0),
    (426.0, 176.0),
    (438.0, 170.0),
    (452.0, 166.0),
    (466.0, 166.0),
    (478.0, 171.0),
    (487.0, 180.0),
    (492.0, 191.0),
    (495.0, 203.0),
    (496.0, 216.0),
    (497.0, 228.0),
    (500.0, 240.0),
    (506.0, 251.0),
    (513.0, 261.0),
    (518.0, 272.0),
    (520.0, 284.0),
    (518.0, 296.0),
    (514.0, 308.0),
    (510.0, 320.0),
    (508.0, 331.0),
    (509.0, 341.0),
    (508.0, 353.0),
    (504.0, 365.0),
    (496.0, 374.0),
    (486.0, 379.0),
    (474.0, 379.0),
    (461.0, 375.0),
    (448.0, 370.0),
    (435.0, 364.0),
    (422.0, 358.0),
    (409.0, 352.0),
    (395.0, 347.0),
    (381.0, 344.0),
    (366.0, 342.0),
    (352.0, 342.0),
    (338.0, 344.0),
    (324.0, 347.0),
    (310.0, 353.0),
    (296.0, 361.0),
    (283.0, 371.0),
    (270.0, 380.0),
]

# Stem centreline, from the blade neck down to the rounded tip.
STEM_ANCHORS = [
    (258.0, 386.0),
    (249.0, 400.0),
    (238.0, 416.0),
    (228.0, 432.0),
    (218.0, 448.0),
    (210.0, 464.0),
    (203.0, 481.0),
    (198.0, 498.0),
    (195.0, 515.0),
    (193.0, 532.0),
    (193.0, 549.0),
    (195.0, 562.0),
]

STEM_START_WIDTH = 0.043
STEM_END_WIDTH = 0.032

# Vein fan: angle from vertical, in degrees (negative is to the left).
VEIN_ANGLES = (-64.0, -46.0, -28.0, -10.0, 8.0, 26.0, 44.0, 62.0, 80.0)


def _scallop(angle_deg: float) -> float:
    """Subtle inward wobble that breaks the blade edge into soft lobes."""
    phase = (angle_deg + 180.0) / 360.0 * 2 * math.pi
    return 1.0 - 0.010 * (0.5 + 0.5 * math.sin(phase * 9 - math.pi / 2))


def _blade_outline() -> list[tuple[float, float]]:
    """Smoothed closed blade outline in normalized fractions."""
    points = _catmull_rom(BLADE_ANCHORS, steps=14, closed=True)
    base_x, base_y = 305.0, 345.0
    wobbled: list[tuple[float, float]] = []
    for x, y in points:
        dx, dy = x - base_x, y - base_y
        distance = math.hypot(dx, dy) or 1.0
        angle = math.degrees(math.atan2(dx, -dy))
        scale = _scallop(angle)
        wobbled.append((base_x + dx * scale, base_y + dy * scale))
    return [_n(x, y) for x, y in wobbled]


def _stem_curve() -> list[tuple[float, float]]:
    points = _catmull_rom(STEM_ANCHORS, steps=16)
    return [_n(x, y) for x, y in points]


def _leaf_masks(size: int = SUPERSAMPLE) -> tuple[Image.Image, Image.Image]:
    """Return (blade mask, stem mask)."""
    blade = _mask_polygon(_px(_blade_outline()), size)
    stem = _tapered_stroke(
        _stem_curve(), start_width=STEM_START_WIDTH, end_width=STEM_END_WIDTH, size=size
    )
    return blade, stem


def _vein_lines() -> list[list[tuple[float, float]]]:
    """Radiating veins fanning from the blade base toward the scalloped edge."""
    base_x, base_y = LEAF_BASE
    tip_x, tip_y = LEAF_NECK
    lines = []
    for angle_deg in VEIN_ANGLES:
        radians = math.radians(angle_deg)
        direction = (math.sin(radians), -math.cos(radians))
        # How far the blade reaches along this ray.
        reach = 0.0
        for step in range(1, 200):
            distance = step / 200.0 * 0.42
            probe = (base_x + direction[0] * distance, base_y + direction[1] * distance)
            if _inside_blade(probe):
                reach = distance
        if reach == 0.0:
            continue
        end = (base_x + direction[0] * reach * 0.90, base_y + direction[1] * reach * 0.90)
        bend = (
            base_x + direction[0] * reach * 0.34,
            base_y + direction[1] * reach * 0.30,
        )
        lines.append(_cubic((tip_x, tip_y - 0.012), bend, bend, end, steps=72))
    return lines


_BLADE_INSIDE: list[tuple[float, float]] | None = None


def _inside_blade(point: tuple[float, float]) -> bool:
    """Even-odd point-in-polygon test against the blade outline."""
    global _BLADE_INSIDE
    if _BLADE_INSIDE is None:
        _BLADE_INSIDE = _blade_outline()
    x, y = point
    inside = False
    count = len(_BLADE_INSIDE)
    for index in range(count):
        x0, y0 = _BLADE_INSIDE[index]
        x1, y1 = _BLADE_INSIDE[(index + 1) % count]
        if (y0 > y) != (y1 > y):
            intersect = x0 + (y - y0) * (x1 - x0) / (y1 - y0)
            if x < intersect:
                inside = not inside
    return inside


def _render_leaf(size: int = SUPERSAMPLE) -> Image.Image:
    """RGBA leaf layer: soft shadow, glow, milky body, veins and rim light."""
    blade_mask, stem_mask = _leaf_masks(size)
    body_mask = ImageChops.lighter(blade_mask, stem_mask)

    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # --- soft contact shadow so the milky body reads as glass over the book --
    shadow = body_mask.filter(ImageFilter.GaussianBlur(0.012 * S))
    shadow_layer = Image.new("RGBA", (size, size), (*_rgb(BOOK_SHADOW), 0))
    shadow_layer.putalpha(shadow.point(lambda value: value * 46 // 255))
    layer = Image.alpha_composite(layer, shadow_layer)

    # --- outer cyan glow bleeding onto the blue -----------------------------
    glow = body_mask.filter(ImageFilter.GaussianBlur(0.020 * S))
    glow_layer = Image.new("RGBA", (size, size), (*_rgb(LEAF_GLOW), 0))
    glow_layer.putalpha(glow.point(lambda value: value * 120 // 255))
    layer = Image.alpha_composite(layer, glow_layer)

    # --- wide, softened rim -------------------------------------------------
    rim_outer = _outline_band(body_mask, width=0.0115 * S)
    rim_outer = rim_outer.filter(ImageFilter.GaussianBlur(0.0034 * S))
    rim_outer_layer = Image.new("RGBA", (size, size), (*_rgb(LEAF_RIM_OUTER), 0))
    rim_outer_layer.putalpha(rim_outer.point(lambda value: value * 185 // 255))
    layer = Image.alpha_composite(layer, rim_outer_layer)

    # --- veins, under the body so they read as internal structure -----------
    veins = Image.new("L", (size, size), 0)
    vein_draw = ImageDraw.Draw(veins)
    for line in _vein_lines():
        vein_draw.line(
            _px(line), fill=255, width=max(1, round(0.0052 * S)), joint="curve"
        )
    veins = ImageChops.multiply(veins, blade_mask)
    veins = veins.filter(ImageFilter.GaussianBlur(0.0030 * S))
    vein_layer = Image.new("RGBA", (size, size), (*_rgb(LEAF_VEIN), 0))
    vein_layer.putalpha(veins.point(lambda value: value * 205 // 255))
    layer = Image.alpha_composite(layer, vein_layer)

    # --- milky body ---------------------------------------------------------
    # A neutral body at ~0.7 alpha over the blue book reproduces the reference's
    # frosted look; the alpha fades toward the bottom of the blade.
    body = Image.new("RGB", (size, size), _rgb(LEAF_BODY))
    milk = body.convert("RGBA")
    alpha = _vertical_alpha(size, 200, 146)
    alpha = ImageChops.multiply(alpha, body_mask)
    milk.putalpha(alpha)
    layer = Image.alpha_composite(layer, milk)

    # The stem is a paler, brighter glass tube than the blade.
    stem_only = ImageChops.subtract(stem_mask, blade_mask)
    stem_fill = Image.new("RGBA", (size, size), (*_rgb(LEAF_STEM), 186))
    stem_fill.putalpha(ImageChops.multiply(stem_fill.getchannel("A"), stem_only))
    layer = Image.alpha_composite(layer, stem_fill)

    # --- bright frosted hotspot near the top of the blade -------------------
    hotspot = _soft_disc(size, (0.488, 0.232), 0.088)
    hotspot_layer = Image.new("RGBA", (size, size), (*_rgb(LEAF_HOTSPOT), 0))
    hotspot_layer.putalpha(
        ImageChops.multiply(hotspot.point(lambda value: value * 215 // 255), blade_mask)
    )
    layer = Image.alpha_composite(layer, hotspot_layer)

    # --- crisp rim ----------------------------------------------------------
    rim_core = _outline_band(body_mask, width=0.0115 * S)
    rim_core = rim_core.filter(ImageFilter.GaussianBlur(0.0026 * S))
    rim_core_layer = Image.new("RGBA", (size, size), (*_rgb(LEAF_RIM_CORE), 0))
    rim_core_layer.putalpha(rim_core.point(lambda value: value * 255 // 255))
    layer = Image.alpha_composite(layer, rim_core_layer)

    return layer


# --------------------------------------------------------------------------
# Master composition
# --------------------------------------------------------------------------


def _scale_layer(layer: Image.Image, scale: float, size: int) -> Image.Image:
    """Scale a supersampled layer about the canvas centre."""
    if scale == 1.0:
        return layer
    scaled = max(1, round(size * scale))
    resized = layer.resize((scaled, scaled), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - scaled) // 2
    canvas.paste(resized, (offset, offset))
    return canvas


def _render_tile(*, mark_scale: float = 1.0) -> Image.Image:
    """Full-bleed tile carrying the book and the ginkgo leaf.

    The artwork is deliberately edge-to-edge and fully opaque: the rounded
    corners in the reference screenshot are applied by the launcher's mask, not
    drawn here. Platforms that need a cut-out shape (round launcher icons) mask
    the finished icon themselves, and Android's adaptive icon gets a separate
    transparent foreground.
    """
    size = SUPERSAMPLE
    book = _scale_layer(_render_book(size), mark_scale, size)
    leaf = _scale_layer(_render_leaf(size), mark_scale, size)

    tile = _vertical_gradient(size, _rgb(TILE_TOP), _rgb(TILE_BOTTOM)).convert("RGBA")
    canvas = Image.alpha_composite(tile, book)
    canvas = Image.alpha_composite(canvas, leaf)
    return canvas


def _mark_layer() -> Image.Image:
    """The book and leaf alone, without the white tile plate."""
    if "mark" not in _MASTER:
        size = SUPERSAMPLE
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        layer = Image.alpha_composite(layer, _render_book(size))
        layer = Image.alpha_composite(layer, _render_leaf(size))
        _MASTER["mark"] = layer
    return _MASTER["mark"]


_MASTER: dict[str, Image.Image] = {}


def _master() -> Image.Image:
    if "master" not in _MASTER:
        _MASTER["master"] = _render_tile(mark_scale=1.0)
    return _MASTER["master"]


def _resize(image: Image.Image, size: int) -> Image.Image:
    return image.resize((size, size), Image.Resampling.LANCZOS)


def generate_geometric_icon(size: int) -> Image.Image:
    """Return the retained experimental book/ginkgo tile, not the final artwork.

    The result is fully opaque: the tile reaches every edge so launchers can
    apply their own corner mask without exposing transparency.
    """
    if size <= 0:
        raise ValueError("size must be positive")
    icon = _resize(_master(), size)
    icon.putalpha(Image.new("L", icon.size, 255))
    return icon


SOURCE_DIRECTORY = Path(__file__).resolve().parents[1] / "assets/branding/source"


def _source_image(filename: str) -> Image.Image:
    """Load an independently portable, verified-size canonical PNG."""
    with Image.open(SOURCE_DIRECTORY / filename) as image:
        image.load()
        expected_mode = "RGB" if filename == "app_icon_1024.png" else "RGBA"
        if image.size != (1024, 1024) or image.mode != expected_mode:
            raise ValueError(f"Invalid canonical launcher input: {filename}")
        return image.copy()


def generate_icon(size: int) -> Image.Image:
    """Return the final diagonal-feather artwork on its opaque white tile."""
    if size <= 0:
        raise ValueError("size must be positive")
    return _resize(_source_image("app_icon_1024.png"), size).convert("RGBA")


def generate_geometric_maskable_icon(size: int) -> Image.Image:
    """Return the experimental ginkgo mark inside the maskable safe circle."""
    if size <= 0:
        raise ValueError("size must be positive")
    icon = _resize(_render_tile(mark_scale=MASKABLE_MARK_SCALE), size)
    icon.putalpha(Image.new("L", icon.size, 255))
    return icon


def generate_geometric_adaptive_foreground(size: int = 432) -> Image.Image:
    """Return the experimental ginkgo mark in Android's central safe zone."""
    if size <= 0:
        raise ValueError("size must be positive")
    return _resize(_scale_layer(_mark_layer(), ADAPTIVE_MARK_SCALE, SUPERSAMPLE), size)


def _raster_tile(mark_scale: float, size: int) -> Image.Image:
    """Centre the supplied transparent mark on white before final downsampling."""
    mark = _scale_layer(_source_image("logo_transparent.png"), mark_scale, 1024)
    tile = Image.new("RGBA", (1024, 1024), (255, 255, 255, 255))
    return _resize(Image.alpha_composite(tile, mark), size)


def generate_maskable_icon(size: int) -> Image.Image:
    """Keep the feather and book inside Web's central 80%-diameter circle."""
    if size <= 0:
        raise ValueError("size must be positive")
    # The supplied transparent mark already includes its own framing. At 72%
    # its alpha>=8 silhouette has radius <38% (Web requires <=40%).
    return _raster_tile(0.72, size)


def generate_adaptive_foreground(size: int = 432) -> Image.Image:
    """Resize the supplied Android foreground, preserving its existing inset."""
    if size <= 0:
        raise ValueError("size must be positive")
    return _resize(_source_image("android_foreground.png"), size)


def generate_monochrome_foreground(size: int = 432) -> Image.Image:
    """Return the supplied white silhouette for Android 13 themed icons."""
    if size <= 0:
        raise ValueError("size must be positive")
    return _resize(_source_image("android_monochrome.png"), size)


def _round_icon(size: int) -> Image.Image:
    # The ordinary square artwork exceeds a circular crop. Reframe the supplied
    # transparent mark so even its feather tip has room before applying the mask.
    icon = _raster_tile(0.90, size)
    supersample = 4
    mask = Image.new("L", (size * supersample, size * supersample), 0)
    ImageDraw.Draw(mask).ellipse(
        (0, 0, size * supersample - 1, size * supersample - 1), fill=255
    )
    icon.putalpha(mask.resize((size, size), Image.Resampling.LANCZOS))
    return icon


def _save(image: Image.Image, path: Path, *, opaque: bool = False) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = image.convert("RGB") if opaque else image
    image.save(path, optimize=True)
    return path


def _save_opaque_icon(size: int, path: Path) -> Path:
    if size == 1024:
        # Preserve the supplied final PNG byte for byte at its native size.
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes((SOURCE_DIRECTORY / "app_icon_1024.png").read_bytes())
        return path
    return _save(generate_icon(size), path, opaque=True)


def _ios_app_icon_sizes(directory: Path) -> dict[str, int]:
    metadata_path = directory / "Contents.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    sizes: dict[str, int] = {}
    for entry in metadata["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        if (
            not isinstance(filename, str)
            or "/" in filename
            or "\\" in filename
            or ":" in filename
            or not filename.endswith(".png")
        ):
            raise ValueError(f"Expected an iOS icon PNG filename, not a path: {filename}")
        scale = float(entry["scale"].removesuffix("x"))
        width, height = (
            round(float(value) * scale) for value in entry["size"].split("x")
        )
        if width != height or width <= 0:
            raise ValueError(f"Expected positive square iOS icon metadata: {entry}")
        existing = sizes.get(filename)
        if existing is not None and existing != width:
            raise ValueError(f"Conflicting iOS icon metadata for {filename}")
        sizes[filename] = width
    return sizes


def _launcher_colors_xml(path: Path) -> str:
    """Update only launcher colors, preserving other values and XML comments."""
    if path.exists():
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
        resources = ET.fromstring(path.read_text(encoding="utf-8"), parser=parser)
        if resources.tag != "resources":
            raise ValueError(f"Expected Android resources XML: {path}")
    else:
        resources = ET.Element("resources")
    for name, value in (
        ("ic_launcher_background_top", LAUNCHER_BACKGROUND_TOP),
        ("ic_launcher_background_bottom", LAUNCHER_BACKGROUND_BOTTOM),
    ):
        matches = resources.findall(f"color[@name='{name}']")
        if len(matches) > 1:
            raise ValueError(f"Duplicate launcher color: {name}")
        entry = matches[0] if matches else ET.SubElement(resources, "color", name=name)
        entry.text = value
    ET.indent(resources, space="    ")
    return '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(resources, encoding="unicode") + "\n"


def write_all_assets(project_root: Path) -> list[Path]:
    project_root = project_root.resolve()
    # Resolve the metadata-driven targets before replacing any existing icon.
    # A broken AppIcon catalog must not leave the other platforms half updated.
    ios_directory = (
        project_root / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    )
    ios_sizes = _ios_app_icon_sizes(ios_directory)
    android_res = project_root / "android" / "app" / "src" / "main" / "res"
    colors = android_res / "values" / "colors.xml"
    colors_xml = _launcher_colors_xml(colors)
    for filename in (
        "app_icon_1024.png", "logo_transparent.png",
        "android_foreground.png", "android_monochrome.png",
    ):
        _source_image(filename)
    written: list[Path] = []

    master = generate_icon(1024)
    branding = project_root / "assets" / "branding"
    written.append(_save_opaque_icon(1024, branding / "icon-master.png"))
    written.append(_save(generate_icon(32), branding / "icon-32.png"))
    written.append(_save(generate_icon(16), branding / "icon-16.png"))

    web_targets = {
        "favicon.png": generate_icon(16),
        "icons/Icon-192.png": generate_icon(192),
        "icons/Icon-512.png": generate_icon(512),
        "icons/Icon-maskable-192.png": generate_maskable_icon(192),
        "icons/Icon-maskable-512.png": generate_maskable_icon(512),
    }
    for relative, image in web_targets.items():
        written.append(_save(image, project_root / "web" / relative))

    android_sizes = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for density, size in android_sizes.items():
        directory = android_res / f"mipmap-{density}"
        written.append(_save(generate_icon(size), directory / "ic_launcher.png"))
        written.append(_save(_round_icon(size), directory / "ic_launcher_round.png"))
    written.append(
        _save(
            generate_adaptive_foreground(),
            android_res / "drawable-nodpi" / "ic_launcher_foreground.png",
        )
    )
    written.append(
        _save(
            generate_monochrome_foreground(),
            android_res / "drawable-nodpi" / "ic_launcher_monochrome.png",
        )
    )

    colors.parent.mkdir(parents=True, exist_ok=True)
    colors.write_text(colors_xml, encoding="utf-8")
    written.append(colors)

    background = android_res / "drawable" / "ic_launcher_background.xml"
    background.parent.mkdir(parents=True, exist_ok=True)
    background.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android" '
        'android:shape="rectangle">\n'
        "    <gradient\n"
        '        android:angle="270"\n'
        '        android:startColor="@color/ic_launcher_background_top"\n'
        '        android:endColor="@color/ic_launcher_background_bottom" />\n'
        "</shape>\n",
        encoding="utf-8",
    )
    written.append(background)

    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n"
    )
    for version in (26, 33):
        version_xml = adaptive
        if version == 33:
            version_xml = adaptive.replace(
                "</adaptive-icon>",
                '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
                "</adaptive-icon>",
            )
        for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
            path = android_res / f"mipmap-anydpi-v{version}" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(version_xml, encoding="utf-8")
            written.append(path)

    for filename, size in sorted(ios_sizes.items()):
        written.append(_save_opaque_icon(size, ios_directory / filename))

    windows_icon = project_root / "windows" / "runner" / "resources" / "app_icon.ico"
    windows_icon.parent.mkdir(parents=True, exist_ok=True)
    master.save(windows_icon, format="ICO", sizes=WINDOWS_ICON_SIZES)
    written.append(windows_icon)
    return written


def check_assets(project_root: Path) -> None:
    """Check every generated byte, including layer XML, without changing the app."""
    project_root = project_root.resolve()
    with tempfile.TemporaryDirectory() as directory:
        expected_root = Path(directory)
        # Generation needs the project's slot table and must preserve any shared
        # Android colors. Everything else is recreated only in this temp folder.
        for relative in (
            Path("ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"),
            Path("android/app/src/main/res/values/colors.xml"),
        ):
            source = project_root / relative
            if source.is_file():
                destination = expected_root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
        expected_paths = write_all_assets(expected_root)
        for expected in expected_paths:
            actual = project_root / expected.relative_to(expected_root)
            if not actual.is_file() or actual.read_bytes() != expected.read_bytes():
                raise SystemExit(f"Missing or stale launcher asset: {actual}")
    print(f"Verified all {len(expected_paths)} launcher assets against canonical inputs.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate 阅读 launcher icons from the supplied final raster artwork."
    )
    parser.add_argument(
        "--check", action="store_true", help="validate every generated launcher file"
    )
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    if args.check:
        check_assets(args.root)
    else:
        paths = write_all_assets(args.root)
        print(f"Generated {len(paths)} 阅读 launcher assets.")


if __name__ == "__main__":
    main()
