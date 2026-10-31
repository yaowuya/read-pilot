# Runtime and State Tasks

- [x] **Task frontend-001: Persist the reader flow setting**

**Files:**
- Modify: `lib/domain/reader_settings.dart`
- Test: `test/domain_test.dart`
- Test: `test/repository_test.dart`

**Reasoning:**
- Pagination and scrolling need one backward-compatible persisted preference. It belongs with existing theme/font/line-height settings, not in `ReaderScreen` local state.

**Depends on:** None

**Interfaces:**
- Consumes: existing `ReaderSettings.fromJson`, `copyWith`, `toJson`.
- Produces: `enum ReaderFlow { paged, scrolling }`, `ReaderSettings.flow`, backward-compatible JSON.
- Contract checks: missing or invalid `flow` resolves to `paged`; copy/round-trip preserves explicit `scrolling`.

**Capability / Preservation Ownership:**
- `CAP-001`: setting portion.
- `PRES-001`: paragraph position format remains unchanged.
- Browser replay: owned by `frontend-009/E2E-READER-FLOW`.

**Step 1: Write the failing test**

Add tests equivalent to:

```dart
test('reader flow defaults to paged and round-trips scrolling', () {
  expect(ReaderSettings.fromJson(const {}).flow, ReaderFlow.paged);
  final settings = const ReaderSettings().copyWith(flow: ReaderFlow.scrolling);
  expect(ReaderSettings.fromJson(settings.toJson()).flow, ReaderFlow.scrolling);
});
```

**Step 2: Run test to verify it fails**

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test test/domain_test.dart test/repository_test.dart`
Expected: FAIL because `ReaderFlow` and `flow` do not exist.

**Step 3: Write minimal implementation**

Add the enum and field to constructor, `copyWith`, `fromJson`, and `toJson`. Use `ReaderFlow.values.firstWhere` with `orElse: () => ReaderFlow.paged`; do not add a migration or second settings store.

**Template/Script/Style Outline:**
- Template: N/A; domain task.
- Script/state: immutable value object with existing clamp behavior unchanged.
- Style: existing Dart formatting and concise public contract comment.

**Visual / UX Checks:**
- None in this task; `frontend-009` owns the visible selector.

**UI/E2E Lifecycle and Evidence:**
- Source reaches `SOURCE_READY`; no standalone UI case.

**Step 4: Run test to verify it passes**

Run the focused command from Step 2.
Expected: PASS with old settings and explicit scrolling round-trip.

**Step 5: Record completion without committing**

Update only this task marker and `.fp-execute/progress.md`. Do not commit or stage files.

---

- [x] **Task frontend-002: Implement deterministic viewport pagination**

**Files:**
- Create: `lib/ui/reader/reader_paginator.dart`
- Create: `test/reader_paginator_test.dart`

**Reasoning:**
- Character-count pages and one-paragraph pages fail for long paragraphs and variable viewports. A pure `TextPainter` paginator is the smallest accurate boundary and can be tested without the full screen.

**Depends on:** None

**Interfaces:**
- Consumes: chapter title, paragraphs, title/body `TextStyle`, max width/height, paragraph spacing and first-page metadata height.
- Produces: immutable `ReaderPageLayout` and `ReaderPage` values with text fragments and `anchorParagraphIndex`; lookup for page containing a paragraph.
- Contract checks: every non-empty character appears once in order; no measured page exceeds height; long paragraphs split; page lookup is stable.

**Capability / Preservation Ownership:**
- `CAP-001`: layout engine.
- `PRES-001`: page values expose paragraph anchors, never persisted page numbers.
- Browser replay: `frontend-009/E2E-READER-FLOW`.

**Step 1: Write the failing test**

Cover short paragraphs, a paragraph taller than one page, title reservation, viewport changes and anchor lookup. The core assertion is:

```dart
final layout = ReaderPaginator.paginate(
  title: '第一章',
  paragraphs: ['第一段', '很长的正文' * 200],
  maxWidth: 280,
  maxHeight: 420,
  bodyStyle: const TextStyle(fontSize: 22, height: 1.9),
  titleStyle: const TextStyle(fontSize: 26, height: 1.6),
);
expect(layout.pages.length, greaterThan(1));
expect(layout.pageForParagraph(1), inInclusiveRange(0, layout.pages.length - 1));
expect(layout.plainText, contains('很长的正文'));
```

**Step 2: Run test to verify it fails**

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test test/reader_paginator_test.dart`
Expected: FAIL because the paginator types do not exist.

**Step 3: Write minimal implementation**

