# 离线阅读目录与排版 — 技术方案设计

## 第一部分：架构决策

### Decision Ledger

用户明确授权“不需要我确认，请按照你的最佳推荐，自行决策，继续往下走”。下表新选择为该授权下的代选，`user-confirmed` 表示授权有效，不伪称用户已按 ID 审阅具体实现；沿用提案的授权例外。

| ID | Decision | Source | Blocking | Status | Evidence / explicit confirmation |
| --- | --- | --- | --- | --- | --- |
| D-001 | 视觉来源采用 UI/UX spec + existing code | `proposal.md` P-001–P-005；frontend settings；当前免确认消息 | yes | user-confirmed | D-001：授权下代选复用现有 Material 3 设置和目录；不引入 Figma、原型或新主题 |
| D-002 | 三项偏好放入现有 ReaderSettings，附加 JSON 键 | `reader_settings.dart:6`；`app_repository.dart:144`；当前免确认消息 | yes | user-confirmed | D-002：代选全局阅读偏好；不新建表，不修改正文和位置记录 |
| D-003 | 段距 0–40 px、每 4 px 一档，默认 20；加粗默认关闭 | `proposal.md` P-002/P-003；当前免确认消息 | yes | user-confirmed | D-003：代选有界范围与默认；实际字号、行距仍沿用现有范围 |
| D-004 | 加粗使用 FontWeight.bold，正文、测量和预览共用同一选择 | `reader_screen.dart:294`、`:353`；当前免确认消息 | yes | user-confirmed | D-004：代选 400/700 字重切换，不新增字体资源 |
| D-005 | 目录组件只用展示索引映射原始索引，保存后保持偏好 | `proposal.md` P-001；当前免确认消息 | yes | user-confirmed | D-005：代选独立 ReaderTocSheet 管理局部保存/回退状态；不排序 Book.chapters |
| D-006 | 排版 key 包含段距与字重；目录排序不触发重新分页 | `reader_screen.dart:391`、`:850`；当前免确认消息 | yes | user-confirmed | D-006：代选在原有临时分页缓存上扩展依赖；继续用章节/段落锚点 |
| D-007 | 保存操作复用持久化成功后发布及可见失败回退 | `app_controller.dart:416`；`reader_preferences.dart:31`；项目规范 P002 | yes | code-verified | D-007：现有 controller 先 await repository.saveSettings；本轮复用，不另建写入通道 |
| D-008 | 单一 frontend small form 与直接 design index | 当前免确认消息；canonical 路径检查均不存在 | yes | user-confirmed | D-008：代选 `design/frontend.md` 和 `design/00-index.md`；无 backend、转换或删除 |
| D-009 | 不增加依赖、在线服务或网络权限 | `proposal.md#Out of Scope`；当前免确认消息 | yes | user-confirmed | D-009：授权下保留当前网络、脚本与书源验收边界，仅扩展客户端能力 |

### 方案比较

1. **扩展现有设置及控件（采用）**：增加三个有界字段；复用保存通道、Slider、SwitchListTile、ListView 和当前分页器。可直接覆盖本轮验收。
2. **每书单独设置及新存储层（不采用）**：需新的继承、重置和合并规则，但本轮没有按书覆盖的需求。
3. **引入上游阅读配置或第二套排版引擎（不采用）**：扩大兼容面、许可证与测量差异，不适合本轮独立实现的范围。

唯一新组件 ReaderTocSheet 服务于当前目录异步排序、失败回退和原始索引选择的完整生命周期；不再增加 registry、service 或可插拔排序框架。

### Pre-write Confirmation Evidence

- Covered IDs: `D-001`, `D-002`, `D-003`, `D-004`, `D-005`, `D-006`, `D-007`, `D-008`, `D-009`
- Outstanding blocking decisions: `none`
- Explicit user authorization to write: 当前用户“不需要我确认，请按照你的最佳推荐，自行决策，继续往下走”，允许在本轮三项范围内代选并写入上述两个 small-form 路径，无转换/移除。阶段不额外等待，不伪造用户逐节审阅记录。

## 第二部分：技术方案详述

### 设计范围适用性

| 评审范围 | 要求 | Canonical owner section | 证据或不适用理由 |
| --- | --- | --- | --- |
| 架构主线 | 必填 | `#架构主线` | 现有设置到阅读布局的路径 |
| 核心对象与职责 | 必填 | `#核心对象与职责` | ReaderSettings、ReaderPreferences、ReaderScreen |
| 数据模型 | 适用 | `#数据模型` | 现有设置附加 JSON 键 |
| 状态、并发与执行流程 | 适用 | `#状态并发与执行流程` | 保存中的禁用、失败回退、关闭后完成 |
| 接口、权限与兼容边界 | 适用 | `#接口权限与兼容边界` | 组件回调、旧 JSON、逻辑锚点 |
| 前端方案 | 适用 | `#前端设计` | 目录弹层及阅读设置 |
| 风险、迁移、发布、回滚与监控 | 必填 | `#风险迁移发布回滚与监控` | 原始索引错位、样式测量不一致等具体场景 |
| 验证方案 | 必填 | `#验证方案` | 域测试、组件测试、真实 Web 与构建 |

