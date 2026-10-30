"""Generate every launcher icon from one normalized geometric master.

Requires Pillow. The launcher uses a fixed local blue gradient and an original white
open-book/feather mark, sampled at high resolution for deterministic small assets.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw

LAUNCHER_BLUE_TOP = "#3AA9FF"
LAUNCHER_BLUE_BOTTOM = "#28A1FF"
LAUNCHER_WHITE = "#FFFFFF"

MASKABLE_MARK_SCALE = 0.82
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


def _rgb(value: str) -> tuple[int, int, int]:
    value = value.removeprefix("#")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def _vertical_gradient(size: int) -> Image.Image:
    top = _rgb(LAUNCHER_BLUE_TOP)
    bottom = _rgb(LAUNCHER_BLUE_BOTTOM)
    image = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(image)
    denominator = max(1, size - 1)
    for y in range(size):
        ratio = y / denominator
        color = tuple(
            round(start + (end - start) * ratio)
            for start, end in zip(top, bottom)
        )
        draw.line((0, y, size, y), fill=color)
    return image


def _cubic(
    start: tuple[float, float],
    control_a: tuple[float, float],
    control_b: tuple[float, float],
    end: tuple[float, float],
    *,
    steps: int = 36,
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


def _transform(
    points: Iterable[tuple[float, float]], scale: float
) -> list[tuple[float, float]]:
    return [
        (0.5 + (x - 0.5) * scale, 0.5 + (y - 0.5) * scale)
        for x, y in points
    ]


def _scaled(
    points: Iterable[tuple[float, float]], size: int
) -> list[tuple[int, int]]:
    return [(round(x * (size - 1)), round(y * (size - 1))) for x, y in points]


def _stroke(
    draw: ImageDraw.ImageDraw,
    points: Iterable[tuple[float, float]],
    size: int,
    *,
    width_ratio: float,
    scale: float,
) -> None:
    transformed = _transform(points, scale)
    pixels = _scaled(transformed, size)
    width = max(1, round(size * width_ratio * scale))
    draw.line(pixels, fill=_rgb(LAUNCHER_WHITE), width=width, joint="curve")

    radius = width / 2
    for x, y in (pixels[0], pixels[-1]):
        draw.ellipse(
            (x - radius, y - radius, x + radius, y + radius),
            fill=_rgb(LAUNCHER_WHITE),
        )


def _draw_launcher_mark(
    draw: ImageDraw.ImageDraw, size: int, *, scale: float = 1.0
) -> None:
    left_page = _join(
        _cubic((0.50, 0.54), (0.42, 0.48), (0.29, 0.45), (0.20, 0.51)),
        _cubic((0.20, 0.51), (0.19, 0.58), (0.19, 0.66), (0.20, 0.71)),
        _cubic((0.20, 0.71), (0.30, 0.66), (0.41, 0.70), (0.50, 0.79)),
    )
    right_page = _join(
        _cubic((0.50, 0.54), (0.58, 0.48), (0.71, 0.45), (0.81, 0.51)),
        _cubic((0.81, 0.51), (0.82, 0.58), (0.82, 0.66), (0.81, 0.71)),
        _cubic((0.81, 0.71), (0.70, 0.66), (0.59, 0.70), (0.50, 0.79)),
    )
    fold = _cubic((0.50, 0.54), (0.50, 0.62), (0.50, 0.71), (0.50, 0.79))

    for page in (left_page, right_page, fold):
        _stroke(draw, page, size, width_ratio=0.052, scale=scale)

    stem = _cubic(
        (0.56, 0.66),
        (0.56, 0.52),
        (0.64, 0.33),
        (0.79, 0.18),
        steps=52,
    )
    _stroke(draw, stem, size, width_ratio=0.039, scale=scale)

    feather_barbs = (
        _cubic((0.60, 0.49), (0.57, 0.46), (0.54, 0.40), (0.51, 0.37)),
        _cubic((0.62, 0.44), (0.67, 0.43), (0.72, 0.37), (0.76, 0.34)),
        _cubic((0.65, 0.37), (0.62, 0.34), (0.59, 0.29), (0.57, 0.26)),
        _cubic((0.68, 0.32), (0.73, 0.31), (0.77, 0.27), (0.80, 0.24)),
        _cubic((0.72, 0.27), (0.70, 0.24), (0.68, 0.20), (0.68, 0.18)),
        _cubic((0.75, 0.23), (0.78, 0.22), (0.80, 0.19), (0.82, 0.17)),
    )
    for barb in feather_barbs:
        _stroke(draw, barb, size, width_ratio=0.034, scale=scale)


def _render_launcher(size: int, *, mark_scale: float) -> Image.Image:
    if size <= 0:
        raise ValueError("size must be positive")
    supersample = 8 if size <= 64 else 4
    canvas_size = size * supersample
    image = _vertical_gradient(canvas_size)
    _draw_launcher_mark(ImageDraw.Draw(image), canvas_size, scale=mark_scale)
    return image.resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")


def generate_icon(size: int) -> Image.Image:
    """Return the ordinary full-bleed launcher icon at ``size`` pixels."""
    return _render_launcher(size, mark_scale=1.0)


def generate_maskable_icon(size: int) -> Image.Image:
    """Return a full-bleed icon whose white mark fits the maskable safe circle."""
    return _render_launcher(size, mark_scale=MASKABLE_MARK_SCALE)


def generate_adaptive_foreground(size: int = 432) -> Image.Image:
    """Return the white mark inside Android's central 66 dp safe zone."""
    if size <= 0:
        raise ValueError("size must be positive")
    supersample = 4
    canvas_size = size * supersample
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    _draw_launcher_mark(
        ImageDraw.Draw(canvas),
        canvas_size,
        scale=ADAPTIVE_MARK_SCALE,
    )
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def _round_icon(size: int) -> Image.Image:
    icon = generate_icon(size)
    supersample = 4
    mask = Image.new("L", (size * supersample, size * supersample), 0)
    ImageDraw.Draw(mask).ellipse(
        (0, 0, size * supersample - 1, size * supersample - 1),
        fill=255,
    )
    icon.putalpha(mask.resize((size, size), Image.Resampling.LANCZOS))
    return icon