Use `TextPainter` with the exact body style. Fill each page until the next fragment would exceed height; for an oversized paragraph, binary-search the largest substring that fits and continue from that character. Prefer whitespace/punctuation boundaries when backing off, but never drop characters. Keep results immutable and document why paragraph anchors, not page numbers, are exposed.

**Template/Script/Style Outline:**
- Template: N/A; pure layout helper.
- Script/state: no mutable global/cache state.
- Style: same text direction and styles as consumer; no arbitrary character-count constants.

**Visual / UX Checks:**
- No clipped final glyph; ordered text preserved; runtime check owned by `VIS-READER-PAPER`.

**UI/E2E Lifecycle and Evidence:**
- Source reaches `SOURCE_READY`; visible lifecycle owned by `frontend-009`.

**Step 4: Run test to verify it passes**

Run the focused command from Step 2.
Expected: PASS for all measurement, splitting and anchor cases.

**Step 5: Record completion without committing**

Update the unique task marker and progress ledger only.

---

- [x] **Task frontend-003: Normalize parsed chapter content safely**

**Files:**
- Create: `lib/services/source_runtime/content_normalizer.dart`
- Modify: `lib/services/source_engine.dart`
- Create: `test/content_normalizer_test.dart`
- Modify: `test/source_engine_test.dart`

**Reasoning:**
- Layout cleanup belongs after all content pages are aggregated. It must be deterministic and must not use ad-keyword guesses that can delete prose.

**Depends on:** None

**Interfaces:**
- Consumes: extracted paragraph strings and resolved chapter title.
- Produces: immutable normalized `List<String>`.
- Contract checks: Unicode spaces collapse, blank/duplicate adjacent paragraphs disappear, a leading duplicate chapter title disappears, ordinary text and safe `##pattern##replacement` output remain.

**Capability / Preservation Ownership:**
- `CAP-004`: complete.
- `PRES-002`: existing safe replacement subset and content limits remain.
- Browser replay: real 8027 integration replay in `frontend-011`.

**Step 1: Write the failing test**

```dart
test('normalizes whitespace without keyword-based deletion', () {
  final result = const ContentNormalizer().normalize(
    [' 第一章 ', '  正文\u00a0 内容  ', '', '广告也是故事的一部分'],
    chapterTitle: '第一章',
  );
  expect(result, ['正文 内容', '广告也是故事的一部分']);
});
```

Add an engine test proving paginated content is normalized only after aggregation.

**Step 2: Run test to verify it fails**

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test test/content_normalizer_test.dart test/source_engine_test.dart`
Expected: FAIL because `ContentNormalizer` is missing and engine output retains duplicate/blank content.

**Step 3: Write minimal implementation**

Create one public, documented pure class. Normalize CR/LF and Unicode horizontal whitespace, split embedded blank lines, trim, remove adjacent exact duplicates, and remove only a normalized leading title equal to the chapter title. Call it once before constructing the final `Chapter`. Keep RuleInterpreter replacement behavior unchanged.

**Template/Script/Style Outline:**
- Template: N/A.
- Script/state: pure function; no source-specific hidden state.
- Style: no ad list, probabilistic rule or remote script.

**Visual / UX Checks:**
- Presentation indentation is not stored here; `frontend-009` owns display formatting.

**UI/E2E Lifecycle and Evidence:**
- Non-UI runtime task; source-ready evidence is focused tests and live integration replay.

**Step 4: Run test to verify it passes**

Run the focused command from Step 2.
Expected: PASS with no regression in existing source-engine tests.

**Step 5: Record completion without committing**

Update task marker and progress ledger only.

---

- [x] **Task frontend-004: Add safe binary transport and cover loading**

**Files:**
- Modify: `lib/services/source_runtime/source_transport.dart`
- Modify: `lib/services/source_engine.dart`
- Modify: `test/source_transport_test.dart`
- Modify: `test/source_engine_test.dart`

**Reasoning:**
- `Image.network` would bypass the existing origin/private-address/redirect limits. Reusing transport with optional text decoding is the smallest safe cover path.

**Depends on:** None

**Interfaces:**
- Consumes: existing `RequestPlan`, `SourceNetworkPolicy`, source headers and same-origin cover URL.
- Produces: `execute(..., bool decodeText = true)` and `SourceEngine.loadCover` / `refreshBookInfo`.
- Contract checks: default text behavior unchanged; binary bytes returned without charset decode; non-image, cross-origin, private, oversized and HTTP failures reject.

**Capability / Preservation Ownership:**
- `CAP-003`: cover runtime portion.
- `PRES-002`: network policy.
- Browser replay: `frontend-010/E2E-SOURCE-SWITCH`.

**Step 1: Write the failing test**

Add transport tests with invalid UTF-8 image bytes and engine tests for `image/png` success plus `text/html` rejection:

```dart
final response = await transport.execute(
  RequestPlan(uri: Uri.parse('https://books.example/cover.png')),
  policy: SourceNetworkPolicy(allowedOrigins: {'https://books.example'}),
  decodeText: false,
);
expect(response.bytes, [0x89, 0x50, 0x4e, 0x47]);
```

**Step 2: Run test to verify it fails**

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test test/source_transport_test.dart test/source_engine_test.dart`
Expected: FAIL because `decodeText`, `loadCover` and `refreshBookInfo` do not exist.

