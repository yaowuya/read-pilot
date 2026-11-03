# 阅读 Implementation Plan

> **For agentic workers:** Execute inline using superpowers:executing-plans. User explicitly requested autonomous decisions; no intermediate approval questions. Do not commit or push unless separately requested.

**Goal:** Deliver a runnable Flutter reader with offline books, TXT import, durable progress/notes/preferences, and an explicit Legado CSS source subset.

**Architecture:** Immutable domain models, injected Sembast repository and HTTP client, a ChangeNotifier application controller, and responsive Flutter screens. Reader viewport state remains local; the durable position is chapter plus paragraph anchor. Network failures never block offline books.

**Tech Stack:** Flutter stable / Dart 3, Material 3, sembast + sembast_web, path_provider, html, http, file_picker, flutter_test.

## Global Constraints

- SDK location is `D:\ProgramFiles\flutter`.
- No routine product/technical questions and no automatic commits or pushes.
- No copied WeRead branding, proprietary book content, or translated upstream Kotlin implementation.
- UTF-8/UTF-16 TXT limit 2 MiB. Source JSON limit 10 MiB. HTTP text response limit 2 MiB; request timeout 15 seconds; redirect cap 4.
- HTTP(S) GET + UTF-8 + explicit CSS rules only. Unsupported executable or advanced parsing fields are reported before import.
- All success claims require fresh verification output. Record missing native SDK/toolchain limitations accurately.

## Task 1 — Toolchain, project, and domain

**Files:** `pubspec.yaml`, `analysis_options.yaml`, generated Android/iOS/Web platform folders, `lib/domain/book.dart`, `lib/domain/reader_settings.dart`, `test/domain_test.dart`.

**Interfaces:** `Book` owns metadata and immutable `List<Chapter>`; `ReadingPosition(chapterIndex, paragraphIndex)` is independent of viewport. `Bookmark` owns book ID, position, quote, note, created time. `ReaderSettings` owns theme, font size, and line height.

- [x] Finish installing Flutter at the mandated path, verify with `D:/ProgramFiles/flutter/bin/flutter --version`.
- [x] Scaffold without fetching first: `D:/ProgramFiles/flutter/bin/flutter create --project-name read_pilot --org dev.readpilot --platforms android,ios,web --no-pub .`.
- [x] Configure dependencies and offline font assets; retain application name 阅读.
- [x] Write a model round-trip test before implementation:

```dart
final position = ReadingPosition(chapterIndex: 2, paragraphIndex: 7);
expect(ReadingPosition.fromJson(position.toJson()).paragraphIndex, 7);
expect(ReadingPosition.fromJson(position.toJson()).chapterIndex, 2);
```

- [x] Run `flutter test test/domain_test.dart`; confirm initial failure then implement constructors, copy methods, JSON codecs, clamping/default validation; rerun to PASS.

## Task 2 — Durable offline library and TXT importer

**Files:** `lib/data/app_repository.dart`, `lib/data/database.dart`, `lib/data/database_native.dart`, `lib/data/database_web.dart`, `lib/data/sample_catalog.dart`, `lib/services/txt_importer.dart`, `test/repository_test.dart`, `test/txt_importer_test.dart`.

**Consumes:** Domain codecs. **Produces:** `AppRepository(Database db)`, `initialize()`, `books()`, `saveBook(Book)`, `removeBook(String)`, `savePosition(String, ReadingPosition)`, `saveBookmark(Bookmark)`, `deleteBookmark(String)`, `saveSettings(ReaderSettings)`, `sources()`, `saveSource(BookSource)`. `TxtImporter.parse(Uint8List bytes, String fileName)` returns a local Book.

- [x] Write memory-database tests for round-trip, seed idempotence, deleted samples not reappearing, independent progress/notes/settings, and cleanup after deleting a book.
- [x] Write importer tests including these concrete inputs:

```dart
final book = TxtImporter().parse(
  Uint8List.fromList(utf8.encode('第一章 起风\n\n正文。\n\n第二章 归来\n\n新一章。')),
  '旅行.txt',
);
expect(book.title, '旅行');
expect(book.chapters.length, 2);
expect(book.chapters.last.title, '第二章 归来');
expect(() => TxtImporter().parse(Uint8List(0), '空.txt'), throwsFormatException);
```

- [x] Run these tests to observe the missing implementation, then implement transactional seed metadata, CRUD, UTF BOM decoding and paragraph-based chapter splitting.
- [x] Add six clearly attributed public-domain excerpts, with three initially on the shelf and all discoverable; do not claim full books.
- [x] Re-run repository and importer tests; inspect saved data after close/reopen.

## Task 3 — Independently implemented book-source engine

