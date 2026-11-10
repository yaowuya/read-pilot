# 现有页面按设计稿还原外观 Frontend Plan

> **For agentic workers:** REQUIRED FLOW: Use `fp-execute` to implement this plan task-by-task. Only task markers use checkbox (`- [ ] **Task frontend-NNN: ...**`) syntax for tracking; substeps are plain ordered instructions.

## Frontend Reuse And Directory Confirmation

- Frontend Scope: `refactor`
- Reference Modules: `lib/ui/app_shell.dart`、`lib/ui/components/design.dart`、`lib/ui/screens/bookshelf_screen.dart`
- Reuse Decisions: `design/frontend.md` 的 Frontend Reuse Decisions。不新建页面或组件库。
- Directory Proposal: 只修改下表已有文件，不新增目录。
- Directory Confirmation: `not-required`
- Confirmation Source: 本次是已有界面重构，不是新模块。

## Global Constraints

- Framework/runtime: Flutter / Dart，`fp-docs/settings/frontend.md`
- Component library/design system: Flutter Material 3，共用组件在 `lib/ui/components/design.dart`
- Script/style conventions: 页边距用 `AppSpacing.page`（25），宽屏用 `AppSpacing.pageWide`（40）
- Visual source: `D:\download\阅读助手_完整设计稿.html` 的 390 宽手机框
- Visual evidence runner: 项目现有 `flutter test`；浏览器像素对比尚未接好，不能把本地运行截图当成设计稿原图
- Verification commands: `flutter test test/reader_paginator_test.dart`；`flutter analyze`
- Engineering quality: `C:\Users\Lenovo\.cursor\plugins\local\fp\skills\_shared\engineering-quality.md`。注释用中文。有意延后：无。

## File Structure

| Path | Action | Responsibility |
| --- | --- | --- |
| `lib/ui/theme.dart` | modify | 页边距 25，面板色 `#F5F7FA` |
| `lib/ui/components/design.dart` | modify | 顶栏高度、列表行垂直间距 |
| `lib/ui/app_shell.dart` | modify | 窄屏底栏内边距 |
| `lib/ui/screens/bookshelf_screen.dart` | modify | 书架边距、三列间距、继续阅读卡 |
| `lib/ui/screens/discover_screen.dart` | modify | 发现页窄屏边距 |
| `lib/ui/screens/profile_screen.dart` | modify | 我的页边距和统计卡 |
| `lib/ui/screens/app_settings_screen.dart` | modify | 设置页边距 |
| `lib/ui/screens/` 其余已有页面 | modify | 把仍写死的 16 或 20 页边距改成 `AppSpacing.page` |

## 1. Page goal and visual contract

窄屏已有页面按设计稿手机框对齐。宽屏继续用宽度 ≥ 1000 的左侧栏。阅读分页规则不改。

## 1.1 Figma source and browser capability resolution

- UI design source: `no trustworthy Figma UI design`
- Prototype usage: `FUNCTION_SCOPE_ONLY` 不适用于本文件；本变更的视觉来源是已批准的静态 HTML，不是仓库原型
- Browser capability: `unavailable`。本机测试使用 `flutter test`。不安装新的浏览器工具。
- Completion vocabulary: 没有 Figma 时，像素级截图结论保持 `CANNOT_VERIFY`。组件测试能证明的间距和颜色除外。

## 1.2 Capability and preservation mapping

| Capability / Preservation ID | Required observable result | Owner task | Runtime replay / visual case | Completion rule |
| --- | --- | --- | --- | --- |
| `FIGCAP-001` | 窄屏主页面左右边距为 25 | `frontend-001` | `VIS-001` | 组件测试读到 `AppSpacing.page == 25` |
| `PRES-001` | 阅读分页规则不变 | `frontend-001` | `test/reader_paginator_test.dart` | 该测试保持通过 |
| `PRES-002` | 宽度 ≥ 1000 仍隐藏底栏 | `frontend-002` | 现有宽屏导航测试 | 底栏键 `nav-0` 在宽屏不出现 |

## 2. Frontend Interface and Visual Contract

