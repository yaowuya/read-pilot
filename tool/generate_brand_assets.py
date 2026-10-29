"""Generate every launcher icon from the 阅读 brand's geometric master.

Requires Pillow. The artwork uses only flat colors and sampled Bézier curves so
small platform assets stay deterministic and visually consistent.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw

PAPER = "#F2E8D5"
INK = "#28302C"
CINNABAR = "#A54636"
MOSS = "#6F7B70"


def _rgb(value: str) -> tuple[int, int, int]:
    value = value.removeprefix("#")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def _cubic(
    start: tuple[float, float],
    control_a: tuple[float, float],
    control_b: tuple[float, float],
    end: tuple[float, float],
    *,
    steps: int = 28,
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


def _scaled(points: Iterable[tuple[float, float]], size: int) -> list[tuple[int, int]]:
    return [(round(x * size), round(y * size)) for x, y in points]


def _draw_mark(draw: ImageDraw.ImageDraw, size: int, *, include_paper: bool) -> None:
    paper = _rgb(PAPER)
    ink = _rgb(INK)
    cinnabar = _rgb(CINNABAR)

    if include_paper:
        draw.rounded_rectangle(
            (0, 0, size - 1, size - 1),
            radius=round(size * 0.17),
            fill=paper,
        )

    inset = size * 0.115
    draw.rounded_rectangle(
        (inset, inset, size - inset, size - inset),
        radius=round(size * 0.075),
        outline=cinnabar,
        width=max(1, round(size * 0.052)),
    )

    moon_center = (size * 0.69, size * 0.285)
    moon_radius = size * 0.078
    draw.ellipse(
        (
            moon_center[0] - moon_radius,
            moon_center[1] - moon_radius,
            moon_center[0] + moon_radius,
            moon_center[1] + moon_radius,
        ),
        fill=cinnabar,
    )

    left = [
        *_cubic((0.49, 0.79), (0.41, 0.69), (0.29, 0.67), (0.19, 0.72)),
        (0.19, 0.42),
        *_cubic((0.19, 0.42), (0.30, 0.36), (0.43, 0.39), (0.49, 0.48)),
    ]
    right = [
        *_cubic((0.51, 0.79), (0.59, 0.69), (0.71, 0.67), (0.81, 0.72)),
        (0.81, 0.42),
        *_cubic((0.81, 0.42), (0.70, 0.36), (0.57, 0.39), (0.51, 0.48)),
    ]
    draw.polygon(_scaled(left, size), fill=ink)
    draw.polygon(_scaled(right, size), fill=ink)

    spine_width = max(1, round(size * 0.027))
    draw.line(
        _scaled([(0.50, 0.49), (0.50, 0.785)], size),
        fill=paper,
        width=spine_width,
    )

    if size >= 256:
        line_width = max(1, round(size * 0.012))
        for y in (0.53, 0.59):
            draw.line(
                _scaled([(0.25, y), (0.43, y + 0.015)], size),
                fill=paper,
                width=line_width,
            )
            draw.line(
                _scaled([(0.57, y + 0.015), (0.75, y)], size),
                fill=paper,
                width=line_width,
            )


def generate_icon(size: int) -> Image.Image:
    """Return an opaque square icon at ``size`` pixels."""
    if size <= 0:
        raise ValueError("size must be positive")
    supersample = 8 if size <= 64 else 4
    canvas_size = size * supersample
    image = Image.new("RGB", (canvas_size, canvas_size), _rgb(PAPER))
    _draw_mark(ImageDraw.Draw(image), canvas_size, include_paper=True)
    return image.resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")


def generate_adaptive_foreground(size: int = 432) -> Image.Image:
    """Return a transparent Android adaptive foreground inside its safe zone."""
    supersample = 4
    canvas = Image.new("RGBA", (size * supersample, size * supersample), (0, 0, 0, 0))
    layer_size = round(size * 0.66) * supersample
    layer = Image.new("RGBA", (layer_size, layer_size), (0, 0, 0, 0))
    _draw_mark(ImageDraw.Draw(layer), layer_size, include_paper=False)
    position = ((canvas.width - layer_size) // 2, (canvas.height - layer_size) // 2)
    canvas.alpha_composite(layer, position)
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def _round_icon(size: int) -> Image.Image:
    icon = generate_icon(size)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    icon.putalpha(mask)
    return icon


def _save(image: Image.Image, path: Path, *, opaque: bool = False) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = image.convert("RGB") if opaque else image
    image.save(path, optimize=True)
    return path


def write_all_assets(project_root: Path) -> list[Path]:
    project_root = project_root.resolve()
    written: list[Path] = []

    master = generate_icon(1024)
    branding = project_root / "assets" / "branding"
    written.append(_save(master, branding / "icon-master.png", opaque=True))
    written.append(_save(generate_icon(32), branding / "icon-32.png"))
    written.append(_save(generate_icon(16), branding / "icon-16.png"))

    web_targets = {
        "favicon.png": 16,
        "icons/Icon-192.png": 192,
        "icons/Icon-512.png": 512,
        "icons/Icon-maskable-192.png": 192,
        "icons/Icon-maskable-512.png": 512,
    }
    for relative, size in web_targets.items():
        written.append(_save(generate_icon(size), project_root / "web" / relative))

    android_sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
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
        f'    <color name="ic_launcher_background">{PAPER}</color>\n'
        '</resources>\n',
        encoding="utf-8",
    )
    written.append(colors)
    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n'
    )
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        path = android_res / "mipmap-anydpi-v26" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(adaptive, encoding="utf-8")
        written.append(path)

    ios_directory = project_root / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for path in sorted(ios_directory.glob("*.png")):
        with Image.open(path) as existing:
            size = existing.size
        if size[0] != size[1]:
            raise ValueError(f"Expected square iOS icon: {path}")
        written.append(_save(generate_icon(size[0]), path, opaque=True))

    launch_directory = (
        project_root / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
    )
    for name, size in {
        "LaunchImage.png": 128,
        "LaunchImage@2x.png": 256,
        "LaunchImage@3x.png": 384,
    }.items():
        written.append(_save(generate_icon(size), launch_directory / name, opaque=True))

    windows_icon = project_root / "windows" / "runner" / "resources" / "app_icon.ico"
    windows_icon.parent.mkdir(parents=True, exist_ok=True)
    master.convert("RGBA").save(
        windows_icon,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    written.append(windows_icon)
    return written


def check_assets(project_root: Path) -> None:
    required = {
        project_root / "assets/branding/icon-master.png": (1024, 1024),
        project_root / "web/favicon.png": (16, 16),
        project_root / "web/icons/Icon-192.png": (192, 192),
        project_root / "web/icons/Icon-512.png": (512, 512),
        project_root / "android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png": (432, 432),
        project_root / "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png": (384, 384),
    }
    for path, expected in required.items():
        with Image.open(path) as image:
            if image.size != expected:
                raise SystemExit(f"{path}: expected {expected}, found {image.size}")
    print(f"Verified {len(required)} representative brand assets.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate 阅读 launcher icons from one geometric master.")
    parser.add_argument("--check", action="store_true", help="validate representative generated files")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    if args.check:
        check_assets(args.root)
    else:
        paths = write_all_assets(args.root)
        print(f"Generated {len(paths)} 阅读 brand assets.")


if __name__ == "__main__":
    main()