### 架构主线

设置界面在本地预览选中的段距/字重，提交时禁用重复保存；经 AppController.updateSettings 写入成功后全局发布，失败显示错误并恢复已保存值。ReaderScreen 从已发布设置生成分页与滚动正文，改变排版时恢复原章节/段落，不持久化屏幕页码。

目录弹层的正倒序按钮调用现有 settings 保存通道，只更新 tocDescending；不调用正文偏好变更处理，因此不主动重置分页。列表 itemBuilder 将显示位置映射到原始章节索引，所有标题、当前章、缓存标记和选择回调都使用该索引。

### 核心对象与职责

| 对象/模块 | 职责 | 不负责 | 协作对象 | 证据 |
| --- | --- | --- | --- | --- |
| ReaderSettings | 有界偏好及 JSON 兼容 | 不保存阅读位置 | 仓储、设置、阅读器 | `lib/domain/reader_settings.dart` |
| ReaderPreferences | 调节、预览、保存状态与回退 | 不直接写数据库 | onChanged、ReaderParagraph | `lib/ui/components/reader_preferences.dart` |
| ReaderTocSheet | 展示顺序、待保存状态、原始索引回调 | 不重排领域章节、不联网 | Book、onOrderChanged、onChapterSelected | 本轮新增组件 |
| ReaderScreen | 接入偏好和目录，保持内容锚点 | 不另建排版引擎 | ReaderPaginator、ReaderParagraph | `lib/ui/screens/reader_screen.dart` |
| AppRepository / AppController | 复用既有设置读写、保存后通知 | 不新增表或副写通道 | ReaderSettings | `app_repository.dart:144`、`app_controller.dart:416` |

### 数据模型

#### 完整字段定义

| 字段 | 类型 | 必填/空值 | 默认值 | 关联/约束 | 证据 |
| --- | --- | --- | --- | --- | --- |
| paragraphSpacing | double | JSON 可缺失 | 20 | 0–40；非数值/非有限值回退 20，copyWith 与读取保持边界 | D-002/D-003 |
| boldText | bool | JSON 可缺失 | false | 只把 JSON true 解释为开启，其他类型回退关闭 | D-002/D-004 |
| tocDescending | bool | JSON 可缺失 | false | 默认正序；只影响展示 | D-002/D-005 |

现有 theme、flow、fontSize 和 lineHeight 的字段含义、默认值及读取方式不变。字段定义以此表为唯一载体，不重复模型代码草图。

#### 存储、继承与访问路径

ReaderSettings 是普通 Dart 值对象，没有 ORM、公共模型基类、manager、mixin、继承字段、软删除或审计字段。物理存储为 Sembast `meta` store 的 `settings` 单键记录，证据为 `app_repository.dart:17`、`:144–152`。查询是按已知键整体读取/覆盖，因此现有主键路径已满足需求，不新增索引、记录或章节副本。

增加三个小标量键，不改变书籍、章节、书签或来源记录。没有 schema migration；旧版本读取时忽略新键，但旧版本重新保存设置会丢弃未知键，回到新版后使用默认值。无需删除任何原始阅读数据。

### 状态、并发与执行流程

- ReaderPreferences 沿用现有 `_saving` 与 `_save`：预览可先更新；保存期间禁用其他写入；错误恢复最近成功保存的值并通过 showMessage 显示，不使用弹层打开时的过期快照。
- ReaderTocSheet 独立持有 `_descending`、`_saving`；排序保存失败恢复原值；关闭后迟到完成不得 setState。选择回调始终传原始索引，等待保存时不允许再次切换排序。
- 保存目录顺序时使用 controller 当前 settings 的 copyWith，保留其他最新偏好。新组件不绕过 controller，也不产生网络请求。
- 排版样式：分页和滚动正文都按 boldText 选择 400/700 字重；分页传 paragraphSpacing。布局 key 包含新排版字段；同段续页仍是 0 段距。
- 预览改用两个现有 ReaderParagraph，中间以 paragraphSpacing 分隔，共用实际字号、行高和字重；不修改正文原文。

### 接口、权限与兼容边界

ReaderTocSheet 接收 Book、原始当前章节索引、初始 descending，以及异步 onOrderChanged(bool) 和 onChapterSelected(int) 回调。公共组件契约明确索引属于 Book.chapters 的原始顺序。

不新增路由或远程 API。仍由现有 ReaderScreen._jump 先保存位置再切章；保存失败保留当前阅读器。偏好改变只保证逻辑锚点不变，屏幕页数和页码可以因排版重新计算。

### 前端设计

#### UI/UX Settings Source

- Settings read: `fp-docs/settings/frontend.md`、`fp-docs/settings/code-standards.md`；无原型或 Figma 输入。
- Existing references: `reader_preferences.dart:49–221`、`reader_screen.dart:792–847`、`lib/ui/theme.dart`。
- Confirmed tokens/components: Material 3；现有 section 间距 24/12、容器 padding 20、圆角 10、目录 padding 24/5、弹层高度 0.65 视口；均从相邻实现复用。
- Confirmed UX rules: 保存期间禁用；错误可见且回退；窄屏不溢出；正文主题与应用蓝灰配色不变。
- Unknowns requiring user confirmation: none；新增控件和参数均按本轮明确自主授权代选。