| Contract | Owner Task | Exact shape / behavior | Consumers | Verification |
| --- | --- | --- | --- | --- |
| 页边距 | `frontend-001` | `AppSpacing.page` 为 25 | 书架、发现、我的、设置 | 窄屏内容左右为 25 |
| 书架网格 | `frontend-003` | 窄屏三列，列间距 22，行间距 25 | 书架 | 网格 delegate 使用这两个值 |
| 面板色 | `frontend-003` | `AppColors.panel` 为 `#F5F7FA` | 继续阅读卡、我的统计卡 | 两处不再各写一套色值 |
| 底栏 | `frontend-002` | 左右 14，上 8，内容高 48 | 窄屏主框架 | 宽屏不渲染底栏 |

### 2.1 Component tree and template outline

主框架仍是 `AppShell` 里的书架、发现、我的。子页仍用各自的 `Scaffold` 和 `AppTopBar`。

### 2.2 State/API/interaction design

不新增状态。`AppController` 和页面局部状态保持原样。

### 2.3 Style and responsive design

窄屏用 25 页边距。宽度 ≥ 1000 的侧栏分支不改。阅读正文边距继续用 `reader_screen.dart` 自己的 29 / 48，不跟随 `AppSpacing.page`。

### 2.4 Visual and UX checks

- 书架、发现、我的、设置的窄屏左右边距为 25。来源：设计稿 `.pad`
- 书架窄屏为三列，列间距 22，行间距 25。来源：设计稿 `.book-grid`
- 继续阅读卡和我的统计卡使用 `#F5F7FA`。来源：设计稿 `.continue-card`、`.stats-card`
- 窄屏底栏有三项，选中项为蓝字加 4 像素圆点。来源：设计稿 `.tabbar`
- 宽屏没有底栏。来源：`lib/ui/app_shell.dart`

### 2.5 Visual Evidence Manifest

Evidence root: `.fp-execute/visual/<task-id>/<case-id>/`。当前没有从 HTML 导出的 `reference.png`，也没有稳定的运行时 `current.png`。下表把缺失写明，不用本地截图冒充设计稿。

| Case ID | Approved design source | Figma node | revision/time | Frame/variant | variables / Auto Layout / assets | Runtime route | Scenario/state | Viewport | DPR | Locale | Theme | Deterministic non-sensitive fixture | Reference path | Current path | Diff path / missing diff | Mask | Acceptance rule | Command/tool | Failure class | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `VIS-001` | `D:\download\阅读助手_完整设计稿.html` `.pad` | N/A | 用户提供的本地 HTML | 手机框 390 | CSS `.pad{padding:0 25px}` | `/` | 书架有书 | 390×855 | 1 | zh-CN | 默认 | 应用自带示例书 | N/A: HTML 未导出 reference.png | N/A: 未采集运行时截图 | N/A: 缺少 reference 与 current | None | 窄屏左右边距 25 | `flutter test` | non-core cosmetic | `PENDING` |

- Provenance: reference.png 只能来自这份 HTML 的导出；current.png 只能来自真实运行路由。
- 上表没有这两张图。不能把本次分析或本地预览当成视觉通过。

### 2.6 UI/E2E Delivery Contract

| Task ID | Case ID | Source-derived condition / requirement reference | UI Delivery Level | Runtime route reference / E2E route | E2E Applicability | Required lifecycle path / stage evidence | Coverage matrix | N/A / BLOCKED rationale |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `frontend-001` | `VIS-001` | 设计稿 `.pad` 左右 25 | `static-only` | `/` | `N/A` | `SOURCE_READY -> STATIC_UI_READY`。视觉截图为 `CANNOT_VERIFY` | `.fp-execute/e2e/frontend-001/VIS-001/coverage-matrix.md` | 静态间距由组件测试覆盖；没有已批准的浏览器 E2E 运行器，不把截图当成 E2E |

没有新的业务流程。不设 `business-flow`。

## 3. Task breakdown

- [ ] **Task frontend-001: 把手机页边距改成 25**

**Files:**
- Create: 无
- Modify: `lib/ui/theme.dart`、`lib/ui/screens/bookshelf_screen.dart`、`lib/ui/screens/discover_screen.dart`、`lib/ui/screens/profile_screen.dart`、`lib/ui/screens/app_settings_screen.dart`
- Test: `test/reader_paginator_test.dart`