**Step 3: Write minimal implementation**

Skip `_decodeText` only when explicitly requested and return `text: ''` while preserving `bytes`, headers and all policy checks. In `loadCover`, build the request with existing planner/source headers, enforce same origin via the engine link policy, require non-empty `image/*`, and return bytes. Refactor detail extraction once so `refreshBookInfo` does not load the TOC and `loadBook` does not duplicate parsing.

**Template/Script/Style Outline:**
- Template: N/A.
- Script/state: no cache or direct HttpClient; existing transport owns lifecycle.
- Style: reason comments at binary decode bypass and image media-type gate.

**Visual / UX Checks:**
- Bytes are not displayed until `frontend-010`; generated cover fallback remains.

**UI/E2E Lifecycle and Evidence:**
- Source-ready runtime contract; real browser cover evidence owned later.

**Step 4: Run test to verify it passes**

Run the focused command from Step 2.
Expected: PASS including all existing transport redirect/timeout/encoding tests.

**Step 5: Record completion without committing**

Update task marker and progress ledger only.

---

- [x] **Task frontend-005: Model source switching as a pure mapping**

**Files:**
- Modify: `lib/domain/book.dart`
- Create: `lib/domain/source_switch.dart`
- Create: `test/source_switch_mapper_test.dart`
- Modify: `test/domain_test.dart`

**Reasoning:**
- Mapping chapters, current position and bookmarks must be independent of network and storage so it is deterministic, immutable and testable.

**Depends on:** None

**Interfaces:**
- Consumes: current `Book`, fully loaded replacement `Book`, current `Bookmark` list and optionally loaded replacement current chapter.
- Produces: `Book.rebindSource`, `Bookmark.copyWithPosition`, immutable `SourceSwitchPlan`.
- Contract checks: stable book/bookmark IDs and user metadata; title-normalized mapping; nearest-index fallback; paragraph text match when available; immutable collections.

**Capability / Preservation Ownership:**
- `CAP-003`: mapping portion.
- `PRES-001`: logical location and bookmarks.
- Browser replay: `frontend-010/E2E-SOURCE-SWITCH`.

**Step 1: Write the failing test**

Cover exact normalized title mapping, duplicate titles, missing-title fallback, current paragraph text match, bookmark remap and immutable inputs. Example:

```dart
final plan = const SourceSwitchMapper().plan(
  current: currentBookAt('第 10 章 归来', paragraph: 2),
  replacement: replacementBookWith('第十章 归来'),
  bookmarks: [bookmarkAt(chapter: 0, paragraph: 1)],
);
expect(plan.book.id, current.id);
expect(plan.book.sourceId, replacement.sourceId);
expect(plan.book.position.chapterIndex, 0);
expect(plan.bookmarks.single.bookId, current.id);
```

**Step 2: Run test to verify it fails**

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test test/source_switch_mapper_test.dart test/domain_test.dart`
Expected: FAIL because mapping and rebind APIs are missing.

**Step 3: Write minimal implementation**

Normalize Unicode whitespace, punctuation and Chinese/Arabic chapter-number prefixes without fuzzy edit-distance guessing. Build a stable first-match map; fall back to clamped old index. Preserve book ID, dates, finished state and existing cover when replacement has none. Copy all lists defensively per P001.

**Template/Script/Style Outline:**
- Template: N/A.
- Script/state: pure immutable domain values.
- Style: public contract comments explain stable identity and mapping fallback.

**Visual / UX Checks:**
- None directly; candidate labels and selected source appear in `frontend-010`.

**UI/E2E Lifecycle and Evidence:**
- Source-ready domain contract; business-flow evidence owned by `frontend-010`.

**Step 4: Run test to verify it passes**

Run the focused command from Step 2.
Expected: PASS for exact and fallback mappings and immutability.

**Step 5: Record completion without committing**

Update task marker and progress ledger only.

---

- [x] **Task frontend-006: Persist source switches atomically and reject stale chapter writes**

**Files:**
- Modify: `lib/data/app_repository.dart`
- Modify: `test/repository_test.dart`

**Reasoning:**
- A source switch changes a book and its notes together. Concurrent old-source chapter downloads must not write after the switch.

**Depends on:** `frontend-005`

**Interfaces:**
- Consumes: `SourceSwitchPlan`; cache request with expected source/chapter IDs.
- Produces: `replaceBookSource(Book, List<Bookmark>)`; guarded `cacheChapter` result.
- Contract checks: one transaction; injected failure rolls back all records; stale source/chapter returns without write; current write still succeeds.

**Capability / Preservation Ownership:**
- `CAP-003`: persistence portion.
- `PRES-002`: publish/rollback and stale-write safety.
- Browser replay: `frontend-010/E2E-SOURCE-SWITCH`.

**Step 1: Write the failing test**

Add repository tests that switch one book plus two bookmarks and a transaction-failure test. Add a race test: after replacing source/chapters, call `cacheChapter` with the old expected IDs and assert the new record is unchanged.

**Step 2: Run test to verify it fails**

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test test/repository_test.dart`
Expected: FAIL because transaction and guard APIs are absent.