**Files:** `lib/domain/book_source.dart`, `lib/services/source_engine.dart`, `lib/services/source_importer.dart`, `test/source_engine_test.dart`, `test/fixtures/`, `docs/BOOK_SOURCES.md`, `examples/book-source.json`.

**Consumes:** `http.Client`, `BookSource`, domain Book/Chapter. **Produces:** `SourceEngine.search(source, keyword)`, `loadBook(source, searchResult)`, `loadChapter(source, chapter)`; `SourceImporter.parse(String)` returns validated source definitions.

- [x] Create HTML fixtures with result cards, a detail page, relative TOC links, and article paragraphs. Create a `MockClient` routing known fixture URLs.
- [x] Write the red end-to-end test using `https://books.example/search?q={{key}}`, `@CSS:.book`, `@CSS:a@text`, `@CSS:a@href`, `@CSS:#toc a`, and `@CSS:article@html`.
- [x] Test object/string rule maps, arrays, duplicate source identity, empty fields, forbidden schemes, `@js`, arbitrary `{{expression}}`, oversized bodies, 404 and timeouts.
- [x] Implement the validator and CSS accessors independently. Preserve paragraphs and line breaks; remove script/style content. Resolve links against response URL and reject unsafe schemes.
- [x] Implement bounded HTTP fetching and explicit errors. Load only requested chapters and persist successful chapter bodies.
- [x] Re-run all engine tests; document exact capability boundaries, CORS and GPL provenance.

## Task 4 — Complete user-facing reading flows

**Files:** `lib/main.dart`, `lib/app.dart`, `lib/application/app_controller.dart`, `lib/ui/theme.dart`, `lib/ui/app_shell.dart`, `lib/ui/components/book_cover.dart`, `lib/ui/screens/bookshelf_screen.dart`, `lib/ui/screens/discover_screen.dart`, `lib/ui/screens/sources_screen.dart`, `lib/ui/screens/profile_screen.dart`, `lib/ui/screens/reader_screen.dart`, `lib/ui/screens/notes_screen.dart`, `test/app_widget_test.dart`.

**Consumes:** AppRepository and SourceEngine. **Produces:** Responsive navigable app with persistent user actions, not static mock screens.

- [x] Add controller tests: add/remove/import book; source enable/disable; load cache before HTTP; save failure does not claim success.
- [x] Add widget tests for initial bookshelf, open reader, chapter switching, note creation, and theme/settings persistence.
- [x] Implement original book-cover artwork, wide left navigation / narrow bottom navigation, readable Chinese hierarchy, working search/sort/layout controls, empty and loading states.
- [x] Implement public catalogue and network search; show a per-source failure rather than replacing results with a generic blank screen.
- [x] Implement source import dialog and file picker, import capability errors, source settings, delete confirmation and offline-help text.
- [x] Implement reader with paragraph keys and anchor capture/restore; flush progress on close, lifecycle pause and chapter switch. Implement TOC, notes, font size, line spacing and three themes.
- [x] Run widget tests after each flow; use semantics labels for all icon-only controls.

## Task 5 — Build, browser verification, recovery closure

**Files:** `.claude/launch.json`, `README.md`, `docs/VERIFICATION.md`, `docs/PROGRESS.md`, `docs/task-state.json`.

- [x] Run `flutter analyze` and `flutter test`; fix causes of failures and rerun.
- [x] Build: `flutter build web --release --no-web-resources-cdn`.
- [x] Start the built Web app with Browser preview tools using a project launch configuration. Test at desktop and 390px width; inspect screenshots and console errors.
- [x] Exercise reading/TOC/settings/note flows, reload to prove persistence, import TXT and a controlled local HTTP source, then verify cached reading offline.
- [x] Inspect Android build prerequisites and attempt an APK when available; report missing SDK/licensing/network requirements precisely if unavailable.
- [x] Check `git diff --check`, source asset licensing, unsupported-feature disclosures, and final working tree.
- [x] Write verification evidence and running instructions. Mark runtime state completed only after the required Web build/tests/browser checks succeed; disable `read-pilot-watchdog` once complete.

## Completion record

Delivered the verified Web first release and complete Flutter platform project sources. Native packaging was checked but remains environment-blocked; checked inspection steps do not imply a successful APK, EXE, or iOS build. Exact automated coverage and browser evidence are recorded in `docs/VERIFICATION.md`. The implementation is left uncommitted on `feat/flutter-reader` per the no-automatic-publish constraint.

## Self-review

All product sections map to tasks 2–4. Toolchain placement, no-commit constraint, supported rule limits and persistent watchdog behavior are explicit. Native packaging is conditional on actual Android toolchain availability; it must not be described as tested merely because the Flutter Web build passes.
