import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tool" / "generate_brand_assets.py"
IOS_APPICON = Path("ios/Runner/Assets.xcassets/AppIcon.appiconset")
IOS_LAUNCH = Path("ios/Runner/Assets.xcassets/LaunchImage.imageset")
ANDROID_RES = Path("android/app/src/main/res")
WINDOWS_ICON = Path("windows/runner/resources/app_icon.ico")

WHITE = (255, 255, 255)
SOURCE_HASHES = {
    "app_icon_1024.png": "62d7e501bc27ec39a04f4a4e3c786fe878187d498727ed52dbfc75bc03790cfa",
    "logo_transparent.png": "4e456e05bca0a3bbf161ad8fb5c441a01e93b4ef765d9670f8a0f535273b04fc",
    "android_foreground.png": "a86e8dad402665fa140646a4e17becf8e7ed186d18d27739f92ef2fe318be7c0",
    "android_monochrome.png": "ee4e48dcab2230ce97df3d40bdb296b7c7dedd3669422859b490ac1b93a0c190",
}
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


def _blue_points(image):
    rgb = image.convert("RGB")
    return [
        (index % rgb.width, index // rgb.width)
        for index, (red, green, blue) in enumerate(rgb.getdata())
        if blue - red >= 70 and blue - green >= 12
    ]


def _visible_mark_points(image, threshold=8):
    rgb = image.convert("RGB")
    return [
        (index % rgb.width, index // rgb.width)
        for index, pixel in enumerate(rgb.getdata())
        if max(abs(channel - 255) for channel in pixel) >= threshold
    ]


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
        "android/app/src/main/res/drawable-nodpi/ic_launcher_monochrome.png",
        "android/app/src/main/res/mipmap-anydpi-v33/ic_launcher.xml",
        "android/app/src/main/res/mipmap-anydpi-v33/ic_launcher_round.xml",
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
    def test_portable_sources_preserve_the_supplied_final_artwork(self):
        for filename, expected_hash in SOURCE_HASHES.items():
            with self.subTest(source=filename):
                source = ROOT / "assets/branding/source" / filename
                self.assertTrue(source.is_file(), f"missing portable icon source: {source}")
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), expected_hash)
                with Image.open(source) as image:
                    self.assertEqual(image.size, (1024, 1024))
                    self.assertEqual(image.mode, "RGB" if filename == "app_icon_1024.png" else "RGBA")

    def test_launcher_master_is_the_polished_diagonal_feather_not_the_geometric_experiment(self):
        generator = load_generator()
        with Image.open(ROOT / "assets/branding/source/app_icon_1024.png") as source:
            expected = source.convert("RGB").tobytes()
        actual = generator.generate_icon(1024)
        self.assertEqual(actual.size, (1024, 1024))
        self.assertEqual(actual.convert("RGB").tobytes(), expected)
        self.assertEqual(actual.convert("RGBA").getextrema()[3], (255, 255))
        self.assertTrue(callable(getattr(generator, "generate_geometric_icon", None)),
                        "retain the authored geometric renderer as an explicit experiment")

    def test_adaptive_and_monochrome_use_provided_portable_inputs(self):
        generator = load_generator()
        for factory_name, filename in (
            ("generate_adaptive_foreground", "android_foreground.png"),
            ("generate_monochrome_foreground", "android_monochrome.png"),
        ):
            with self.subTest(layer=filename):
                factory = getattr(generator, factory_name, None)
                self.assertTrue(callable(factory), f"missing Android layer generator: {factory_name}")
                with Image.open(ROOT / "assets/branding/source" / filename) as source:
                    expected = source.resize((432, 432), Image.Resampling.LANCZOS)
                actual = factory(432)
                self.assertEqual(actual.mode, "RGBA")
                self.assertEqual(actual.tobytes(), expected.tobytes())
                self.assertAdaptiveSafeZone(actual)
                if "monochrome" in filename:
                    visible = [pixel for pixel in actual.getdata() if pixel[3] > 0]
                    self.assertTrue(visible)
                    self.assertTrue(all(pixel[:3] == WHITE for pixel in visible))
                    self.assertLess(len(visible), 432 * 432 * 0.20)

    def test_white_maskable_retains_feather_inside_safe_circle(self):
        generator = load_generator()
        factory = getattr(generator, "generate_maskable_icon", None)
        self.assertTrue(callable(factory), "maskable launcher generator is required")
        for size in (192, 512):
            with self.subTest(size=size):
                image = factory(size)
                self.assertMaskableSafeZone(image)
                self.assertEqual(image.convert("RGB").getpixel((0, 0)), WHITE)
                points = _blue_points(image)
                self.assertGreater(len(points), size * size * 0.08)
                self.assertLess(len(points), size * size * 0.30)
                # The reduced mark must still occupy the centre, not be an
                # empty white tile or an already-inset adaptive icon shrunk twice.
                self.assertLess(min(x for x, _ in points), size * 0.25)
                self.assertGreaterEqual(max(x for x, _ in points) + 1, size * 0.75)

    def test_generated_targets_include_android_13_without_touching_source_or_metadata(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            _prepare_generation_root(target)
            metadata = target / IOS_APPICON / "Contents.json"
            metadata_before = metadata.read_bytes()
            paths = generator.write_all_assets(target)
            self.assertEqual(len(paths), 42)
            self.assertEqual(len(set(paths)), 42)
            self.assertEqual({path.relative_to(target).as_posix() for path in paths},
                             _expected_generated_paths())
            self.assertEqual(metadata.read_bytes(), metadata_before)
            for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
                xml = (target / ANDROID_RES / "mipmap-anydpi-v33" / name).read_text(encoding="utf-8")
                self.assertIn('<monochrome android:drawable="@drawable/ic_launcher_monochrome"', xml)
            with Image.open(target / ANDROID_RES / "drawable-nodpi/ic_launcher_monochrome.png") as image:
                self.assertAdaptiveSafeZone(image)

    def test_legacy_round_icons_do_not_clip_the_feather(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            _prepare_generation_root(target)
            generator.write_all_assets(target)
            for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
                with self.subTest(density=density):
                    with Image.open(target / ANDROID_RES / f"mipmap-{density}/ic_launcher_round.png") as image:
                        rgba = image.convert("RGBA")
                    self.assertEqual(rgba.getpixel((0, 0))[3], 0)
                    points = [
                        (index % rgba.width, index // rgba.width)
                        for index, pixel in enumerate(rgba.getdata())
                        if pixel[3] >= 245 and max(255 - value for value in pixel[:3]) >= 32
                    ]
                    self.assertTrue(points)
                    center = (rgba.width - 1) / 2
                    radius = max(((x - center) ** 2 + (y - center) ** 2) ** 0.5 for x, y in points)
                    self.assertLessEqual(radius / rgba.width, 0.49,
                                         "important feather/book pixels must not meet the circular crop")

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

        for name in ("ic_launcher_foreground.png", "ic_launcher_monochrome.png"):
            with Image.open(root / ANDROID_RES / "drawable-nodpi" / name) as image:
                self.assertAdaptiveSafeZone(image)

    def test_white_tile_has_blue_book_and_translucent_diagonal_feather(self):
        generator = load_generator()
        icon = generator.generate_icon(1024).convert("RGB")
        for point in ((0, 0), (1023, 0), (0, 1023), (1023, 1023), (150, 150)):
            with self.subTest(background=point):
                self.assertEqual(icon.getpixel(point), WHITE)

        # Independent visual landmarks from the approved diagonal-feather design:
        # saturated pages and bottom fold, translucent blade, and pale cyan stem.
        for x_ratio, y_ratio in ((0.22, 0.50), (0.80, 0.60), (0.50, 0.82)):
            pixel = icon.getpixel((round(x_ratio * 1023), round(y_ratio * 1023)))
            self.assertLess(pixel[0], 35)
            self.assertGreater(pixel[2], 235)
        blade = icon.getpixel((665, 348))
        self.assertGreater(blade[0], 100)
        self.assertGreater(blade[1], 170)
        self.assertGreater(blade[2], 220)
        stem = icon.getpixel((184, 880))
        self.assertGreater(stem[0], 130)
        self.assertGreater(stem[1], 220)
        self.assertGreater(stem[2], 235)

    def test_final_artwork_is_deterministic_and_readable_at_small_sizes(self):
        generator = load_generator()
        for size in (1024, 32, 16):
            with self.subTest(size=size):
                first = generator.generate_icon(size).convert("RGBA")
                second = generator.generate_icon(size).convert("RGBA")
                self.assertEqual(first.tobytes(), second.tobytes())
                self.assertEqual(first.size, (size, size))
                self.assertEqual(first.getextrema()[3], (255, 255))
                self.assertEqual(first.getpixel((0, 0))[:3], WHITE)

                points = _blue_points(first)
                self.assertGreater(len(points), size * size * 0.25)
                self.assertLess(len(points), size * size * 0.50)
                xs = [point[0] for point in points]
                ys = [point[1] for point in points]
                self.assertLessEqual(min(xs), size * 0.20)
                self.assertGreaterEqual(max(xs) + 1, size * 0.80)
                self.assertLessEqual(min(ys), size * 0.20)
                self.assertGreaterEqual(max(ys) + 1, size * 0.80)

        for factory in (generator.generate_icon, generator.generate_maskable_icon,
                        generator.generate_adaptive_foreground, generator.generate_monochrome_foreground):
            for invalid_size in (0, -1):
                with self.subTest(factory=factory.__name__, invalid_size=invalid_size):
                    with self.assertRaises(ValueError):
                        factory(invalid_size)

    def test_ordinary_maskable_and_adaptive_marks_stay_inside_safe_zones(self):
        generator = load_generator()
        ordinary_points = _blue_points(generator.generate_icon(512))
        self.assertTrue(ordinary_points)
        self.assertGreaterEqual(min(x for x, _ in ordinary_points), round(512 * 0.10))
        self.assertLessEqual(max(x for x, _ in ordinary_points), round(512 * 0.90))
        self.assertGreaterEqual(min(y for _, y in ordinary_points), round(512 * 0.08))
        self.assertLessEqual(max(y for _, y in ordinary_points), round(512 * 0.92))
        self.assertMaskableSafeZone(generator.generate_maskable_icon(512))
        self.assertAdaptiveSafeZone(generator.generate_adaptive_foreground(432))
        self.assertAdaptiveSafeZone(generator.generate_monochrome_foreground(432))

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
            ROOT / ANDROID_RES / "drawable-nodpi/ic_launcher_monochrome.png": (432, 432),
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
                    self.assertGreater(len(_blue_points(frame)), size[0] * size[1] * 0.25)
                    self.assertLess(len(_blue_points(frame)), size[0] * size[1] * 0.50)
                    self.assertEqual(frame.getpixel((0, 0)), WHITE)

    def test_invalid_ios_metadata_does_not_write_any_launcher_assets(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            _prepare_generation_root(target)
            existing = target / "assets/branding/icon-master.png"
            existing.parent.mkdir(parents=True)
            existing.write_bytes(b"existing launcher must survive invalid metadata")
            metadata_path = target / IOS_APPICON / "Contents.json"
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
            metadata["images"][0]["size"] = "20x21"
            metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
            before = _hashes([path for path in target.rglob("*") if path.is_file()], target)

            with self.assertRaises(ValueError):
                generator.write_all_assets(target)

            after = _hashes([path for path in target.rglob("*") if path.is_file()], target)
            self.assertEqual(before, after, "validate every target before the first write")

    def test_ios_metadata_cannot_target_non_icon_assets(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            _prepare_generation_root(target)
            metadata_path = target / IOS_APPICON / "Contents.json"
            original = json.loads(metadata_path.read_text(encoding="utf-8"))
            for filename in ("../LaunchImage.imageset/LaunchImage.png", "..\\LaunchImage.imageset\\LaunchImage.png", "Contents.json"):
                with self.subTest(filename=filename):
                    metadata = json.loads(json.dumps(original))
                    metadata["images"][0]["filename"] = filename
                    metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
                    before = _hashes([path for path in target.rglob("*") if path.is_file()], target)
                    with self.assertRaises(ValueError):
                        generator.write_all_assets(target)
                    self.assertEqual(before, _hashes([path for path in target.rglob("*") if path.is_file()], target))

    def test_generated_master_is_byte_identical_to_the_final_source(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            _prepare_generation_root(target)
            generator.write_all_assets(target)
            for relative in ("assets/branding/icon-master.png", (IOS_APPICON / "Icon-App-1024x1024@1x.png").as_posix()):
                with self.subTest(master=relative):
                    self.assertEqual(hashlib.sha256((target / relative).read_bytes()).hexdigest(),
                                     SOURCE_HASHES["app_icon_1024.png"])

    def test_generation_preserves_non_icon_android_resources(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            _prepare_generation_root(target)
            colors = target / ANDROID_RES / "values/colors.xml"
            colors.parent.mkdir(parents=True)
            colors.write_text(
                '<resources>\n'
                '    <!-- Keep the app theme and non-icon resources. -->\n'
                '    <color name="app_accent">#123456</color>\n'
                '    <item type="color" name="app_surface">@android:color/white</item>\n'
                '    <color name="ic_launcher_background_top">#000000</color>\n'
                '    <color name="ic_launcher_background_bottom">#000000</color>\n'
                '</resources>\n', encoding="utf-8",
            )
            sentinel = target / ANDROID_RES / "drawable/keep_me.xml"
            sentinel.parent.mkdir(parents=True)
            sentinel.write_bytes(b"unrelated Android resource")
            generator.write_all_assets(target)
            resources = ET.fromstring(colors.read_text(encoding="utf-8"))
            self.assertEqual(resources.find("color[@name='app_accent']").text, "#123456")
            self.assertEqual(resources.find("item[@name='app_surface']").text, "@android:color/white")
            self.assertIn("Keep the app theme", colors.read_text(encoding="utf-8"))
            for name in ("ic_launcher_background_top", "ic_launcher_background_bottom"):
                self.assertEqual(resources.find(f"color[@name='{name}']").text, "#FFFFFF")
            self.assertEqual(sentinel.read_bytes(), b"unrelated Android resource")

    def test_invalid_canonical_input_fails_before_replacing_any_icons(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            target = base / "project"
            _prepare_generation_root(target)
            sources = base / "inputs"
            shutil.copytree(ROOT / "assets/branding/source", sources)
            Image.new("RGBA", (1, 1)).save(sources / "android_monochrome.png")
            generator.SOURCE_DIRECTORY = sources
            before = _hashes([path for path in target.rglob("*") if path.is_file()], target)
            with self.assertRaises(ValueError):
                generator.write_all_assets(target)
            self.assertEqual(before, _hashes([path for path in target.rglob("*") if path.is_file()], target))

    def test_check_rejects_stale_nonrepresentative_asset_without_writing(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            _prepare_generation_root(target)
            generator.write_all_assets(target)
            Image.new("RGBA", (32, 32), (255, 255, 255, 255)).save(target / "assets/branding/icon-32.png")
            before = _hashes([path for path in target.rglob("*") if path.is_file()], target)
            with self.assertRaises(SystemExit):
                generator.check_assets(target)
            self.assertEqual(before, _hashes([path for path in target.rglob("*") if path.is_file()], target))

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
            self.assertEqual(len(expected_paths), 42)

            first_paths = generator.write_all_assets(target)
            first_relative = [path.relative_to(target).as_posix() for path in first_paths]
            self.assertEqual(len(first_paths), 42)
            self.assertEqual(len(set(first_paths)), 42)
            self.assertEqual(set(first_relative), expected_paths)
            self.assertGeneratedOutputSemantics(target)
            first_hashes = _hashes(first_paths, target)

            second_paths = generator.write_all_assets(target)
            second_relative = [path.relative_to(target).as_posix() for path in second_paths]
            self.assertEqual(len(second_paths), 42)
            self.assertEqual(len(set(second_paths)), 42)
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
