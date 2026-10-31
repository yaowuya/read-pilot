# 离线阅读目录与排版 Frontend Plan

> 执行入口为 `fp-execute`，automationMode=full。用户明确免除逐项确认与阶段等待；具体代选和依据见 proposal/design 台账。不提交、不推送、不归档。仅以下 Task 标记拥有执行 checkbox。

## Global Constraints

- Framework/runtime：现有 Flutter/Dart 客户端，Material 3；`fp-docs/settings/frontend.md`。
- Component/state：复用 ReaderSettings、ReaderPreferences、ReaderParagraph、ReaderPaginator、AppController、Sembast；不新增依赖、API、路由或存储层。
- 原始书籍/章节/笔记不变；目录仅展示映射；继续持久化章节/段落锚点；保存成功后发布状态。来源：项目规范 P001/P002/P004。
- Visual source：`design/frontend.md#前端设计` 的 UI/UX spec + existing code。没有本功能的可信 Figma/reference.png，视觉保真证据为 CANNOT_VERIFY，不冒充像素还原 PASS。
- Browser capability：现有 Claude Browser preview_* 已实际可用，`.claude/launch.json` 已有 read-pilot-web；不安装 Playwright 或修改依赖/CI。
- Verification：SDK `D:/ProgramFiles/flutter`；测试局部 NO_PROXY/no_proxy=localhost,127.0.0.1,::1；使用 format、analyze、Flutter test、Web release 与 Android debug。
- Engineering quality：`C:/Users/Lenovo/.claude/plugins/cache/fp-dev/fp/1.0.0/skills/_shared/engineering-quality.md`；`fp-docs/settings/code-standards.md`。公共组件说明原索引契约，非显然的测量依赖/异步关闭边界保留必要说明，不逐行复述。
- 工作树有大量先前改动：只修改本计划列出的文件；先保存本轮触及文件的代码基线，最终审查分清本轮增量和既有分支改动。旧换源与异常路径验收缺口不关闭。

## File Structure

| Path | Action | Responsibility |
| --- | --- | --- |
| `lib/domain/reader_settings.dart` | modify | 三个有界偏好与 JSON 兼容 |
| `lib/ui/components/reader_preferences.dart` | modify | 控件、预览、保存回退 |
| `lib/ui/components/reader_toc_sheet.dart` | create | 目录展示顺序和原始索引 |
| `lib/ui/screens/reader_screen.dart` | modify | 两种流的排版与目录接入 |
| `test/reader_settings_test.dart` | create | 默认/损坏/往返/copyWith |
| `test/repository_test.dart` | test | 真实内存 Sembast 偏好往返 |
| `test/reader_preferences_test.dart` | test | 新控件、预览、失败与禁用 |
| `test/reader_recovery_test.dart` | test | 实际阅读组件、锚点和排序接入 |
| `test/reader_paginator_test.dart` | test | 段距/粗体组合的测量边界 |
| `test/reader_toc_sheet_test.dart` | create | 反序原索引、标记、回退、迟到完成 |
| `docs/PROGRESS.md`、`docs/VERIFICATION.md` | modify | 本轮实际结果与限制 |

## 1. Page goal and visual contract

### 1.1 Figma source and browser capability resolution

- UI design source: no trustworthy Figma UI design；本轮批准来源是当前页面和项目规范。
- Prototype usage: FUNCTION_SCOPE_ONLY；本轮不创建原型。
- Browser capability: existing project preview runner；只用 preview_* 启动/操作 HTTP 服务。
- Completion vocabulary：没有 reference.png 的保真检查为 CANNOT_VERIFY，不能进入 VISUAL_REVIEW_PASS。仍记录实际功能观察与截图，不以其取代缺失参考或真实 E2E。

### 1.2 Capability and preservation mapping

| Capability / Preservation ID | Required observable result | Owner task | Runtime replay / visual case | Completion rule |
| --- | --- | --- | --- | --- |
| `reader-paragraph-spacing`、`reader-bold-text` 控件 | 设置、预览、保存并恢复 | frontend-002 | PREFS | 实际 UI 改动与重载恢复，保真单独报告 |
| 阅读流一致性 | 两种流共用排版参数且无溢出 | frontend-003 | LAYOUT | 运行观察与正式测试，不声称已通过保真门禁 |
| `toc-display-order` | 倒序选择原始章节，标记正确 | frontend-004 | TOC | 实际 UI 切章和持久化，不修改原列表 |
| 原有缩进/按行断页/内容锚点 | 没有重缩进、跳字或改存屏幕页码 | frontend-003 | LAYOUT | 既有回归加组合参数检查 |

