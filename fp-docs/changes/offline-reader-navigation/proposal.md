# 离线阅读目录与排版能力迁移

## Why

当前阅读器已支持左右分页、滚动阅读及两字首行缩进，但目录只能正序展示，正文段距固定，也没有加粗开关。长目录和不同阅读偏好下，用户仍缺少基础的阅读控制。

本轮从已核实的 Legado 可见能力中选择目录倒序、段距调节和正文加粗。三项均可在现有 Flutter 客户端内独立实现，不需要在线服务、新依赖或扩大书源执行权限。

## What Changes

### 1. 目录正序与倒序

阅读目录增加顺序切换，并保存用户的目录顺序偏好。改变的只有列表展示顺序，不修改书籍的实际章节列表、章节 ID、阅读位置或书签。无论正序还是倒序，点击目录项都打开同一个原始章节；当前章节与缓存标识保持正确。

### 2. 段距调节

阅读设置增加段距调节。左右分页、上下滚动及设置预览使用同一段距偏好。已有设置缺少该字段时保留原有 20 px 默认值；首行两字缩进和同段跨页不增加段距的规则不变。设置变更后保持章节/段落锚点，而不是保存旧屏幕页码。

### 3. 正文加粗

阅读设置增加正文加粗开关，默认关闭。正文显示、分页测量及预览使用相同字重，避免字重变化后出现漏字、重复或溢出。偏好随其他阅读设置保存，重新打开应用后恢复；不更改章节原文。

## Capabilities

### New Capabilities

- `toc-display-order`：保存目录展示顺序，并以原始章节索引完成跳转。
- `reader-paragraph-spacing`：在两种阅读流中统一调节逻辑段落间距。
- `reader-bold-text`：切换并保存正文粗体，测量与绘制保持一致。

### Modified Capabilities

- `reader-preferences`：扩展现有阅读设置及预览，继续采用保存成功后发布状态、失败可见的模式。
- `reader-layout`：字号、行距、段距和字重共同决定临时分页，内容锚点与原文保持不变。

## Out of Scope

- 简繁转换、自动滚动、朗读、定时退出、EPUB 或其他新文件格式。
- 目录筛选、定位当前章、书内全文搜索；这些不与本轮三项能力捆绑。
- 全量移植 Legado、复制或逐行翻译其 GPL 实现。
- 网络、书源引擎、脚本许可、换源、缓存协议或数据库架构改造。
- 更改品牌、应用配色、两字缩进或刚修复的按实际排版行断页规则。
- 清理既有工作树、提交、推送、自动归档，或关闭历史真实换源验收缺口。

## Impact

- `lib/domain/reader_settings.dart`：以向后兼容的附加字段表达段距、正文加粗和目录顺序。
- `lib/ui/components/reader_preferences.dart`：复用 Material 3 控件扩展设置与正文预览。
- `lib/ui/screens/reader_screen.dart`：将偏好应用于分页和滚动，保持逻辑锚点；接入目录顺序切换。
- `lib/ui/reader/reader_paginator.dart`、`reader_paragraph.dart`：复用现有测量与缩进能力，不引入第二套排版算法。
- 目录 UI 如需局部状态，新增范围明确的目录组件；技术形态由设计阶段确定。
- 对应领域、仓储、组件及阅读恢复测试：覆盖旧数据、往返保存、失败回退、原始索引跳转及两种阅读流。
- 既有 Sembast `meta/settings` 记录可保存新增键，不引入新表、索引或外部服务。具体字段边界与实现方案由设计阶段记录。

### Handoff Decision Ledger

授权说明：用户本轮明确表示“不需要我确认，请按照你的最佳推荐，自行决策，继续往下走”。这条指令覆盖默认的逐项提问和阶段等待。以下 `user-confirmed` 的依据是明确的自主决策授权；具体代选值逐项列出，不代表用户曾按 ID 逐条审阅。后续阶段必须保留这一区别。

| ID | Decision | Source | Blocking | Status | Evidence / explicit confirmation |
| --- | --- | --- | --- | --- | --- |
| P-001 | 本轮目录迁移选择仅改变展示顺序的正序/倒序 | 本轮免确认用户消息；`reader_screen.dart:792` | yes | user-confirmed | P-001：在用户明确自主决策授权内代选目录顺序切换；不改变原始章节顺序 |
| P-002 | 段距可调并兼容旧设置的 20 px 默认值 | 本轮免确认用户消息；`reader_paginator.dart:79`、`reader_screen.dart:288` | yes | user-confirmed | P-002：在授权内代选段距设置；现有默认值由代码核实，展示适用于两种阅读流 |
| P-003 | 正文加粗为默认关闭的持久化偏好 | 本轮免确认用户消息；`reader_screen.dart:294`、`:353` | yes | user-confirmed | P-003：在授权内代选加粗开关；当前普通字重由代码核实 |
| P-004 | 提案使用 small form，新建当前变更的唯一入口 | 本轮免确认用户消息；目标路径存在性检查 | yes | user-confirmed | P-004：代选 `fp-docs/changes/offline-reader-navigation/proposal.md`；目标目录此前不存在，无覆盖、转换或删除 |
| P-005 | 在授权内连续推进设计、计划、实现和验证，不提交或推送 | 当前用户消息“自行决策，继续往下走”；此前迁移请求及不提交约束 | yes | user-confirmed | P-005：后续阶段不重复等待人工确认，但必须校验产物、运行测试并如实记录失败 |
| P-006 | 保留章节/段落内容锚点和保存成功后发布状态的现有约束 | `reader_screen.dart:166`、`app_controller.dart:416`；项目规范 P002/P004 | yes | code-verified | P-006：读取现有位置与设置更新逻辑；本轮不更换其含义或存储架构 |
| P-007 | 本轮没有后端、远程接口或权限模型变更 | 三项客户端功能范围及现有 Flutter 结构 | no | not-applicable | P-007：所有新增行为均在既有客户端阅读路径内，无新增网络调用 |

### Pre-write Confirmation Evidence

- Covered IDs: `P-001`, `P-002`, `P-003`, `P-004`, `P-005`, `P-006`, `P-007`
- Outstanding blocking decisions: `none`
- Explicit user authorization to write: 本轮用户明确回复“不需要我确认，请按照你的最佳推荐，自行决策，继续往下走”；据此代选上述范围和 small form，并授权新建 `fp-docs/changes/offline-reader-navigation/proposal.md`，无覆盖或移除动作。
- 写后交接：提案文件核验通过后按同一自主授权进入设计；不得把该授权写成用户已逐条审阅提案。
- 上游行为参考：`HapeLee/legado-with-MD3` 固定提交 `b21025d3769ec9c4028514914f3c555a1ba284b8` 的 README 与 `app/src/main/res/values/strings.xml`；已核实 `reverse_toc`、`paragraph_size` 和 `text_bold`。只参考公开行为，独立实现。
