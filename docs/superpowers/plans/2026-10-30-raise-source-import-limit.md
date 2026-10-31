# Raise Source Import Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise the shared book-source JSON import limit from 1 MiB to 10 MiB without weakening the existing source-count or JSON-depth safeguards.

**Architecture:** Keep one shared byte-limit constant in `SourceImporter`. `SourceImportService` already uses that constant as its default network response limit, so changing the shared value keeps pasted, file-based, and URL imports consistent.

**Tech Stack:** Dart, Flutter test, `package:http/testing.dart`

## Global Constraints

- Interpret “10M” as 10 MiB: `10 * 1024 * 1024` bytes.
- Keep the maximum source count at 500 and maximum JSON depth at 64.
- Preserve configurable `SourceImportService.maxResponseBytes` behavior used by focused tests.
- Do not commit or push unless the user explicitly asks.

---

### Task 1: Lock the new default behavior with a regression test

**Files:**
- Modify: `test/source_import_service_test.dart`

**Interfaces:**
- Consumes: `SourceImportService.prepare(SourceImportInput)` and the existing `_sourceJson()` fixture.
- Produces: A regression test proving a valid URL payload larger than 1 MiB is accepted by the default configuration.

- [ ] **Step 1: Write the failing test**

Add a test that creates a valid source object with an unused padding field large enough to push the UTF-8 response beyond 1 MiB, serves it through `MockClient`, and expects one parsed source:

```dart
test('accepts a URL import larger than the former 1 MiB limit', () async {
  final payload = jsonEncode({
    ..._sourceJson(name: '大型书源'),
    'padding': 'x' * (1024 * 1024),
  });
  expect(utf8.encode(payload).length, greaterThan(1024 * 1024));

  final service = SourceImportService(
    client: MockClient(
      (_) async => http.Response(
        payload,
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  );
  addTearDown(service.close);

  final preview = await service.prepare(
    SourceImportInput.url(Uri.parse('https://feed.example/large-source.json')),
  );

  expect(preview.sources.single.name, '大型书源');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
flutter test test/source_import_service_test.dart --plain-name "accepts a URL import larger than the former 1 MiB limit"
```

Expected: FAIL with `SourceImportErrorKind.tooLarge` under the current 1 MiB default.

### Task 2: Raise the shared limit and keep documentation accurate

**Files:**
- Modify: `lib/services/source_importer.dart:11-17`
- Modify: `docs/SOURCE_COMPATIBILITY.md:40`
- Modify: `docs/BOOK_SOURCES.md:53`
- Modify: `docs/superpowers/plans/2026-10-28-read-pilot.md:16`

**Interfaces:**
- Consumes: `SourceImporter.maxBytes`, already used by `SourceImportService` as its default `maxResponseBytes`.
- Produces: A 10 MiB default for text, file, and URL source imports.

- [ ] **Step 1: Implement the minimal shared-constant change**

Change the importer constant and parser message:

```dart
static const maxBytes = 10 * 1024 * 1024;
```

```dart
throw const FormatException('书源 JSON 不能超过 10 MiB。');
```

- [ ] **Step 2: Update active and historical requirement documentation**

Replace the source JSON limit references from `1 MiB` to `10 MiB` while leaving the unrelated 2 MiB runtime-response and TXT limits unchanged.

- [ ] **Step 3: Run the focused tests**

Run:

```bash
flutter test test/source_import_service_test.dart
```

Expected: PASS, including the new default-limit regression test and the existing configurable-limit rejection test.

- [ ] **Step 4: Run importer and screen regression coverage**

Run:

```bash
flutter test test/source_engine_test.dart test/sources_screen_test.dart test/repository_test.dart
```

Expected: PASS with no source-import regressions.
