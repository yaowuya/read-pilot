# UI and Verification Tasks

- [ ] **Task frontend-008: Replace source preview with one-step import**

**Files:**
- Modify: `lib/ui/components/source_import_sheet.dart`
- Modify: `test/sources_screen_test.dart`
- Create: `.fp-execute/visual/frontend-008/VIS-IMPORT-DIRECT/manifest.md`
- Create: `.fp-execute/e2e/frontend-008/E2E-IMPORT-DIRECT/coverage-matrix.md`

**Reasoning:**
- Product scope removes preview and per-source selection, but validation, cancellation and atomic commit must remain. The UI owns only orchestration and feedback.

**Depends on:** None

**Interfaces:**
- Consumes: `prepareSourceImport`, `commitSourceImport`, `SourceImportCommitResult`.
- Produces: one `_import` handler and a sheet result containing added/updated counts.
- Contract checks: no preview/checklist; prepare before commit; all preview sources committed; error keeps sheet open; cancel still aborts URL prepare.

**Capability / Preservation Ownership:**
- `CAP-002`: complete.
- `PRES-002`: validation and transaction behavior.
- Browser replay: `VIS-IMPORT-DIRECT`, `E2E-IMPORT-DIRECT`.

**Step 1: Write the failing test**

Update the widget test controller to record prepare/commit order. Assert a single confirm tap calls both, the preview source names never render, and commit failure leaves the sheet visible:

```dart
await tester.tap(find.text('确认导入'));
await tester.pumpAndSettle();
expect(controller.calls, ['prepare', 'commit']);
expect(find.text('待导入书源'), findsNothing);
expect(find.byType(Checkbox), findsNothing);
```

**Step 2: Run test to verify it fails**

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test test/sources_screen_test.dart`
Expected: FAIL because the first tap only prepares and renders preview.

**Step 3: Write minimal implementation**

Before source edits, create the approved static SVG for `VIS-IMPORT-DIRECT` from `05-interfaces.md`, render `reference.png`, and write its provenance manifest. Then remove `_preview`, `_selectedSourceIds` and preview widgets. Keep input modes, file reading, busy/error/cancel state. The confirm handler builds input, awaits prepare, awaits commit with all sources, and pops only on success.

**Template Outline:**
- `SingleChildScrollView > mode selector > input > inline error > action row`.
- No preview card, source checkbox or second commit button.

**Script/State Outline:**
- Local state: mode, controllers, file label, error, busy, abort.
- One async handler; disable mode/input/actions while busy; dispose completes abort.

**Style Outline:**
- Existing padding 24, Material 3 primary button and error text.
- Reference SVG uses only confirmed hierarchy/tokens, not new visual choices.

**Visual / UX Checks:**
- One primary action “确认导入”.
- No preview or source checklist in any mode.
- Busy, validation error and cancellation remain visible.
- Visual Evidence case: `VIS-IMPORT-DIRECT`.

**UI/E2E Lifecycle and Evidence:**
- UI Delivery Level: business-flow; case `E2E-IMPORT-DIRECT`.
- Stages: `SOURCE_READY -> STATIC_UI_READY -> VISUAL_REVIEW_PASS -> INTERACTION_READY -> FRONTEND_E2E_PASS`.
- Visual review: independent read-only reviewer compares reference/current artifacts and records verdict.
- E2E: real Web runtime; enter deterministic non-sensitive source JSON through the UI, confirm, observe actual Sembast-backed source row, then delete it through the UI. `Mocked Core API: false`; no storage injection or intercepted request.
- Evidence: `.fp-execute/e2e/frontend-008/E2E-IMPORT-DIRECT/` with command/tool, environment, timestamps, attempts, artifacts and coverage matrix.
- BLOCKED handling: if browser cannot interact with Flutter semantics after 3 attempts, record BLOCKED; do not replace with widget-test evidence.

**Step 4: Run test and real UI verification**

Run the focused test from Step 2.
Expected: PASS.

Run: `"D:/ProgramFiles/flutter/bin/flutter.bat" build web --release --no-web-resources-cdn`, then `preview_start(read-pilot-web)` and the preview tools listed in the case manifest.
Expected: visual reviewer returns `VISUAL_REVIEW_PASS`; real import and UI cleanup reach `FRONTEND_E2E_PASS` with no console errors.

**Step 5: Record completion without committing**

Update task marker and progress ledger after both visual and E2E gates pass. Do not commit.

---

- [ ] **Task frontend-009: Integrate horizontal paging and reader preferences**

**Files:**
- Modify: `lib/ui/screens/reader_screen.dart`
- Modify: `lib/ui/components/reader_preferences.dart`
- Modify: `test/reader_recovery_test.dart`
- Modify: `test/app_widget_test.dart`
- Create: `.fp-execute/visual/frontend-009/VIS-READER-PAPER/manifest.md`
- Create: `.fp-execute/e2e/frontend-009/E2E-READER-FLOW/coverage-matrix.md`

**Reasoning:**
- This task connects the tested paginator and setting to the real reader while preserving save failure, bookmarks, notes, chapter navigation and vertical fallback.

**Depends on:** `frontend-001`, `frontend-002`

**Interfaces:**
- Consumes: `ReaderSettings.flow`, `ReaderPaginator`, existing save/load/jump methods.
- Produces: `PagedReader` UI path, retained scrolling path, `SegmentedButton<ReaderFlow>`.
- Contract checks: default paged; scroll selectable; both persist paragraph anchors; cross-chapter swipe saves first; layout changes restore anchor.

**Capability / Preservation Ownership:**
- `CAP-001`: complete.
- `PRES-001`: complete.
- `PRES-003`: themes, local books and notes remain.
- Browser replay: `VIS-READER-PAPER`, `E2E-READER-FLOW`.

**Step 1: Write the failing test**

Extend reader tests to open a multi-page chapter, drag left, assert persisted paragraph advances, reopen and assert the same paragraph/page. Toggle scrolling and assert a vertical `Scrollable` path. Add settings failure rollback coverage.

```dart
expect(find.byKey(const Key('reader-paged-view')), findsOneWidget);
await tester.drag(find.byKey(const Key('reader-paged-view')), const Offset(-300, 0));
await tester.pumpAndSettle();
expect(repository.savedPosition.paragraphIndex, greaterThan(0));
```

**Step 2: Run test to verify it fails**

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test test/reader_recovery_test.dart test/app_widget_test.dart`
Expected: FAIL because reader is only a vertical `SingleChildScrollView` and no flow control exists.