无 Figma-derived FIGCAP/PRES 台账，不虚构对应 ID。

## 2. Frontend Interface and Visual Contract

| Contract | Owner Task | Exact shape / behavior | Consumers | Verification |
| --- | --- | --- | --- | --- |
| settings | frontend-001 | paragraphSpacing 默认20、范围0–40；boldText/tocDescending 默认false；损坏新字段回默认 | 设置、目录、阅读 | JSON/copyWith/仓储测试 |
| preferences | frontend-002 | 现有 onChanged Future；保存中禁用；失败回退；预览两段使用相同排版参数 | 阅读设置与个人设置 | 控件与异步测试 |
| layout | frontend-003 | 正文/测量同字重；paginator 段距；layout key 新字段；同段续页无额外段距 | 分页、滚动 | widget/paginator/恢复测试 |
| toc | frontend-004 | Book、currentChapterIndex、descending、Future onOrderChanged、原始索引 onChapterSelected | ReaderScreen | 组件与真实目录操作 |

### 2.1 Component tree and template outline

ReaderPreferences 在现有字号/行距之后增加段距 Slider 与正文加粗 SwitchListTile，保留可滚动宿主；预览容器内复用两个 ReaderParagraph。ReaderTocSheet 保留目录头、章数和 Expanded ListView，头部增加顺序按钮和可见状态；不创建路由。

### 2.2 State/API/interaction design

复用 `_save/_saving`，新增目录局部 pending 状态与 mounted 防护。目录保存使用 controller 最新 settings.copyWith，不调用正文偏好重排方法。所有章节数据与回调从映射后的原始索引取得。不新增网络调用。

### 2.3 Style and responsive design

严格沿用设计唯一视觉 owner：Material 3、现有 section 24/12、预览 padding20/radius10、目录 padding24/5、0.65视口和760正文上限。段距0–40是有界产品参数而非新设计 token。主题/品牌不变。

### 2.4 Visual and UX checks

执行 `design/frontend.md` 中全部 Visual Checks；实际截图用于观察窄屏、主题、段距和字重，不作为缺失 reference.png 的替代。存储故障只在测试中使用受控失败仓储；真实 UI 无法安全触发时 coverage 标 BLOCKED，不破坏用户数据库。

### 2.5 Visual Evidence Manifest

Evidence root: `.fp-execute/visual/<task-id>/<case-id>/`。每个 case 在实现时保存 manifest.md 和真实 current.png；reference.png 当前缺失，不能伪造。以下表是 case 属性唯一 owner。

| Case ID | Approved design source | Figma node | revision/time | Frame/variant | variables / Auto Layout / assets | Runtime route | Scenario/state | Viewport | DPR | Locale | Theme | Deterministic non-sensitive fixture | Reference path | Current path | Diff path / missing diff | Mask | Acceptance rule | Command/tool | Failure class | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PREFS | UI spec + existing ReaderPreferences | N/A | 本轮已写设计 | 默认及段距0/40、粗体开关 | Material3/NotoSansSC | `/#/read/public-fusheng` 设置弹层 | 调节、保存、重载、失败回退 | 375×812 | 2 | zh-CN | paper/dark | 应用随包公版《浮生六记》 | `.fp-execute/visual/frontend-002/PREFS/reference.png` 缺失 | `.fp-execute/visual/frontend-002/PREFS/current.png` | missing diff：无可信静态参考 | None | 控件不溢出，预览参数一致；保真不得PASS | preview_*；参考正式控件测试 | core visual | CANNOT_VERIFY |
| LAYOUT | UI spec + existing ReaderScreen | N/A | 本轮已写设计 | paged/scrolling | 既有字体与排版组件 | `/#/read/public-fusheng` | 粗体和段距组合、翻页、锚点 | 375×812 / desktop | 2 / runtime | zh-CN | paper/dark | 同上，无数据注入 | `.fp-execute/visual/frontend-003/LAYOUT/reference.png` 缺失 | `.fp-execute/visual/frontend-003/LAYOUT/current.png` | missing diff：无可信静态参考 | None | 无overflow，真实段距有效，续段无重缩进；保真不得PASS | preview_*；paginator/恢复测试 | core visual | CANNOT_VERIFY |
| TOC | UI spec + existing目录 | N/A | 本轮已写设计 | 正序/倒序 | Material3/ListView | `/#/read/public-fusheng` 目录弹层 | 排序、原始索引选择、恢复、失败回退 | 375×812 | 2 | zh-CN | paper | 同上，无新增业务种子 | `.fp-execute/visual/frontend-004/TOC/reference.png` 缺失 | `.fp-execute/visual/frontend-004/TOC/current.png` | missing diff：无可信静态参考 | None | 顺序状态/标记可辨，跳转正确；保真不得PASS | preview_*；目录组件测试 | core visual | CANNOT_VERIFY |

