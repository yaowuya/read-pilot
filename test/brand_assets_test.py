import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tool" / "generate_brand_assets.py"
IOS_APPICON = Path("ios/Runner/Assets.xcassets/AppIcon.appiconset")
IOS_LAUNCH = Path("ios/Runner/Assets.xcassets/LaunchImage.imageset")
ANDROID_RES = Path("android/app/src/main/res")
WINDOWS_ICON = Path("windows/runner/resources/app_icon.ico")

BLUE_TOP = (58, 169, 255)
BLUE_BOTTOM = (40, 161, 255)
WHITE = (255, 255, 255)
ICO_SIZES = {(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)}
LAUNCH_HASHES = {
    "LaunchImage.png": "f3fc1421fabab01590e273e635fb9ca09cdffab4d285d3f0a510c4c3ccc7f029",
    "LaunchImage@2x.png": "5f05b8eaa13c3200511be309769b11339be4d74a1f8cca54faf5f5689268cd42",
    "LaunchImage@3x.png": "2aa97d58d0b12cdbb8aa2c9ef54a2c4452eb7023a4d3a58240d0fe4fcfbbcb8f",
}


def load_generator():
    spec = importlib.util.spec_from_file_location("brand_generator", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _close(actual, expected, tolerance=2):
    return all(abs(channel - target) <= tolerance for channel, target in zip(actual[:3], expected))


def _is_white(pixel, threshold=235):
    return all(channel >= threshold for channel in pixel[:3])


def _white_points(image, threshold=235):
    width = image.width
    return [
        (index % width, index // width)
        for index, pixel in enumerate(image.convert("RGB").getdata())
        if _is_white(pixel, threshold)
    ]


def _visible_mark_points(image, threshold=8):
    rgb = image.convert("RGB")
    denominator = max(1, rgb.height - 1)
    points = []
    for index, pixel in enumerate(rgb.getdata()):
        y = index // rgb.width
        ratio = y / denominator
        background = tuple(
            round(start + (end - start) * ratio)
            for start, end in zip(BLUE_TOP, BLUE_BOTTOM)
        )
        if max(abs(channel - expected) for channel, expected in zip(pixel, background)) >= threshold:
            points.append((index % rgb.width, y))
    return points


def _alpha_points(image, threshold=8):
    rgba = image.convert("RGBA")
    width = rgba.width
    return [
        (index % width, index // width)
        for index, pixel in enumerate(rgba.getdata())
        if pixel[3] >= threshold
    ]


def _metadata_sizes(root):
    metadata = json.loads((root / IOS_APPICON / "Contents.json").read_text(encoding="utf-8"))
    sizes = {}
    for entry in metadata["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        scale = float(entry["scale"].removesuffix("x"))
        points = tuple(float(value) for value in entry["size"].split("x"))
        sizes[filename] = tuple(round(value * scale) for value in points)
    return sizes


def _prepare_generation_root(target):
    appicon = target / IOS_APPICON
    appicon.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / IOS_APPICON / "Contents.json", appicon / "Contents.json")

    launch = target / IOS_LAUNCH
    launch.mkdir(parents=True, exist_ok=True)
    for filename in LAUNCH_HASHES:
        shutil.copyfile(ROOT / IOS_LAUNCH / filename, launch / filename)


def _hashes(paths, root):
    return {
        path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in paths
    }


def _expected_generated_paths():
    paths = {
        "assets/branding/icon-master.png",
        "assets/branding/icon-32.png",
        "assets/branding/icon-16.png",
        "web/favicon.png",
        "web/icons/Icon-192.png",
        "web/icons/Icon-512.png",
        "web/icons/Icon-maskable-192.png",
        "web/icons/Icon-maskable-512.png",
        "android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png",
        "android/app/src/main/res/values/colors.xml",
        "android/app/src/main/res/drawable/ic_launcher_background.xml",
        "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml",
        "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml",
        "windows/runner/resources/app_icon.ico",
    }
    for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
        paths.add(f"android/app/src/main/res/mipmap-{density}/ic_launcher.png")
        paths.add(f"android/app/src/main/res/mipmap-{density}/ic_launcher_round.png")
    paths.update(
        (IOS_APPICON / filename).as_posix()
        for filename in _metadata_sizes(ROOT)
    )
    return paths


class BrandAssetsTest(unittest.TestCase):
    def assertWhiteNear(self, image, x_ratio, y_ratio, radius_ratio=0.025):
        rgb = image.convert("RGB")
        center_x = round((rgb.width - 1) * x_ratio)
        center_y = round((rgb.height - 1) * y_ratio)
        radius = max(1, round(rgb.width * radius_ratio))
        found = any(
            _is_white(rgb.getpixel((x, y)))
            for y in range(max(0, center_y - radius), min(rgb.height, center_y + radius + 1))
            for x in range(max(0, center_x - radius), min(rgb.width, center_x + radius + 1))
            if (x - center_x) ** 2 + (y - center_y) ** 2 <= radius**2
        )
        self.assertTrue(found, f"expected white geometry near ({x_ratio:.3f}, {y_ratio:.3f})")

    def assertMaskableSafeZone(self, image):
        rgba = image.convert("RGBA")
        self.assertEqual(rgba.width, rgba.height)
        self.assertEqual(rgba.getextrema()[3], (255, 255))
        points = _visible_mark_points(rgba)
        self.assertTrue(points)
        center = (rgba.width - 1) / 2
        self.assertLessEqual(
            max(((x - center) ** 2 + (y - center) ** 2) ** 0.5 for x, y in points),
            rgba.width * 0.40,
        )

    def assertAdaptiveSafeZone(self, image):
        self.assertEqual(image.mode, "RGBA")
        self.assertEqual(image.width, image.height)
        points = _alpha_points(image)
        self.assertTrue(points)
        center = (image.width - 1) / 2
        self.assertLessEqual(
            max(((x - center) ** 2 + (y - center) ** 2) ** 0.5 for x, y in points),
            image.width * (33 / 108),
        )
        self.assertEqual(image.getpixel((0, 0))[3], 0)

    def assertGeneratedOutputSemantics(self, root):
        for relative in (
            Path("web/favicon.png"),
            Path("web/icons/Icon-192.png"),
            Path("web/icons/Icon-512.png"),
        ):
            with self.subTest(ordinary_web=relative):
                with Image.open(root / relative) as image:
                    rgba = image.convert("RGBA")
                self.assertEqual(rgba.getextrema()[3], (255, 255))

        for relative in (
            Path("web/icons/Icon-maskable-192.png"),
            Path("web/icons/Icon-maskable-512.png"),
        ):
            with self.subTest(maskable_web=relative):
                with Image.open(root / relative) as image:
                    self.assertMaskableSafeZone(image)

        with Image.open(
            root / ANDROID_RES / "drawable-nodpi/ic_launcher_foreground.png"
        ) as image:
            self.assertAdaptiveSafeZone(image)

    def test_launcher_master_has_blue_gradient_white_open_book_and_feather(self):
        generator = load_generator()
        self.assertEqual(generator.LAUNCHER_BLUE_TOP, "#3AA9FF")
        self.assertEqual(generator.LAUNCHER_BLUE_BOTTOM, "#28A1FF")
        self.assertEqual(getattr(generator, "LAUNCHER_WHITE", None), "#FFFFFF")

        icon = generator.generate_icon(1024).convert("RGB")
        self.assertTrue(_close(icon.getpixel((8, 8)), BLUE_TOP))
        self.assertTrue(_close(icon.getpixel((8, 1015)), BLUE_BOTTOM))

        extrema = icon.getextrema()
        self.assertGreaterEqual(extrema[1][0], 145, "legacy ink/red pixels must not remain")
        self.assertGreaterEqual(extrema[2][0], 250, "launcher mark must use only blue and white")
        self.assertGreater(len(_white_points(icon)), 20_000)

        # Open-book outline: left/right crowns, lower corners, and the central fold.
        for point in (
            (0.20, 0.51),
            (0.34, 0.47),
            (0.50, 0.54),
            (0.66, 0.47),
            (0.81, 0.51),
            (0.20, 0.71),
            (0.50, 0.79),
            (0.81, 0.71),
        ):
            with self.subTest(book_point=point):
                self.assertWhiteNear(icon, *point)

        # The feather-leaf grows from the right page and occupies only the upper-right field.
        for point in ((0.56, 0.66), (0.61, 0.47), (0.53, 0.38), (0.73, 0.35), (0.79, 0.18)):
            with self.subTest(feather_point=point):
                self.assertWhiteNear(icon, *point)
        upper_left = icon.crop((80, 80, 390, 390))
        self.assertLess(len(_white_points(upper_left)), 500)

        # The pages stay outlined instead of becoming a filled white book.
        self.assertFalse(_is_white(icon.getpixel((round(0.34 * 1024), round(0.61 * 1024)))))
        self.assertFalse(_is_white(icon.getpixel((round(0.68 * 1024), round(0.62 * 1024)))))

    def test_normalized_geometry_is_deterministic_and_readable_at_small_sizes(self):
        generator = load_generator()
        for size in (1024, 32, 16):
            with self.subTest(size=size):
                first = generator.generate_icon(size).convert("RGBA")
                second = generator.generate_icon(size).convert("RGBA")
                self.assertEqual(first.tobytes(), second.tobytes())
                self.assertEqual(first.size, (size, size))
                self.assertEqual(first.getextrema()[3], (255, 255))

                points = _white_points(first, threshold=215)
                self.assertGreaterEqual(len(points), max(8, round(size * size * 0.025)))
                self.assertLess(len(points), round(size * size * 0.30))
                xs = [point[0] for point in points]
                ys = [point[1] for point in points]
                extent = size - 1
                self.assertLessEqual(min(xs), round(extent * 0.25))
                self.assertGreaterEqual(max(xs), round(extent * 0.75))
                self.assertLessEqual(min(ys), round(extent * 0.27))
                self.assertGreaterEqual(max(ys), round(extent * 0.72))

        for invalid_size in (0, -1):
            with self.subTest(invalid_size=invalid_size):
                with self.assertRaises(ValueError):
                    generator.generate_icon(invalid_size)

    def test_ordinary_maskable_and_adaptive_marks_stay_inside_safe_zones(self):
        generator = load_generator()
        ordinary = generator.generate_icon(512)
        ordinary_points = _white_points(ordinary)
        self.assertTrue(ordinary_points)
        self.assertGreaterEqual(min(x for x, _ in ordinary_points), round(512 * 0.14))
        self.assertLessEqual(max(x for x, _ in ordinary_points), round(512 * 0.86))
        self.assertGreaterEqual(min(y for _, y in ordinary_points), round(512 * 0.12))
        self.assertLessEqual(max(y for _, y in ordinary_points), round(512 * 0.84))

        maskable_factory = getattr(generator, "generate_maskable_icon", None)
        self.assertTrue(callable(maskable_factory), "maskable launcher generator is required")
        maskable = maskable_factory(512)
        self.assertTrue(_close(maskable.convert("RGB").getpixel((8, 8)), BLUE_TOP, tolerance=3))
        self.assertMaskableSafeZone(maskable)

        adaptive = generator.generate_adaptive_foreground(432)
        self.assertAdaptiveSafeZone(adaptive)

    def test_platform_assets_cover_every_launcher_target(self):
        expected_sizes = {
            ROOT / "assets/branding/icon-master.png": (1024, 1024),
            ROOT / "assets/branding/icon-32.png": (32, 32),
            ROOT / "assets/branding/icon-16.png": (16, 16),
            ROOT / "web/favicon.png": (16, 16),
            ROOT / "web/icons/Icon-192.png": (192, 192),
            ROOT / "web/icons/Icon-512.png": (512, 512),
            ROOT / "web/icons/Icon-maskable-192.png": (192, 192),
            ROOT / "web/icons/Icon-maskable-512.png": (512, 512),
            ROOT / ANDROID_RES / "drawable-nodpi/ic_launcher_foreground.png": (432, 432),
        }
        android_sizes = {
            "mdpi": 48,
            "hdpi": 72,
            "xhdpi": 96,
            "xxhdpi": 144,
            "xxxhdpi": 192,
        }
        for density, size in android_sizes.items():
            expected_sizes[ROOT / ANDROID_RES / f"mipmap-{density}/ic_launcher.png"] = (size, size)
            expected_sizes[ROOT / ANDROID_RES / f"mipmap-{density}/ic_launcher_round.png"] = (size, size)
        for filename, size in _metadata_sizes(ROOT).items():
            expected_sizes[ROOT / IOS_APPICON / filename] = size

        for path, size in expected_sizes.items():
            with self.subTest(path=path):
                with Image.open(path) as image:
                    self.assertEqual(image.size, size)
                    if IOS_APPICON.as_posix() in path.as_posix():
                        self.assertEqual(image.mode, "RGB")
                        self.assertEqual(image.getextrema()[0][1], 255)

        for density, size in android_sizes.items():
            ordinary_path = ROOT / ANDROID_RES / f"mipmap-{density}/ic_launcher.png"
            round_path = ROOT / ANDROID_RES / f"mipmap-{density}/ic_launcher_round.png"
            with Image.open(ordinary_path) as image:
                ordinary = image.convert("RGBA")
            with Image.open(round_path) as image:
                rounded = image.convert("RGBA")
            with self.subTest(android_density=density):
                self.assertEqual(ordinary.getextrema()[3], (255, 255))
                self.assertEqual(rounded.getpixel((0, 0))[3], 0)
                self.assertEqual(rounded.getpixel((size - 1, 0))[3], 0)
                self.assertEqual(rounded.getpixel((size // 2, size // 2))[3], 255)

        self.assertGeneratedOutputSemantics(ROOT)

        for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
            adaptive_xml = (ROOT / ANDROID_RES / "mipmap-anydpi-v26" / name).read_text(encoding="utf-8")
            self.assertIn('@drawable/ic_launcher_background', adaptive_xml)
            self.assertIn('@drawable/ic_launcher_foreground', adaptive_xml)
        background_xml = (ROOT / ANDROID_RES / "drawable/ic_launcher_background.xml").read_text(encoding="utf-8")
        self.assertIn('android:angle="270"', background_xml)
        self.assertIn('@color/ic_launcher_background_top', background_xml)
        self.assertIn('@color/ic_launcher_background_bottom', background_xml)

        with Image.open(ROOT / WINDOWS_ICON) as icon:
            self.assertEqual(icon.ico.sizes(), ICO_SIZES)
            for size in sorted(ICO_SIZES):
                with self.subTest(ico_frame=size):
                    frame = icon.ico.getimage(size).convert("RGB")
                    self.assertGreater(len(_white_points(frame, threshold=215)), 4)
                    extrema = frame.getextrema()
                    self.assertGreaterEqual(extrema[1][0], 140)
                    self.assertGreaterEqual(extrema[2][0], 250)

    def test_launch_images_remain_byte_for_byte_unchanged(self):
        for filename, expected_hash in LAUNCH_HASHES.items():
            with self.subTest(filename=filename):
                path = ROOT / IOS_LAUNCH / filename
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), expected_hash)

    def test_two_full_generations_are_deterministic_and_match_repository(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            _prepare_generation_root(target)
            launch_before = _hashes([target / IOS_LAUNCH / name for name in LAUNCH_HASHES], target)

            expected_paths = _expected_generated_paths()
            self.assertEqual(len(expected_paths), 39)

            first_paths = generator.write_all_assets(target)
            first_relative = [path.relative_to(target).as_posix() for path in first_paths]
            self.assertEqual(len(first_paths), 39)
            self.assertEqual(len(set(first_paths)), 39)
            self.assertEqual(set(first_relative), expected_paths)
            self.assertGeneratedOutputSemantics(target)
            first_hashes = _hashes(first_paths, target)

            second_paths = generator.write_all_assets(target)
            second_relative = [path.relative_to(target).as_posix() for path in second_paths]
            self.assertEqual(len(second_paths), 39)
            self.assertEqual(len(set(second_paths)), 39)
            self.assertEqual(second_relative, first_relative)
            second_hashes = _hashes(second_paths, target)

            self.assertEqual(first_hashes, second_hashes)
            self.assertEqual(launch_before, _hashes([target / IOS_LAUNCH / name for name in LAUNCH_HASHES], target))
            self.assertFalse(any(target / IOS_LAUNCH in path.parents for path in first_paths))

            for generated in first_paths:
                actual = ROOT / generated.relative_to(target)
                with self.subTest(snapshot=actual):
                    self.assertTrue(actual.is_file(), f"missing launcher asset: {actual}")
                    self.assertEqual(actual.read_bytes(), generated.read_bytes())


if __name__ == "__main__":
    unittest.main()