**Step 3: Write minimal implementation**

Copy the approved user image to the visual evidence reference path and document the mask/acceptance rule before source edits. Refactor reader body into paged and scrolling builders without changing load/save error handling. Cache layout by chapter/viewport/font/line-height, initialize `PageController` from paragraph anchor, debounce page changes through existing persistence, and use leading/trailing sentinel indices for chapter transitions. Prefix display paragraphs with two ideographic spaces and use justified text without mutating stored content.

**Template Outline:**
- `ReaderScreen > AppBar > save banner > flow-specific Expanded`.
- Paged: `PageView.builder > SelectionArea > constrained page content`.
- Preferences: existing panel plus one segmented flow row.

**Script/State Outline:**
- Existing `_chapterIndex`, `_paragraphIndex`, `_pendingFinished`, `_saveTimer` remain authority.
- New page controller/layout cache are invalidated by chapter, width, height, font or line height.
- No persisted page index.

**Style Outline:**
- Paper `#F4EFDC`; ink `#34332F`; current dark/light values unchanged.
- Horizontal padding 24/48 at 650 breakpoint; max width 760.

**Visual / UX Checks:**
- Background/AppBar exact paper token.
- No clipped glyph or horizontal overflow at 375x812 and desktop.
- Swipe advances one page; resize/font change preserves paragraph.
- Flow selector persists and scroll fallback behaves as before.
- Visual Evidence case: `VIS-READER-PAPER`.

**UI/E2E Lifecycle and Evidence:**
- UI Delivery Level: business-flow; case `E2E-READER-FLOW`.
- Full lifecycle through visual and real E2E pass.
- Real browser flow uses built-in sample book through shelf UI, switches mode, swipes, exits/reopens, verifies setting and logical position in real IndexedDB, then restores the prior flow through UI. `Mocked Core API: false`.
- Evidence and coverage matrix under `.fp-execute/e2e/frontend-009/E2E-READER-FLOW/`.
- BLOCKED handling: Flutter semantic interaction or persistence failure after 3 attempts remains BLOCKED; widget tests cannot waive it.

