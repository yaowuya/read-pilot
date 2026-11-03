# Frontend Interface and Visual Contract

## Capability and Preservation Mapping

| Capability / Preservation ID | Required observable result | Owner task | Runtime replay / visual case | Completion rule |
| --- | --- | --- | --- | --- |
| `CAP-001` | 阅读器支持真实左右分页并持久化模式和段落位置 | `frontend-009` | `VIS-READER-PAPER` / `E2E-READER-FLOW` | 视觉通过且真实 IndexedDB 恢复通过 |
| `CAP-002` | 导入点击一次即校验并提交，不显示预览 | `frontend-008` | `VIS-IMPORT-DIRECT` / `E2E-IMPORT-DIRECT` | UI 无 preview，真实来源记录创建并经 UI 清理 |
| `CAP-003` | 远程书可搜索候选、手动换源并刷新封面 | `frontend-010` | `VIS-SOURCE-SWITCH` / `E2E-SOURCE-SWITCH` | 真实来源切换成功；无可用双源环境则 BLOCKED |
| `CAP-004` | 正文按确定性规则整理且不误删内容 | `frontend-003` | unit/runtime chapter replay | fixture 与真实 8027 章节均无空段和重复标题 |
| `PRES-001` | 阅读位置仍以章节和段落为锚点 | `frontend-009` | `E2E-READER-FLOW` before/after | 重新打开仍位于同一逻辑段落 |
| `PRES-002` | 书源请求安全边界和失败不发布状态 | `frontend-004`, `frontend-006`, `frontend-007` | transport/controller/repository tests | 所有负向用例通过 |
| `PRES-003` | 本地书、样例节选、明亮/夜间主题和生成封面保持可用 | `frontend-009`, `frontend-010` | widget/browser replay | 不出现来源操作；回退与主题通过 |

## End-local Interface Ledger

| Contract | Owner Task | Exact shape / behavior | Consumers | Verification |
| --- | --- | --- | --- | --- |
| `ReaderFlow` | `frontend-001` | `enum ReaderFlow { paged, scrolling }`；fromJson 缺失/未知回退 `paged` | preferences、reader | domain/repository tests |
| `ReaderPaginator` | `frontend-002` | 输入 title/paragraphs/style/viewport；输出不可变 pages，每页含首段锚点和文本片段 | `PagedReader` | `reader_paginator_test.dart` |
| `ContentNormalizer` | `frontend-003` | 输入段落和 chapterTitle；只处理 Unicode 空白、空段、连续重复和重复标题 | source engine | `content_normalizer_test.dart` |
| `SourceTransport.execute(decodeText)` | `frontend-004` | 默认 `true` 保持文本行为；`false` 返回 bytes 且不做 charset 解码 | source engine cover | transport tests |
| `Book.rebindSource` | `frontend-005` | 保留 stable id/用户状态，替换来源/详情/目录/封面/映射位置 | mapper、controller | domain/mapper tests |
| `SourceSwitchMapper.plan` | `frontend-005` | 规范化章节名，映射 position/bookmarks；当前段可用时匹配规范化文本 | controller | mapper tests |
| `AppRepository.replaceBookSource` | `frontend-006` | 一个 Sembast 事务写 book 与相关 bookmarks | controller | rollback test |
| `AppRepository.cacheChapter` guard | `frontend-006` | 只有 `expectedSourceId + expectedChapterId` 仍匹配才写入 | controller | stale write test |
| `findSourceCandidates` | `frontend-007` | 搜索启用源，排除 current，书名精确匹配，作者相同优先 | source switch sheet | controller tests |
| `switchBookSource` | `frontend-007` | 先加载目标，后持久化，最后发布；失败保持原状态 | details/sheet | controller tests |
| `refreshBookCover` / `loadBookCover` | `frontend-007` | 同源安全字节，`image/*`，失败不覆盖现有封面 | cover/details | engine/controller tests |
| Source import submit | `frontend-008` | 单 handler 顺序调用 prepare/commit，commit 全部 sources | source screen | widget/E2E |
| Reader UI | `frontend-009` | flow selector + paged/scroll view + paragraph persistence | app route | widget/E2E |
| Source management UI | `frontend-010` | details actions + candidate sheet + safe cover fallback | app shell | widget/E2E |

## Component Tree and Template Outline

```text
ReaderScreen
├─ AppBar
└─ LayoutBuilder
   ├─ save-error banner
   └─ ReaderFlow.paged -> PagedReader(PageView -> SelectionArea -> page content)
      ReaderFlow.scrolling -> existing scrolling chapter view

SourceImportSheet
├─ mode selector
├─ text/file/url input
├─ inline error
└─ primary confirm/cancel actions

BookDetails
├─ BookCover(FutureBuilder<Image.memory> -> generated fallback)
├─ metadata and description
├─ Wrap(refresh cover, change source)
├─ primary read/add button
└─ SourceSwitchSheet(modal)
   ├─ loading / empty / error / partial-error summary
   └─ candidate ListView
```

## State, API, Route, Interaction and Style Contracts

- Global state remains `AppController extends ChangeNotifier`; component busy/error/cancel/page state remains local.
- No new route. Reader route remains `/read/<encoded-book-id>`; details remain current sheet/panel.
- `ReaderPaginator` and `ContentNormalizer` are pure and deterministic.
- Source candidate search uses existing scheduler concurrency 4 and cancellation signal.
- `SourceSwitchSheet` disables duplicate selection while switching and remains open on failure.
- Source import closes only after commit succeeds; success result includes added/updated counts.
- Paper background is `#F4EFDC`; body ink `#34332F`; existing dark/light tokens remain unchanged.
- Reader horizontal padding remains 24 below 650 px and 48 otherwise; content max width 760.
- Candidate sheet max width 600; action buttons use Material 3 existing primary/outlined hierarchy.