### 2.6 UI/E2E Delivery Contract

| Task ID | Case ID | Source-derived condition / requirement reference | UI Delivery Level | Runtime route reference / E2E route | E2E Applicability | Required lifecycle path / stage evidence | Coverage matrix | N/A / BLOCKED rationale |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| frontend-002 | PREFS | proposal变更2/3；D-003/D-004/D-007；偏好保存/失败/恢复 | business-flow | PREFS route | REQUIRED | SOURCE_READY→STATIC_UI_READY→VISUAL_REVIEW_PASS→INTERACTION_READY→FRONTEND_E2E_PASS；保存证据独立 | `.fp-execute/e2e/frontend-002/PREFS/coverage-matrix.md` | 保真源缺失；真实存储故障不可安全注入时BLOCKED |
| frontend-003 | LAYOUT | proposal变更2/3；D-004/D-006；重排/流切换/锚点 | interactive | LAYOUT route | REQUIRED | 同上；不能越过缺失视觉门禁 | `.fp-execute/e2e/frontend-003/LAYOUT/coverage-matrix.md` | 保真源缺失；实际功能观察不等于生命周期通过 |
| frontend-004 | TOC | proposal变更1；D-005/D-007；排序保存、标记和原索引选择 | business-flow | TOC route | REQUIRED | 同上；本地真实设置读写为核心持久化边界 | `.fp-execute/e2e/frontend-004/TOC/coverage-matrix.md` | 保真源缺失；真实错误分支无法安全触发则BLOCKED |

真实浏览器证据记录 command/tool、environment、destination、start/end、attempts、test IDs、artifacts、coverage path 与 cleanup。核心持久化为本应用真实 Sembast/IndexedDB 设置读写，Mocked Core API:false；不虚构 HTTP API。仅从 UI 改变/恢复偏好，不直接注入 store、数据库或拦截请求。正常观察可以记录 covered，但生命周期与完整case仍保留BLOCKED，禁止人工豁免。最后将 UI 设置恢复到观察前值。

## 3. Task breakdown

- [x] **Task frontend-001: 扩展有界阅读偏好与持久化回归**

**Files:** Modify `lib/domain/reader_settings.dart`；Create `test/reader_settings_test.dart`；Test `test/repository_test.dart`。
**Reasoning:** 先建立兼容字段契约，其他控件/布局共享它；不改Sembast结构。
**Depends on:** None
**Interfaces:** Consumes 既有ReaderSettings/JSON/meta/settings；Produces settings contract；Contract checks 默认、有限值、布尔类型、copyWith保留其他字段及往返。
**Capability / Preservation Ownership:** 无FIGCAP/PRES；三项设置字段为后续任务输入，非UI任务。
**Step 1: Write the failing test:** 新建JSON默认/往返断言，例如 `expect(ReaderSettings.fromJson({}).toJson()['paragraphSpacing'], 20)`，旧实现实际返回null；仓储保存三个新键后用fresh repository读取。
**Step 2: Run test to verify it fails:** `flutter test --no-pub test/reader_settings_test.dart test/repository_test.dart`，预期新增字段缺失导致FAIL，不是环境失败。
**Step 3: Write minimal implementation:** 增加三个final字段，copyWith/fromJson/toJson向后兼容；新字段非法值按设计默认。保持现有对象说明，不创建通用配置框架。
**Template Outline:** N/A，领域对象。
**Script/State Outline:** 同步值对象；仓储继续同一记录。
**Style Outline:** N/A，无视觉变更。
**Visual / UX Checks:** 无case；确认默认20/false/false不改变旧UI行为。
**UI/E2E Lifecycle and Evidence:** 非UI任务；以正式单元/仓储测试为证，不签发视觉/E2E通过。
**Step 4: Run test to verify it passes:** 同一聚焦命令；新增与原有测试全部PASS，记录红绿输出并inline自审。
**Step 5: Commit:** 不执行；用户约束禁止提交/推送。

- [ ] **Task frontend-002: 增加段距、加粗控件及一致预览**