**Reasoning:**
- 设计稿 `.pad` 是 25。当前窄屏书架是 20，发现和我的是 16。阅读正文不跟着改。

**Depends on:** None

**Interfaces:**
- Consumes: `AppSpacing.page`
- Produces: 窄屏主页面使用 25
- Contract checks: 阅读分页测试仍通过

**Capability / Preservation Ownership:**
- `FIGCAP-001`: `FIGCAP-001`
- `PRES-001`: `PRES-001`
- Browser replay: `CANNOT_VERIFY`，没有浏览器运行器

**Step 1: Write the failing test**

断言 `AppSpacing.page` 等于 25。修改前它是 20，断言失败。

**Step 2: Run test to verify it fails**

Run: `flutter test` 中针对 `AppSpacing.page` 的断言
Expected: FAIL，实际值为 20

**Step 3: Write minimal implementation**

把 `AppSpacing.page` 改为 25。书架、发现、我的和设置的窄屏页边距改用这个常量。

**Template Outline:**
- 页面内容包在左右 25 的内边距里

**Script/State Outline:**
- 无新状态

**Style Outline:**
- `AppSpacing.page = 25`

**Visual / UX Checks:**
- 窄屏左右边距为 25
- Visual Evidence cases: `VIS-001`

**UI/E2E Lifecycle and Evidence:**
- UI Delivery Level and Contract cases: `frontend-001` / `VIS-001`，`static-only`
- Source and stages: `SOURCE_READY -> STATIC_UI_READY`。`VISUAL_REVIEW_PASS` 在没有 reference.png 时不能标记通过
- E2E evidence: `N/A`，静态间距
- BLOCKED handling: 像素对比缺少设计稿导出图，不假装通过

**Step 4: Run test to verify it passes**

Run: `flutter test test/reader_paginator_test.dart`
Expected: PASS

Run: `flutter analyze lib/ui/theme.dart lib/ui/screens/bookshelf_screen.dart lib/ui/screens/discover_screen.dart lib/ui/screens/profile_screen.dart lib/ui/screens/app_settings_screen.dart`
Expected: No issues found

- [ ] **Task frontend-002: 对齐窄屏底栏内边距**

**Files:**
- Create: 无
- Modify: `lib/ui/app_shell.dart`
- Test: `test/app_widget_test.dart`

**Reasoning:**
- 设计稿底栏左右 14、上 8。宽屏必须继续没有底栏。

**Depends on:** None

**Interfaces:**
- Consumes: `_TabBar`
- Produces: 窄屏底栏内边距
- Contract checks: 宽屏找不到 `nav-0`

**Capability / Preservation Ownership:**
- `FIGCAP-*`: None
- `PRES-*`: `PRES-002`
- Browser replay: `CANNOT_VERIFY`

**Step 1: Write the failing test**

宽屏下 `find.byKey(Key('nav-0'))` 应为 0。这条现有测试应继续通过。

**Step 2: Run test to verify it fails**

Run: `flutter test test/app_widget_test.dart --name "bookshelf"`
Expected: 现有书架导航测试在改坏宽屏分支时失败

**Step 3: Write minimal implementation**

底栏增加 `EdgeInsets.fromLTRB(14, 8, 14, 0)`，内容高度 48。不改宽度 ≥ 1000 的分支。

**Template Outline:**
- `SafeArea` 包住底栏，底部安全区不写死 27

**Script/State Outline:**
- 选中项仍由 `AppShell` 的下标决定

**Style Outline:**
- 选中色 `AppColors.blue`，圆点 4

**Visual / UX Checks:**
- 窄屏三项导航仍在
- 宽屏无底栏

**UI/E2E Lifecycle and Evidence:**
- UI Delivery Level: `static-only`
- Source and stages: `SOURCE_READY -> STATIC_UI_READY`
- E2E evidence: `N/A`
- BLOCKED handling: 无真实浏览器证据时不标记视觉通过

**Step 4: Run test to verify it passes**

Run: `flutter test test/app_widget_test.dart --name "bookshelf"`
Expected: PASS

- [ ] **Task frontend-003: 对齐书架网格和两张面板卡**

**Files:**
- Create: 无
- Modify: `lib/ui/theme.dart`、`lib/ui/screens/bookshelf_screen.dart`、`lib/ui/screens/profile_screen.dart`
- Test: 无新测试文件。用 `flutter analyze` 检查这两个页面。