#### Visual Source

- 类型：UI/UX spec + existing code。
- 来源：上述 settings 和相邻设置/目录页面，不打开 Figma 或新建原型。
- 可信边界：组件和既有尺寸已确认，新增控件的窄屏、夜间、保存状态在实现后通过浏览器与组件测试验收。

#### UI 组件树与 Figma 解析映射

| 设计区域/节点 | 目标 DOM/组件层级 | 项目组件 | 布局策略 | 关键 token/尺寸 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 段距设置 | ReaderPreferences → 标签行 + Slider | 复用现有 Slider 模式 | Column + Row/Spacer | section 24/12；参数 0–40、10 divisions | 非 Web DOM；显示 px 单位 |
| 正文加粗 | ReaderPreferences → SwitchListTile | Material 3 开关 | 行内开关，不引入固定宽度 | 复用当前文字样式与主题 | 独立语义标签 |
| 预览 | 现有预览容器 → 两个 ReaderParagraph | 已有缩进组件 | Column + 可调间隔 | 原 padding 20、圆角 10 | 不改容器配色 |
| 目录顺序 | ReaderTocSheet → 目录头 + IconButton | 现有目录视觉与按钮 | Row/Spacer + Expanded ListView | 原 padding 24/5，0.65 视口 | 标出当前正序/倒序；保留章数与缓存标志 |

#### Visual Checks

- [ ] 375×812 下设置可滚动到段距、加粗和预览，标签与开关不溢出；来源：现有设置弹层与 frontend settings。
- [ ] 段距 0/20/40 可见，粗体预览和正文一致；真实新段仍空两字，同段续页不重复缩进；来源：D-003/D-004 与现有 ReaderParagraph。
- [ ] 目录正序/倒序状态可辨，当前章和缓存标志随原始章节移动，点击打开正确章；来源：现有目录和 D-005。
- [ ] 纸张/夜间主题不引入新配色；正文无 overflow，桌面仍遵守 760 最大内容宽度；来源：现有 ReaderScreen 和 frontend settings。
- [ ] 保存中禁止重复提交，保存失败可见并恢复已保存值；来源：ReaderPreferences._save 和项目规范 P002。

### 风险、迁移、发布、回滚与监控

| 具体失败场景 | 影响 | 预防或处理 | 发布/回滚/监控安排 | 证据 |
| --- | --- | --- | --- | --- |
| 倒序后把显示索引当原索引 | 打开错误章节/错误当前章 | 所有目录数据与回调统一映射原始索引，不修改 Book.chapters | 正序/倒序分别点击首尾并断言原始索引 | D-005 |
| 粗体/段距仅改绘制，未改测量 | 页尾溢出、重复或跳字 | 共用 style、paragraphSpacing 和布局 key | 组合参数测量测试及真实阅读截图 | D-004/D-006 |
| 旧 JSON 缺字段或值损坏 | 冷启动失败/异常排版 | 字段默认、有限值校验与范围约束 | 领域与仓储往返测试 | D-002/D-003 |
| 目录关闭后保存回调到达 | setState after dispose | 每次异步完成检查 mounted | 迟到完成组件测试 | D-005/D-007 |
| 存储失败却看似保存 | 偏好重启丢失且误导用户 | 延用 controller 成功后发布、UI 回退和错误文案 | 故障组件测试，不在真实用户库制造损坏 | D-007 |

无本轮承诺范围内的有意延后项。历史换源和不安全异常注入验收缺口不属于本轮，不改变其状态。任务检查仅在本轮执行期间运行，完成/明确阻塞后停用；不更改系统权限、依赖或安全策略。

### 验证方案

| 验证项 | 命令或操作 | 预期结果 | 覆盖的设计结论 | 证据 owner |
| --- | --- | --- | --- | --- |
| 红绿领域/仓储 | 新字段默认、损坏值、copyWith、JSON 与真实 Sembast 往返测试 | 先红后绿，原设置不丢失 | D-002/D-003 | 执行记录 |
| 控件与目录 | Widget 测试调节、预览、禁用、失败回退、迟到完成、原索引 | 状态与持久化契约一致 | D-004/D-005/D-007 | 执行记录 |
| 阅读集成 | 两种 flow 下应用字段、重排、保持逻辑锚点；长段分页完整性 | 无异常、溢出或文本丢失 | D-004/D-006 | 执行记录 |
| 全量门禁 | format、analyze、flutter test、Web release、Android debug | 分别记录命令、退出码与既有警告 | 工程质量与兼容 | 执行记录 |
| 真实页面 | 上述 Visual Checks；通过 preview 工具操作正式 Web 构建 | 截图、语义与无新 console error 的证据 | 视觉与交互 | 执行记录 |
| 最终审查 | fp-final-review，区分本轮增量和已有脏工作树 | 不把既有改动或历史阻塞误报为本轮成果 | 范围与交付 | 最终审查产物 |