**Files:** Modify `lib/ui/components/reader_preferences.dart`；Test `test/reader_preferences_test.dart`。
**Reasoning:** 控件与预览共享领域偏好，沿用现有保存/回退模式。
**Depends on:** frontend-001
**Interfaces:** Consumes settings contract；Produces preferences contract；Contract checks 回调新字段、保存中禁用、失败回退、预览几何段距和字重。
**Capability / Preservation Ownership:** reader-paragraph-spacing/reader-bold-text控件；Browser replay PREFS。
**Step 1: Write the failing test:** 查找 `reader-paragraph-spacing`、`reader-bold-text`，模拟操作并断言回调及预览；旧UI找不到控件。加入失败/待完成回调测试。
**Step 2: Run test to verify it fails:** `flutter test --no-pub test/reader_preferences_test.dart`；预期新控件/预览契约FAIL。
**Step 3: Write minimal implementation:** 复用Slider、SwitchListTile与现有_save；预览两段ReaderParagraph共享参数，既有容器配色不动。
**Template Outline:** 按设计组件树和settings来源实现，不新建路由。
**Script/State Outline:** 复用_value/_saving/_save与mounted保护。
**Style Outline:** 复用现有24/12、padding20/radius10和主题。
**Visual / UX Checks:** PREFS：窄屏可滚动、控件可辨、段距与字重预览有效，CANNOT_VERIFY保真。
**UI/E2E Lifecycle and Evidence:** 唯一owner为2.6 PREFS行；实现和测试记录SOURCE/STATIC，视觉源缺失保持BLOCKED；真实安全可观察分支在覆盖矩阵独立记录，不越级签发生命周期。
**Step 4: Run test to verify it passes:** 同一聚焦命令；组件测试通过，真实页面按PREFS观察/截图；错误分支不能安全触发则记录BLOCKED。
**Step 5: Commit:** 不执行。

- [ ] **Task frontend-003: 将新偏好接入两种阅读流与测量**

**Files:** Modify `lib/ui/screens/reader_screen.dart`；Test `test/reader_recovery_test.dart`、`test/reader_paginator_test.dart`。
**Reasoning:** 所有实际绘制和分页依赖必须一致，防止重现页尾留白/溢出。
**Depends on:** frontend-001
**Interfaces:** Consumes settings contract和现有paginator；Produces layout contract；Contract checks 字重、段距、布局key、逻辑锚点、同段续页标志。
**Capability / Preservation Ownership:** 新偏好在阅读流中的应用；原有缩进/连续分页/恢复；Browser replay LAYOUT。
**Step 1: Write the failing test:** 在ReaderSettings.fromJson输入新字段后打开实际ReaderScreen，断言ReaderParagraph.style字重与Padding段距；旧实现仍400/20。为paginator添加0/40、400/700组合检查正文重组和高度。
**Step 2: Run test to verify it fails:** `flutter test --no-pub test/reader_recovery_test.dart test/reader_paginator_test.dart`；预期新样式应用FAIL，保留既有点击/拖动回归。
**Step 3: Write minimal implementation:** 两处bodyStyle使用boldText；滚动Padding使用paragraphSpacing；paginate传该参数，layoutKey包含新字段。不修改paragraph原文或位置模型。
**Template Outline:** 保持现有PageView/scroll树与首行缩进组件。
**Script/State Outline:** 复用_restore/_updateReaderSettings；只更新必要测量依赖。
**Style Outline:** 主题、宽度760及12/28页内边距不变。
**Visual / UX Checks:** LAYOUT：观察两种流、主题、参数边界，无overflow；保真CANNOT_VERIFY。
**UI/E2E Lifecycle and Evidence:** 唯一owner为2.6 LAYOUT行；不越过缺失视觉门禁，真实操作记录独立观察证据。
**Step 4: Run test to verify it passes:** 同一聚焦命令；正文不丢/重，恢复章节/段落不变，旧翻页测试通过。
**Step 5: Commit:** 不执行。

- [ ] **Task frontend-004: 实现目录倒序及原始索引选择**

