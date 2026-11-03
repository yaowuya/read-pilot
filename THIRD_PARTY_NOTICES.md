# Third-party materials

## Typeface

- **Noto Sans SC** — Copyright 2014-2021 Adobe, with Reserved Font Name 'Source', as stated in the bundled license. SIL Open Font License 1.1.
- Source: <https://github.com/google/fonts/tree/main/ofl/notosanssc>
- Font file: `assets/fonts/NotoSansSC.ttf` (variable weight).
- Full license accompanies the font at `assets/fonts/OFL.txt`.
- Bundled for offline Chinese rendering; no runtime font CDN is needed for the bundled character repertoire.

## Framework and dependencies

Flutter/Dart and pub dependencies retain their own licenses. Flutter's in-app license registry is available through the About screen. `pubspec.lock` pins the resolved packages.

## Book-source design reference

Legado-with-MD3: <https://github.com/HapeLee/legado-with-MD3>, GPL-3.0. The 阅读 app uses an independently written Dart declarative CSS subset guided by the public data format; it does not embed or translate the upstream Kotlin implementation. Detailed references and compatibility limits are in `docs/BOOK_SOURCES.md`.

## Sample texts and artwork

Bundled reading samples are identified as excerpts of public-domain Chinese works (or original test text written for 阅读), not complete commercially licensed ebooks. Their source/provenance is shown with each book. Covers and the 阅读 mark are original Flutter vector/typographic compositions; platform icon assets are generated from `tool/generate_brand_assets.py`. No WeRead assets are used. Distribution in a new jurisdiction requires checking the applicable copyright term and any future content additions.