**Step 4: Run test and real UI verification**

Run focused tests from Step 2, then the Web build/preview sequence.
Expected: tests PASS; independent reviewer returns visual pass; real reopen reaches `FRONTEND_E2E_PASS` with saved paragraph and cleanup.

**Step 5: Record completion without committing**

Update task marker/progress only after required evidence exists.

---

- [ ] **Task frontend-010: Add safe covers, source actions and candidate sheet**

**Files:**
- Modify: `lib/ui/components/book_cover.dart`
- Modify: `lib/ui/components/book_details.dart`
- Create: `lib/ui/components/source_switch_sheet.dart`
- Create: `test/book_details_test.dart`
- Modify: `test/app_widget_test.dart`
- Create: `integration_test/live_source_switch_test.dart`
- Create: `.fp-execute/visual/frontend-010/VIS-SOURCE-SWITCH/manifest.md`
- Create: `.fp-execute/e2e/frontend-010/E2E-SOURCE-SWITCH/coverage-matrix.md`

**Reasoning:**
- Users need discoverable manual source and cover actions, but widgets must not implement matching, transport or persistence logic.

**Depends on:** `frontend-004`, `frontend-007`

**Interfaces:**
- Consumes: controller candidate/switch/cover APIs, current `BookCover` generated art, existing details state.
- Produces: safe image rendering, remote-only actions, `SourceSwitchSheet` state UI.
- Contract checks: local/sample books hide source actions; generated cover fallback has no layout shift; candidates show source/title/author; failure keeps original book and sheet retryable.

**Capability / Preservation Ownership:**
- `CAP-003`: visible completion.
- `PRES-003`: generated cover and local books.
- Browser replay: `VIS-SOURCE-SWITCH`, `E2E-SOURCE-SWITCH`.

**Step 1: Write the failing test**

Create widget tests with a controller test double at the application boundary. Verify remote actions, local hiding, candidate loading/empty/partial-error/fatal-error/success, switch busy state and cover fallback. Do not mock transport inside the real E2E case.

```dart
expect(find.text('换源'), findsOneWidget);
await tester.tap(find.text('换源'));
await tester.pump();
expect(find.byKey(const Key('source-switch-loading')), findsOneWidget);
```

Add a live integration test using the existing 8027 source and the user-supplied 1325 source endpoint. Search `九星霸体诀`; if both safely expose a matching candidate, complete switch/detail/content checks. A live environment failure is reported, not replaced with `MockClient`.

