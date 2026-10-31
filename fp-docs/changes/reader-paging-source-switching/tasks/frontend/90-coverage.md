# Frontend Coverage and Verification Mapping

## Proposal and Design Coverage

| Source | Requirement / capability / preservation / visual boundary | Tasks | Verification |
| --- | --- | --- | --- |
| `proposal.md#左右分页阅读与暖纸色` | 双模式、默认分页、段落锚点、`#F4EFDC` | `frontend-001`, `frontend-002`, `frontend-009` | paginator/domain/widget tests + `VIS-READER-PAPER` + `E2E-READER-FLOW` |
| `proposal.md#一步确认导入书源` | 无预览、prepare + commit、失败不部分保存 | `frontend-008` | `sources_screen_test.dart` + `VIS-IMPORT-DIRECT` + `E2E-IMPORT-DIRECT` |
| `proposal.md#候选书源搜索与手动换源` | 候选匹配、手动选择、事务切换、位置/笔记映射 | `frontend-005`, `frontend-006`, `frontend-007`, `frontend-010` | mapper/repository/controller/widget/live E2E |
| `proposal.md#封面获取与刷新` | 详情刷新、安全图片字节、失败保留封面 | `frontend-004`, `frontend-007`, `frontend-010` | transport/engine/controller/widget + source switch evidence |
| `proposal.md#正文整理排版` | 安全替换、确定性整理、展示缩进与对齐 | `frontend-003`, `frontend-009` | normalizer/engine tests + reader visual replay |
| `design/frontend.md#迟到下载保护` | 旧来源请求不能污染新目录 | `frontend-006`, `frontend-007` | repository/controller race tests |
| `design/frontend.md#接口权限与兼容边界` | 同源、私网、跳转、大小、CORS 边界 | `frontend-004`, `frontend-007`, `frontend-010` | transport negative tests + browser network evidence |
| `design/frontend.md#Migration影响` | 旧 settings 兼容、无 schema migration | `frontend-001`, `frontend-011` | domain/repository round-trip + full suite |
| `design/frontend.md#Visual-Checks` | 纸色、响应式、状态、封面回退 | `frontend-008`, `frontend-009`, `frontend-010`, `frontend-011` | three visual manifests and independent review |

## Capability and Preservation Coverage

| ID | Unique implementation owner | Supporting tasks | Completion evidence |
| --- | --- | --- | --- |
| `CAP-001` | `frontend-009` | `frontend-001`, `frontend-002` | unit/widget + reader visual/E2E |
| `CAP-002` | `frontend-008` | None | widget + import visual/E2E |
| `CAP-003` | `frontend-010` | `frontend-004`, `frontend-005`, `frontend-006`, `frontend-007` | runtime tests + source switch visual/E2E |
| `CAP-004` | `frontend-003` | `frontend-011` live replay | unit/engine/live 8027 |
| `PRES-001` | `frontend-009` | `frontend-001`, `frontend-002`, `frontend-005` | reader reopen + mapper tests |
| `PRES-002` | `frontend-007` | `frontend-004`, `frontend-006`, `frontend-008` | negative/rollback/race tests |
| `PRES-003` | `frontend-010` | `frontend-009` | local/sample widget and browser checks |

## UI/E2E Case Coverage

| Task / Case | Happy path | Branches and errors | Persistence/navigation | Security/isolation | Cleanup | Initial status |
| --- | --- | --- | --- | --- | --- | --- |
| `frontend-009/E2E-READER-FLOW` | open, swipe, change mode | save failure/retry covered in widget suite; real failure only when safely observable | IndexedDB setting + position; exit/reopen | local-only, no source request | restore prior mode via UI | PENDING |
| `frontend-008/E2E-IMPORT-DIRECT` | paste and confirm | validation error; URL cancellation separately widget-tested | source appears after close/reopen | real parser/transaction; no request mock | delete source via UI | PENDING |
| `frontend-010/E2E-SOURCE-SWITCH` | import, add, switch, read | loading/empty/partial/fatal/retry widget coverage; real network errors recorded | same book ID after reopen | real source transport, same-origin and CORS | delete test book/sources via UI | PENDING; may become BLOCKED only under contract |

Each case writes its own canonical coverage matrix under `.fp-execute/e2e/<task-id>/<case-id>/coverage-matrix.md`. This table is planning coverage, not execution evidence.

## Verification Order

1. Run each task's red/green focused tests before advancing.
2. After each UI task reaches static UI, produce its real runtime screenshot and independent visual review.
3. After visual pass, execute the required real browser E2E and cleanup.
4. Run `frontend-011` fresh format, analyze, full tests, live tests, Web build and all case replays.
5. Reconcile owner checkboxes and `.fp-execute/progress.md`; any required BLOCKED case keeps the owning task and final verification incomplete.

## Planned End Summary

- Frontend canonical entrypoint: `tasks/frontend/00-index.md` (split).
- Backend plan: skipped because the repository has no production backend and all changed layers belong to the single Flutter app.
- Change-level `tasks/00-overview.md`: intentionally absent because only one end exists.
- Task graph: 11 unique frontend tasks, all owned by the two `tasks` fragments; no cross-end dependencies.