def _save(image: Image.Image, path: Path, *, opaque: bool = False) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = image.convert("RGB") if opaque else image
    image.save(path, optimize=True)
    return path


def _ios_app_icon_sizes(directory: Path) -> dict[str, int]:
    metadata_path = directory / "Contents.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    sizes: dict[str, int] = {}
    for entry in metadata["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        scale = float(entry["scale"].removesuffix("x"))
        width, height = (
            round(float(value) * scale) for value in entry["size"].split("x")
        )
        if width != height:
            raise ValueError(f"Expected square iOS icon metadata: {entry}")
        existing = sizes.get(filename)
        if existing is not None and existing != width:
            raise ValueError(f"Conflicting iOS icon metadata for {filename}")
        sizes[filename] = width
    return sizes


def write_all_assets(project_root: Path) -> list[Path]:
    project_root = project_root.resolve()
    written: list[Path] = []

    master = generate_icon(1024)
    branding = project_root / "assets" / "branding"
    written.append(_save(master, branding / "icon-master.png", opaque=True))
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
    android_res = project_root / "android" / "app" / "src" / "main" / "res"
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

    colors = android_res / "values" / "colors.xml"
    colors.parent.mkdir(parents=True, exist_ok=True)
    colors.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        f'    <color name="ic_launcher_background_top">{LAUNCHER_BLUE_TOP}</color>\n'
        f'    <color name="ic_launcher_background_bottom">{LAUNCHER_BLUE_BOTTOM}</color>\n'
        '</resources>\n',
        encoding="utf-8",
    )
    written.append(colors)

    background = android_res / "drawable" / "ic_launcher_background.xml"
    background.parent.mkdir(parents=True, exist_ok=True)
    background.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android" '
        'android:shape="rectangle">\n'
        '    <gradient\n'
        '        android:angle="270"\n'
        '        android:startColor="@color/ic_launcher_background_top"\n'
        '        android:endColor="@color/ic_launcher_background_bottom" />\n'
        '</shape>\n',
        encoding="utf-8",
    )
    written.append(background)

    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n'
    )
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        path = android_res / "mipmap-anydpi-v26" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(adaptive, encoding="utf-8")
        written.append(path)

    ios_directory = (
        project_root / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    )
    for filename, size in sorted(_ios_app_icon_sizes(ios_directory).items()):
        written.append(
            _save(generate_icon(size), ios_directory / filename, opaque=True)
        )

    windows_icon = project_root / "windows" / "runner" / "resources" / "app_icon.ico"
    windows_icon.parent.mkdir(parents=True, exist_ok=True)
    master.save(
        windows_icon,
        format="ICO",
        sizes=WINDOWS_ICON_SIZES,
    )
    written.append(windows_icon)
    return written


def check_assets(project_root: Path) -> None:
    required = {
        project_root / "assets/branding/icon-master.png": (1024, 1024),
        project_root / "web/favicon.png": (16, 16),
        project_root / "web/icons/Icon-192.png": (192, 192),
        project_root / "web/icons/Icon-maskable-512.png": (512, 512),
        project_root
        / "android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png": (432, 432),
        project_root
        / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": (1024, 1024),
    }
    for path, expected in required.items():
        with Image.open(path) as image:
            if image.size != expected:
                raise SystemExit(f"{path}: expected {expected}, found {image.size}")
    print(f"Verified {len(required)} representative launcher assets.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate 阅读 launcher icons from one normalized geometric master."
    )
    parser.add_argument(
        "--check", action="store_true", help="validate representative generated files"
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