**Step 3: Write minimal implementation**

Use the existing `database.transaction`. Put the book record and only the supplied same-book bookmarks. Change `cacheChapter` to accept `expectedSourceId` and `expectedChapterId`; re-read the book in transaction and compare both before replacing a chapter. Return a boolean so the controller knows whether persistence occurred.

**Template/Script/Style Outline:**
- Template: N/A.
- Script/state: Sembast transaction only; no new store/index.
- Style: reason comments document why late writes are rejected and why state publishes after transaction.

**Visual / UX Checks:**
- None directly.

**UI/E2E Lifecycle and Evidence:**
- Persistence contract feeds `frontend-010` business-flow evidence.

**Step 4: Run test to verify it passes**

Run the focused command from Step 2.
Expected: PASS for success, rollback and stale-write cases.

**Step 5: Record completion without committing**

Update task marker and progress ledger only.

---

- [x] **Task frontend-007: Orchestrate candidates, switching and cover refresh**

**Files:**
- Modify: `lib/application/app_controller.dart`
- Modify: `test/controller_test.dart`

**Reasoning:**
- UI needs one application boundary. Network, mapping and persistence order must stay outside widgets and publish only after durable success.

**Depends on:** `frontend-003`, `frontend-004`, `frontend-005`, `frontend-006`

**Interfaces:**
- Consumes: existing `searchSources`, engine detail/chapter/cover APIs, mapper and repository transaction.
- Produces: `findSourceCandidates`, `switchBookSource`, `refreshBookCover`, `loadBookCover`.
- Contract checks: current source excluded; title exact/author rank stable; failed load/transaction leaves `_books` and `_bookmarks` unchanged; stale chapter result not published; successful refresh persists before notify.

**Capability / Preservation Ownership:**
- `CAP-003`: application orchestration.
- `PRES-002`: persistence-before-publish.
- Browser replay: `frontend-010/E2E-SOURCE-SWITCH`.

**Step 1: Write the failing test**

Use existing fake engine/repository patterns to verify candidate filtering, author ordering, switch call order, current-chapter preload, rollback, state notification timing, cover refresh success/failure and guarded chapter cache.

```dart
final candidates = await controller.findSourceCandidates(book.id);
expect(candidates.map((item) => item.sourceId), ['https://exact-author.example']);
await controller.switchBookSource(book.id, candidates.single);
expect(controller.book(book.id)!.id, book.id);
expect(controller.book(book.id)!.sourceId, candidates.single.sourceId);
```

**Step 2: Run test to verify it fails**

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test test/controller_test.dart`
Expected: FAIL because controller APIs and guarded cache call are missing.

**Step 3: Write minimal implementation**

Search enabled sources through the existing scheduler. Normalize only for matching/sorting. During switch, load target book, map current chapter, load that target chapter, create the plan, persist, then replace controller state. Pass expected IDs to chapter cache. For cover refresh, validate bytes before saving a new URL; never clear a working URL on failure.

**Template/Script/Style Outline:**
- Template: N/A.
- Script/state: existing ChangeNotifier; no second store or background task.
- Style: public method contract comments and non-obvious operation-order comments.

**Visual / UX Checks:**
- Exposed errors remain readable through existing `errorMessage` path.

**UI/E2E Lifecycle and Evidence:**
- Source-ready application contract; `frontend-010` owns interaction and real E2E.

**Step 4: Run test to verify it passes**

Run the focused command from Step 2.
Expected: PASS with notifications only after persistence.

**Step 5: Record completion without committing**

Update task marker and progress ledger only.