**Reasoning:**
- 设计稿书架列间距 22、行间距 25。继续阅读卡和我的统计卡共用 `#F5F7FA`。

**Depends on:** `frontend-001`

**Interfaces:**
- Consumes: `AppColors.panel`
- Produces: 两张卡使用同一颜色
- Contract checks: 源码里这两张卡不再各写 `Color(0xFFF5F7FA)`

**Capability / Preservation Ownership:**
- `FIGCAP-*`: None
- `PRES-*`: None
- Browser replay: `CANNOT_VERIFY`

**Step 1: Write the failing test**

不新增会在改色前就失败的测试。完成标准是两处颜色常量相同，并且网格间距为 22 和 25。

**Step 2: Run test to verify it fails**

Run: 无单独失败测试
Expected: 修改前统计卡仍硬编码 `0xFFF5F7FA`

**Step 3: Write minimal implementation**

增加 `AppColors.panel`。继续阅读卡和统计卡改用它。窄屏网格列间距 22，行间距 25。

**Template Outline:**
- 三列网格
- 面板卡圆角：继续阅读 13，统计卡 12

**Script/State Outline:**
- 无新状态

**Style Outline:**
- `#F5F7FA`

**Visual / UX Checks:**
- 两张卡颜色相同
- 书架三列间距符合设计稿

**UI/E2E Lifecycle and Evidence:**
- UI Delivery Level: `static-only`
- E2E evidence: `N/A`

**Step 4: Run test to verify it passes**

Run: `flutter analyze lib/ui/screens/bookshelf_screen.dart lib/ui/screens/profile_screen.dart`
Expected: No issues found

- [ ] **Task frontend-004: 将其余已有页面的窄屏页边距收口**

**Files:**
- Create: 无
- Modify: `lib/ui/screens/search_screen.dart`、`lib/ui/screens/notes_screen.dart`、`lib/ui/screens/import_screen.dart`、`lib/ui/screens/sources_screen.dart`、`lib/ui/screens/backup_screen.dart`、`lib/ui/screens/reading_history_screen.dart`、`lib/ui/screens/audio_screen.dart`、`lib/ui/screens/welcome_screen.dart`、`lib/ui/screens/finish_screen.dart`
- Test: 各页现有组件测试

**Reasoning:**
- 提案覆盖全部已有页面。搜索等子页仍有 23 或 20 的页边距，还没改成 25。

**Depends on:** `frontend-001`

**Interfaces:**
- Consumes: `AppSpacing.page`
- Produces: 这些页面的窄屏内容边距改为 25
- Contract checks: 不改它们的点击流程

**Capability / Preservation Ownership:**
- `FIGCAP-*`: None
- `PRES-*`: None
- Browser replay: `CANNOT_VERIFY`

**Step 1: Write the failing test**

对仍写死页边距的页面，断言内容左右为 25。修改前失败。

**Step 2: Run test to verify it fails**

Run: 对应页面的 `flutter test`
Expected: FAIL，边距仍不是 25

**Step 3: Write minimal implementation**

只替换页面级左右边距。弹层内部间距和阅读正文测量不动。

**Template Outline:**
- 子页内容使用 `AppSpacing.page`

**Script/State Outline:**
- 保持各页现有状态

**Style Outline:**
- 左右 25

**Visual / UX Checks:**
- 子页窄屏左右边距为 25
- 返回、搜索、导入和备份的原操作仍可点

**UI/E2E Lifecycle and Evidence:**
- UI Delivery Level: `interactive` 的原有点击不改语义
- E2E evidence: 没有已批准浏览器运行器，真实 E2E 为 `BLOCKED`，不能改标成通过

**Step 4: Run test to verify it passes**

Run: `flutter test` 中这些页面已有的测试文件
Expected: PASS

## 4. Coverage

| 设计结论 | 任务 |
| --- | --- |
| 页边距 25 | `frontend-001`、`frontend-004` |
| 底栏 | `frontend-002` |
| 书架网格和面板色 | `frontend-003` |
| 阅读分页不改 | `frontend-001` 的分页测试 |
| 宽屏侧栏保留 | `frontend-002` |