**Files:** Create `lib/ui/components/reader_toc_sheet.dart`、`test/reader_toc_sheet_test.dart`；Modify `lib/ui/screens/reader_screen.dart`；Test `test/reader_recovery_test.dart`。
**Reasoning:** 将目录的局部排序/保存生命周期集中在一个组件，避免在900行ReaderScreen继续堆叠状态。
**Depends on:** frontend-001
**Interfaces:** Consumes Book、currentChapterIndex、descending与callbacks；Produces toc contract；Contract checks 原始索引、标记、原列表不变、回退和关闭。
**Capability / Preservation Ownership:** toc-display-order及原始索引保护；Browser replay TOC。
**Step 1: Write the failing test:** 阅读器目录中 `reader-toc-order` 必须存在，旧目录没有。组件测试覆盖反序选择的回调原索引、当前章、缓存、失败回退与关闭后完成。
**Step 2: Run test to verify it fails:** `flutter test --no-pub test/reader_recovery_test.dart` 观察缺少排序入口；新组件测试可先因模块缺失失败，不能将其当运行通过。
**Step 3: Write minimal implementation:** 新建有原始索引契约说明的ReaderTocSheet，itemBuilder按方向映射；_saving/mounted保护；通过当前controller.settings保存顺序，不调用正文重排路径。替换原_showToc内联列表。
**Template Outline:** 原目录头/章数/Expanded ListView，新增顺序IconButton和可见状态。
**Script/State Outline:** 局部_descending/_saving；无新store/route，选择仍走_jump。
**Style Outline:** 原24/5和0.65视口、现有选中与缓存样式。
**Visual / UX Checks:** TOC：顺序可辨，正反向均打开正确章，重新打开恢复偏好；保真CANNOT_VERIFY。
**UI/E2E Lifecycle and Evidence:** 唯一owner为2.6 TOC行；保存故障未安全触发则BLOCKED，禁止注入真实库。
**Step 4: Run test to verify it passes:** `flutter test --no-pub test/reader_toc_sheet_test.dart test/reader_recovery_test.dart`，所有合成回归PASS；真实目录操作另留记录。
**Step 5: Commit:** 不执行。

- [ ] **Task frontend-005: 执行全量检查、真实观察与交付审查**

**Files:** Test前述全部测试；Modify `docs/PROGRESS.md`、`docs/VERIFICATION.md`；Append `.fp-execute/progress.md`与case证据。
**Reasoning:** 分开报告代码功能、平台构建与严格UI门禁，保护已有工作树和数据。
**Depends on:** frontend-001, frontend-002, frontend-003, frontend-004
**Interfaces:** Consumes所有已实现契约及2.5/2.6证据；Produces实际结果与未解决项；Contract checks 不以单测、截图或授权替代必需真实分支和参考源。
**Capability / Preservation Ownership:** 无重复owner；汇总其他任务证据。
**Step 1: Write the failing test:** 无新增业务行为，不制造人为红灯；复用前四项真实红绿记录，检查覆盖遗漏并在原任务补测试。
**Step 2: Run test to verify it fails:** N/A；验证任务不要求伪造失败。任何真实失败回到对应owner修复。
**Step 3: Write minimal implementation:** 仅记录实际命令、页面和限制；不新增业务能力。
**Template Outline:** N/A，文档/验证。
**Script/State Outline:** 任务完成或明确阻塞后将watch-state置终态，并停用精确watchdog任务。
**Style Outline:** N/A；检查已有Visual Checks。
**Visual / UX Checks:** 汇总PREFS/LAYOUT/TOC的真实截图与coverage；缺少参考源或真实故障证据的checkbox保持未勾选，禁止宣称完整生命周期通过。
**UI/E2E Lifecycle and Evidence:** 本任务不拥有新case；final-review只能报告缺口，不能豁免上游BLOCKED。
**Step 4: Run test to verify it passes:** `dart format --output=none --set-exit-if-changed lib test integration_test`；`flutter analyze --no-pub`；`flutter test --no-pub`；`flutter build web --release --no-web-resources-cdn --no-pub`；`flutter build apk --debug --no-pub`。使用现有preview_*，记录真实UI改动/重载恢复/清理；最后加载fp-final-review。若严格门禁仍BLOCKED，保留未完成标记并如实交付功能/构建结果，不伪造通过。
**Step 5: Commit:** 不执行；也不自动归档。

## Coverage Matrix

| Source | Requirement / capability / preservation / visual boundary | Tasks | Verification |
| --- | --- | --- | --- |
| proposal变更1；D-005 | 目录展示顺序、原索引、持久化 | frontend-001/frontend-004 | settings/repository/toc/reader测试；TOC覆盖矩阵 |
| proposal变更2；D-003 | 段距有界、默认兼容、两流一致 | frontend-001/frontend-002/frontend-003 | settings/preferences/paginator/recovery；PREFS/LAYOUT |
| proposal变更3；D-004 | 加粗与测量/预览一致 | frontend-001/frontend-002/frontend-003 | 同上，检查400/700 |
| D-007；项目规范P002/P004 | 保存失败、迟到完成、锚点 | frontend-001/frontend-002/frontend-003/frontend-004 | 故障组件回归；真实危险故障标BLOCKED |
| design Visual Checks | 窄屏、主题、正文/目录/设置 | frontend-002/frontend-003/frontend-004 | 对应独立case证据；缺参考源不记保真PASS |
| 工程门禁与用户约束 | 全量/构建/未提交/停止检查 | frontend-005 | 命令日志、最终审查、watchdog停用结果 |