**Step 2: Run test to verify it fails**

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test test/book_details_test.dart test/app_widget_test.dart`
Expected: FAIL because actions, sheet and network cover path are missing.

**Step 3: Write minimal implementation**

Create the approved static SVG/reference for `VIS-SOURCE-SWITCH` before source edits. Convert `BookCover` to stateful safe-byte loading with `Image.memory(BoxFit.cover)` and unchanged generated fallback. Add remote-only outlined actions to `BookDetails`. Implement a max-width-600 modal sheet with cancellation, loading, empty, partial failure, fatal error, retry and disabled switching states. On success close the sheet and let AnimatedBuilder show the persisted book.

**Template Outline:**
- Details: existing cover/metadata, `Wrap` of secondary actions, description, chapter status, primary read button.
- Sheet: title/close, status area, candidate list, retry/cancel.

**Script/State Outline:**
- `BookCover` stores only current Future and refreshes when URL changes.
- Sheet owns abort completer, busy/error/candidates and selected candidate.
- Controller remains the only network/persistence boundary.

**Style Outline:**
- Existing 28 padding, AppColors, Material 3 outlined/filled hierarchy.
- Candidate source is secondary text; row remains readable at 375 px.

**Visual / UX Checks:**
- Actions wrap without overflow; local books show none.
- Sheet max width 600, every state has readable feedback.
- Network cover fills existing shape; fallback preserves title/author art.
- Visual Evidence case: `VIS-SOURCE-SWITCH`.

**UI/E2E Lifecycle and Evidence:**
- UI Delivery Level: business-flow; case `E2E-SOURCE-SWITCH`.
- Full lifecycle through visual and real E2E pass.
- Use real Web UI, real source import/network and real IndexedDB. Import sources, discover/add the book, open details, switch source, reopen/read and delete test-created book/source through UI. `Mocked Core API: false`.
- Evidence under `.fp-execute/e2e/frontend-010/E2E-SOURCE-SWITCH/` records source URLs, environment, attempts, result and cleanup without secrets.
- BLOCKED handling: if the two approved live sources lack a common result or CORS/network prevents safe browser execution after 3 attempts, mark the case and final review BLOCKED. Do not use route interception, fixture response or direct database writes.

**Step 4: Run test and real UI verification**

Run focused tests from Step 2.
Expected: PASS.

Run live integration test with `"D:/ProgramFiles/flutter/bin/flutter.bat" test integration_test/live_source_switch_test.dart` and then Web preview replay.
Expected: live path and visual/E2E gates pass; otherwise exact real-environment blocker is recorded.

**Step 5: Record completion without committing**

Only mark complete if all required gates pass. A blocked live case keeps this task unchecked.

---

- [ ] **Task frontend-011: Run full verification and finalize evidence**

**Files:**
- Modify: `fp-docs/changes/reader-paging-source-switching/tasks/frontend/10-runtime-tasks.md`
- Modify: `fp-docs/changes/reader-paging-source-switching/tasks/frontend/20-ui-verification-tasks.md`
- Modify: `fp-docs/changes/reader-paging-source-switching/.fp-execute/progress.md`
- Verify: `.fp-execute/visual/**` and `.fp-execute/e2e/**`

**Reasoning:**
- Completion requires one fresh, whole-snapshot verification after all task-local cycles, plus evidence/lifecycle consistency and engineering-quality self-review.

**Depends on:** `frontend-001`, `frontend-002`, `frontend-003`, `frontend-004`, `frontend-005`, `frontend-006`, `frontend-007`, `frontend-008`, `frontend-009`, `frontend-010`

**Interfaces:**
- Consumes: all task outputs and evidence contracts in `05-interfaces.md`.
- Produces: fresh verification output, reconciled checkboxes/ledger, final review-ready branch.
- Contract checks: no unchecked dependency, duplicate task ID, stale progress claim, missing evidence artifact, invalid mock, source change without test/comment, or unreviewed visual case.

**Capability / Preservation Ownership:**
- `CAP-001`–`CAP-004`: aggregate verification.
- `PRES-001`–`PRES-003`: aggregate verification.
- Browser replay: validates all three case directories; owns no new visual case.

**Step 1: Confirm task and evidence state before commands**

Parse all unique owner checkboxes and progress entries. Confirm each visual/E2E case has manifest, artifacts, coverage matrix, lifecycle result and cleanup record. Do not convert BLOCKED/CANNOT_VERIFY to pass.

**Step 2: Run formatting and static analysis**

Run: `"D:/ProgramFiles/flutter/bin/dart.bat" format --output=none --set-exit-if-changed lib test integration_test`
Expected: exit 0, no changed files.

Run: `"D:/ProgramFiles/flutter/bin/flutter.bat" analyze`
Expected: `No issues found!`

**Step 3: Run the complete automated suite**

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test`
Expected: all tests pass with zero failures.

Run: `NO_PROXY='localhost,127.0.0.1,::1' no_proxy='localhost,127.0.0.1,::1' "D:/ProgramFiles/flutter/bin/flutter.bat" test integration_test/live_8027_test.dart integration_test/live_source_switch_test.dart`
Expected: both live tests pass; a real external failure is reported as BLOCKED, never hidden.

**Step 4: Build and replay the real Web UI**

Run: `"D:/ProgramFiles/flutter/bin/flutter.bat" build web --release --no-web-resources-cdn`
Expected: release build succeeds.

Use `preview_start(read-pilot-web)` and Browser preview tools to replay all case manifests at desktop and 375x812. Check server/browser console and failed network requests. Independent read-only visual review must return `VISUAL_REVIEW_PASS`; required real E2E must return `FRONTEND_E2E_PASS`.

**Step 5: Diff and engineering-quality self-review**

Review only the actual change diff. Verify public object contracts, transaction/竞态/security reason comments, no unrelated refactor, no direct network-image bypass, no old 1 MiB regression, and no untracked generated runtime output outside owned evidence paths. Run `git diff --check` for changed paths.

**Step 6: Reconcile completion without committing**

Mark this task complete only if all required tests, visual and E2E gates pass and no BLOCKED case remains. Update progress ledger once. Do not commit, push, merge or archive.
