# 阅读分页与书源切换能力

本提案为现有 Flutter 阅读应用补齐左右分页阅读、简化书源导入，并建立安全的多书源切换、封面刷新和正文整理能力。实现沿用当前段落锚点、声明式书源协议和本地持久化边界，不复制上游 Kotlin 代码。

## 后续需求澄清（2026-10-31）

用户随后要求每个真实段落首行空两字，并修复跨页续段的断裂。正文整理据此保留来源的逻辑换行，不默认合并或重新切分段落；下文“合并被网页布局拆散的连续文本”不作为启用启发式重分段的授权。当前段落与安全替换边界见 [书源格式与边界](../../../docs/BOOK_SOURCES.md#正文段落与替换)。

## Why

当前阅读页只提供纵向滚动，不能用常见的左右滑动方式翻页。纸张主题虽已有暖色背景，但与用户提供的微信读书参考图仍有差异。

书源导入目前要求用户先预览并逐项勾选，再执行提交。这个两阶段界面对普通导入增加了不必要的操作。

远程书籍一旦加入书架，就固定绑定单一 `sourceId` 和目录。来源失效时，用户无法搜索同一本书的其他来源，也不能刷新封面或在保持阅读进度的前提下手动换源。正文解析后也缺少统一的排版整理步骤。

参考项目 `HapeLee/legado-with-MD3` 的公开 README 确认了阅读排版、广告清理和正文替换等用户能力。2026-10-30 的受限调研未能从 GitHub 目录页取得具体换源实现，因此本项目只借鉴用户行为，按现有 Flutter 架构独立实现。

## What Changes

### 1. 左右分页阅读与暖纸色

- 新增左右滑动的分页阅读模式，并将其作为默认阅读方式。
- 保留纵向滚动模式，用户可在阅读设置中切换，选择会持久化。
- 分页只影响展示，不以屏幕页号替代现有章节索引和段落索引。
- 字号、行高或视口变化后，以当前段落锚点重新分页并恢复位置。
- 将“纸张”主题调整为用户参考图中的暖奶油纸色，同时保持明亮和夜间主题不变。

### 2. 一步确认导入书源

- 保留 JSON、文件和 URL 的格式校验、网络限制及原子写入。
- 移除导入后的预览列表和逐源勾选。
- 用户点击确认后，应用直接执行准备、校验和提交；成功时返回新增与更新数量，失败时不保存部分结果。
- 导入过程中继续支持取消、超时、重定向和错误提示。

### 3. 候选书源搜索与手动换源

- 以当前书名和作者在启用书源中搜索候选书籍。
- 候选结果展示来源、书名、作者和可用封面，用户可手动选择目标来源。
- 换源前加载目标详情和目录；加载失败时保留原来源、原目录和缓存。
- 换源成功后保持书籍 ID、书架记录、笔记和段落阅读锚点。
- 章节映射优先使用规范化章节名；无法匹配时回退到相邻章节索引，并将段落索引约束到新章节范围。
- 与新目录不兼容的旧正文缓存不再作为新来源内容使用；切换过程通过仓储事务原子保存。

### 4. 封面获取与刷新

- 复用现有书源 `ruleSearch.coverUrl` 和 `ruleBookInfo.coverUrl` 解析能力。
- 搜索结果、详情加载和换源候选都可提供封面 URL。
- 书籍详情页提供手动刷新封面入口，从当前来源重新获取详情并在成功后持久化。
- 刷新失败时保留现有封面，不把临时失败写入书籍记录。

### 5. 正文整理排版

- 在正文规则解析完成后执行有界、确定性的本地整理。
- 规范化换行与空白，移除空段，合并被网页布局拆散的连续文本，并避免重复章节标题。
- 支持书源声明式正文替换规则；继续禁止远程原生代码、任意脚本和越过现有安全策略的处理。
- 整理结果仍保存为段落列表，兼容现有段落阅读位置、书签和离线缓存。

## Capabilities

### New Capabilities

- `horizontal-reader-pagination`: 按视口左右分页，并用段落锚点保存与恢复阅读位置。
- `book-source-candidate-search`: 在启用书源中查找同名同作者候选书籍。
- `manual-book-source-switching`: 用户选择候选来源后，原子替换来源与目录并保持书籍身份和阅读锚点。
- `book-cover-refresh`: 从当前书源重新获取并持久化封面。
- `content-normalization`: 对解析后的正文执行有界排版整理和声明式替换。

### Modified Capabilities

- `reader-theme`: “纸张”主题改为参考图的暖奶油色，并新增分页模式偏好。
- `source-import`: 从预览后提交改为一次确认后的校验与原子提交。
- `book-source-runtime`: 在现有搜索、详情、目录和正文能力上增加候选匹配与切源编排。

## Out of Scope

- 不复制、翻译或移植 `legado-with-MD3` 的 Kotlin 实现。
- 不承诺兼容 Legado 的全部书源语法、登录、Cookie、WebView、媒体、文件或设备 helper。
- 不启用远程任意脚本、原生代码桥、公共代理或浏览器安全绕过。
- 不自动批量替换所有书架书籍来源；换源由用户在单本书上发起并确认。
- 不改变现有书源数量、JSON 深度、同源、超时、重定向、响应大小和 DOM 上限。

## Impact

- `lib/domain/book.dart`：支持以原子语义替换来源、目录和封面，同时保持书籍身份及用户数据。
- `lib/domain/reader_settings.dart`：持久化阅读分页模式，并为旧数据提供兼容默认值。
- `lib/domain/source_definition.dart`：按现有声明式协议读取适用的正文替换规则。
- `lib/services/source_engine.dart`：编排候选搜索、详情/目录刷新、封面解析和正文整理。
- `lib/application/app_controller.dart`：暴露候选搜索、换源、封面刷新和一致性状态更新。
- `lib/data/app_repository.dart`：事务化保存换源结果，避免失败时发布部分状态。
- `lib/ui/screens/reader_screen.dart`：实现左右分页、模式切换和段落锚点恢复。
- `lib/ui/components/reader_preferences.dart`：展示并保存阅读模式和调整后的纸张主题。
- `lib/ui/components/source_import_sheet.dart`：移除预览状态，改为一次确认导入。
- `lib/ui/components/book_details.dart`：增加换源和封面刷新入口及候选选择界面。
- `test/`：增加分页恢复、一步导入、切源回滚、章节映射、封面刷新和正文整理回归测试。

### Handoff Decision Ledger

| ID | Decision | Source | Blocking | Status | Evidence / explicit confirmation |
| --- | --- | --- | --- | --- | --- |
| P-001 | 本 change 覆盖左右分页、暖纸色、一步导入、候选搜索、手动换源、封面刷新和正文整理 | 用户原始需求；本次会话实施路径选择 | yes | `user-confirmed` | P-001: selected 完整分阶段能力范围；user message 要求“把 legado-with-MD3 这块功能搬过来”，并选择“走 fp-start auto 模式” |
| P-002 | 按当前 Flutter 架构独立实现，不复制或翻译上游 Kotlin | `fp-docs/settings/code-standards.md:21-26`；项目全局约束 | yes | `code-verified` | P-002: 当前书源是有界声明式协议，且项目约束禁止翻译上游 Kotlin；现有实现路径为 Dart/Flutter |
| P-003 | 换源保留书籍身份、笔记和段落锚点，并原子更新来源、目录与缓存 | 用户 auto 授权；`fp-docs/settings/code-standards.md:14-33` | yes | `user-confirmed` | P-003: selected 保持身份、段落锚点与事务一致性；user message 明确要求“用你的最佳实践完成，不要询问我” |
| P-004 | 导入保留准备和校验，但移除预览与逐源选择 | 用户原始需求 | yes | `user-confirmed` | P-004: selected 一次确认后校验并原子提交；user message 要求“不要预览，就直接确认导入即可” |
| P-005 | 纸张主题采用参考图的暖奶油纸色方向 | 用户原始需求及附图 | yes | `user-confirmed` | P-005: selected 参考图暖奶油纸色；user message 要求纸张颜色参考所附微信读书截图 |
| P-006 | 只实现点名能力块，不扩展到登录、远程脚本或全量 Legado 兼容 | 用户 auto 授权；`fp-docs/settings/code-standards.md:21-26` | yes | `user-confirmed` | P-006: selected 现有安全协议内的最小完整能力；user message 明确委托按最佳实践完成 |
| P-007 | Proposal 使用 small form，写入 `fp-docs/changes/reader-paging-source-switching/proposal.md` | artifact-layout contract；本次 Glob 检查 | yes | `code-verified` | P-007: 目标 slug 下无现有文件，预计 proposal 未超过 500 行或 30,000 字符，无转换或删除 |
| P-008 | 外部调研限制在指定 GitHub 仓库的 5 个页面 | 用户选择的完整分阶段选项；本次授权边界 | no | `user-confirmed` | P-008: selected 仅 `github.com/HapeLee/legado-with-MD3`、最多 5 个页面；user message 选择完整分阶段并要求继续 auto |
| P-009 | 按已展示摘要和 exact path 写入 proposal 并继续后续阶段 | 用户本次会话授权 | yes | `user-confirmed` | P-009: selected 写入本 proposal 并继续；user message 为“走 fp-start auto 模式，请你用你的最佳实践完成，不要询问我” |

### Pre-write Confirmation Evidence

- Covered IDs: `P-001`, `P-002`, `P-003`, `P-004`, `P-005`, `P-006`, `P-007`, `P-008`, `P-009`
- Outstanding blocking decisions: `none`
- Explicit user authorization to write: 用户在本次会话明确要求“走 fp-start auto 模式，请你用你的最佳实践完成，不要询问我”，授权按上述范围、small form 和 `fp-docs/changes/reader-paging-source-switching/proposal.md` 写入并继续完整流程；不授权提交、推送或合并。
