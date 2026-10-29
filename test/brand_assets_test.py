import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tool" / "generate_brand_assets.py"


def load_generator():
    spec = importlib.util.spec_from_file_location("brand_generator", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class BrandAssetsTest(unittest.TestCase):
    def test_generator_uses_the_approved_flat_palette(self):
        generator = load_generator()
        self.assertEqual(generator.PAPER, "#F2E8D5")
        self.assertEqual(generator.INK, "#28302C")
        self.assertEqual(generator.CINNABAR, "#A54636")
        icon = generator.generate_icon(512)
        colors = {pixel[:3] for pixel in icon.convert("RGBA").getdata()}
        self.assertIn((242, 232, 213), colors)
        self.assertIn((40, 48, 44), colors)
        self.assertIn((165, 70, 54), colors)
        self.assertNotIn((36, 104, 222), colors)

    def test_generator_is_deterministic_and_readable_at_16_pixels(self):
        generator = load_generator()
        first = generator.generate_icon(16).convert("RGBA")
        second = generator.generate_icon(16).convert("RGBA")
        self.assertEqual(first.tobytes(), second.tobytes())
        self.assertEqual(first.size, (16, 16))
        self.assertEqual(first.getextrema()[3], (255, 255))
        digest = hashlib.sha256(first.tobytes()).hexdigest()
        self.assertEqual(len(digest), 64)
        non_paper = sum(pixel[:3] != (242, 232, 213) for pixel in first.getdata())
        self.assertGreater(non_paper, 30)

    def test_generated_platform_assets_have_expected_dimensions(self):
        expected = {
            ROOT / "assets/branding/icon-master.png": (1024, 1024),
            ROOT / "web/favicon.png": (16, 16),
            ROOT / "web/icons/Icon-192.png": (192, 192),
            ROOT / "web/icons/Icon-512.png": (512, 512),
            ROOT / "web/icons/Icon-maskable-192.png": (192, 192),
            ROOT / "web/icons/Icon-maskable-512.png": (512, 512),
            ROOT / "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": (48, 48),
            ROOT / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": (192, 192),
            ROOT / "android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png": (432, 432),
            ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": (1024, 1024),
            ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png": (128, 128),
            ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png": (256, 256),
            ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png": (384, 384),
        }
        for path, size in expected.items():
            with self.subTest(path=path):
                with Image.open(path) as image:
                    self.assertEqual(image.size, size)
        with Image.open(ROOT / "windows/runner/resources/app_icon.ico") as icon:
            self.assertIn((16, 16), icon.ico.sizes())
            self.assertIn((256, 256), icon.ico.sizes())

    def test_generated_assets_match_the_repository_snapshot(self):
        generator = load_generator()
        app_icons = Path("ios/Runner/Assets.xcassets/AppIcon.appiconset")
        metadata = json.loads((ROOT / app_icons / "Contents.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            # iOS 的尺寸来自平台清单，不依赖待验证 PNG 是否存在或正确。
            for entry in metadata["images"]:
                filename = entry.get("filename")
                if not filename:
                    continue
                scale = float(entry["scale"].removesuffix("x"))
                size = tuple(round(float(value) * scale) for value in entry["size"].split("x"))
                path = target / app_icons / filename
                path.parent.mkdir(parents=True, exist_ok=True)
                Image.new("RGB", size).save(path)

            for generated in generator.write_all_assets(target):
                actual = ROOT / generated.relative_to(target)
                with self.subTest(path=actual):
                    self.assertTrue(actual.is_file(), f"Missing brand asset: {actual}")
                    if generated.suffix == ".xml":
                        self.assertEqual(actual.read_text(encoding="utf-8"), generated.read_text(encoding="utf-8"))
                        continue
                    with Image.open(actual) as snapshot, Image.open(generated) as expected:
                        self.assertEqual(snapshot.size, expected.size)
                        self.assertEqual(snapshot.mode, expected.mode)
                        if generated.suffix == ".ico":
                            self.assertEqual(snapshot.ico.sizes(), expected.ico.sizes())
                            for size in expected.ico.sizes():
                                self.assertEqual(snapshot.ico.getimage(size).tobytes(), expected.ico.getimage(size).tobytes())
                        else:
                            self.assertEqual(snapshot.tobytes(), expected.tobytes())


if __name__ == "__main__":
    unittest.main()