## Visual and UX Checks

- Reader paper background and AppBar use `#F4EFDC`; page text has no horizontal overflow or clipped final glyph.
- Font size, line height and viewport changes preserve the paragraph anchor.
- Flow selector is understandable and persists across reopen.
- Import has no preview list or source checkboxes; busy/error/cancel behavior remains visible.
- Source actions appear only for remote shelf books; local/sample books remain unchanged.
- Candidate sheet exposes loading, empty, partial failure, fatal failure, retry and switching states.
- Image loading uses `BoxFit.cover`; any failure shows the full generated cover without layout shift.

## Visual Evidence Manifest

Evidence root: `.fp-execute/visual/<task-id>/<case-id>/`.

| Case ID | Approved design source | Figma node | revision/time | Frame/variant | variables / Auto Layout / assets | Runtime route | Scenario/state | Viewport | DPR | Locale | Theme | Deterministic non-sensitive fixture | Reference path | Current path | Diff path / missing diff | Mask | Acceptance rule | Command/tool | Failure class | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `VIS-READER-PAPER` | 用户原图 `images/2.jpg` | N/A | user upload 2026-10-30 | warm paper reader | original JPEG | `/read/<sample-book-id>` | paged first/middle page | 375x812 and desktop | 1 | zh-CN | paper | built-in sample book via normal UI | `.fp-execute/visual/frontend-009/VIS-READER-PAPER/reference.png` | `.fp-execute/visual/frontend-009/VIS-READER-PAPER/current.png` | N/A: reference phone chrome/layout differs; compare sampled paper region and structural checks | system status/navigation and unrelated reference controls | paper pixels `#F4EFDC`; no overflow/clipped glyph; same paragraph after resize | `preview_start`, `preview_resize`, `preview_snapshot`, `preview_inspect`, `preview_screenshot` | core visual | PENDING |
| `VIS-IMPORT-DIRECT` | confirmed `design/frontend.md` static component contract | N/A | design 2026-10-30 | import sheet default/busy/error | static SVG generated from confirmed hierarchy before source edit | sources screen import sheet | default then busy | 375x812 and desktop | 1 | zh-CN | app light | user-entered non-sensitive source JSON through UI | `.fp-execute/visual/frontend-008/VIS-IMPORT-DIRECT/reference.png` | `.fp-execute/visual/frontend-008/VIS-IMPORT-DIRECT/current.png` | `.fp-execute/visual/frontend-008/VIS-IMPORT-DIRECT/diff.png` | dynamic text cursor only | no preview/checklist; one primary confirm; input and error alignment match contract | static SVG render + preview screenshot | core visual | PENDING |
| `VIS-SOURCE-SWITCH` | confirmed `design/frontend.md` static component contract | N/A | design 2026-10-30 | details actions/candidate sheet | static SVG generated from confirmed hierarchy before source edit | shelf details modal | candidates loaded | 375x812 and desktop | 1 | zh-CN | app light | real imported sources and shelf book | `.fp-execute/visual/frontend-010/VIS-SOURCE-SWITCH/reference.png` | `.fp-execute/visual/frontend-010/VIS-SOURCE-SWITCH/current.png` | `.fp-execute/visual/frontend-010/VIS-SOURCE-SWITCH/diff.png` | live cover artwork/text values | actions wrap without overflow; sheet max width 600; source/author hierarchy visible | static SVG render + preview screenshot | core visual | PENDING |

Provenance is strict: reference files come from the approved screenshot or confirmed static design SVG; current files come from the real Web runtime. Browser interaction evidence is recorded separately.

## UI/E2E Delivery Contract

E2E evidence root: `.fp-execute/e2e/<task-id>/<case-id>/`.

| Task ID | Case ID | Source-derived condition / requirement reference | UI Delivery Level | Runtime route reference / E2E route | E2E Applicability | Required lifecycle path / stage evidence | Coverage matrix | N/A / BLOCKED rationale |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `frontend-009` | `E2E-READER-FLOW` | proposal change 1；design Visual Checks | business-flow | shelf -> reader -> preferences -> swipe -> exit/reopen | REQUIRED | `SOURCE_READY -> STATIC_UI_READY -> VISUAL_REVIEW_PASS -> INTERACTION_READY -> FRONTEND_E2E_PASS`; real IndexedDB setting/position evidence and restore cleanup | `.fp-execute/e2e/frontend-009/E2E-READER-FLOW/coverage-matrix.md` | N/A |
| `frontend-008` | `E2E-IMPORT-DIRECT` | proposal change 2；D-006 | business-flow | sources -> import -> paste input -> confirm -> source list -> delete | REQUIRED | same full lifecycle; `Mocked Core API: false`; actual SourceImportService + Sembast; cleanup through source delete UI | `.fp-execute/e2e/frontend-008/E2E-IMPORT-DIRECT/coverage-matrix.md` | N/A; deterministic JSON is normal user input entered through UI, not a mocked response or storage injection |
| `frontend-010` | `E2E-SOURCE-SWITCH` | proposal changes 3-4；D-007-D-009 | business-flow | sources import -> discover/add -> details -> change source -> reopen/read -> cleanup | REQUIRED | same full lifecycle; `Mocked Core API: false`; real live sources, network and persistence; cleanup through UI | `.fp-execute/e2e/frontend-010/E2E-SOURCE-SWITCH/coverage-matrix.md` | BLOCKED if approved live sources cannot safely produce the same candidate or Web CORS denies them after 3 attempts; mocks and direct DB/API writes are forbidden |

Each coverage matrix records happy path, validation, loading/empty/error/retry, persistence/navigation, concurrency, security isolation and cleanup as `covered`, `N/A` or `BLOCKED` with real evidence.
