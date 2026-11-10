# 现有页面按设计稿还原外观

本提案把应用里已经存在的页面，按 `D:\download\阅读助手_完整设计稿.html` 的手机界面对齐。窄屏跟随设计稿的布局、间距、颜色、字号和组件。宽度达到 1000 时，继续使用现有左侧栏。

## Why

读者打开书架、发现、阅读和我的时，看到的间距、层级和组件仍与设计稿有差距。最近的阅读页和书架已经按稿收紧过，其余已有页面和共用组件还没有按同一份手机稿对齐。

现在做，是因为视觉基准已经明确：设计稿第 12 行的 `:root` 色值，与 `lib/ui/theme.dart` 的 `AppColors` 一致。缺的是页面和组件的还原，不是新的产品流程。

## What Changes

### 1. 窄屏已有页面按手机稿对齐

手机宽度上，已有页面的标题、列表、卡片、底栏、弹层和空状态按设计稿排列。页面继续显示真实书籍、进度、笔记和书源，不改成设计稿里的示例数字。

覆盖的已有界面：

- 主框架：书架、发现、我的，以及窄屏底部导航
- 书架分组、整理、移动和相关弹层
- 发现、书源浏览、搜索和搜索范围
- 书籍详情、阅读页、目录、划线、阅读设置和换源
- 听书、笔记、阅读记录、导入、书源、备份、设置、欢迎和读完

### 2. 宽屏保持现有侧栏

宽度 ≥ 1000 时，保留 `lib/ui/app_shell.dart` 的左侧栏，并继续隐藏底部导航。内容区使用同一套已对齐的组件，不把手机框拉满桌面，也不横向溢出。

### 3. 共用视觉只修正偏离设计稿的用法

`AppColors` 继续使用已经与设计稿一致的主色 `#2878F0`、背景 `#F3F4F6`、文字 `#23262C`、次级文字 `#858B96`、分割线 `#EDF0F3` 和淡蓝 `#EDF4FF`。按钮、卡片、弹层和点击热区沿用 `AppRadii`、`AppSpacing` 中与设计稿一致的数值。页面上仍偏离这些数值的间距和组件，改回设计稿。

## Capabilities

### New Capabilities

- 无

### Modified Capabilities

- `existing-screen-appearance`：已有页面在窄屏上的布局、间距、颜色、字号和组件按手机设计稿呈现。
- `adaptive-shell`：窄屏仍用底部三项导航；宽度 ≥ 1000 时仍用左侧栏，并隐藏底部导航。
- `existing-interaction-presentation`：分组、搜索、详情、阅读、换源、笔记和设置等已有操作的外观按设计稿呈现。点击之后的现有流程保持不变。

## Out of Scope

- 设计稿外层的工作室顶栏、屏幕目录、标注页和图标预览。
- 应用里还没有的独立流程。
- 阅读分页、换源、导入和备份的既有业务规则。
- 后端、新依赖，以及把宽屏重做成另一套桌面稿。
- 把示例时长、示例书目或演示文案写进真实数据。

## Impact

- `lib/ui/theme.dart`：核对并继续使用已与设计稿 `:root` 一致的色值、圆角和间距。
- `lib/ui/app_shell.dart`：窄屏底栏按设计稿对齐；宽度 ≥ 1000 的侧栏结构保留。
- `lib/ui/screens/`：书架、发现、我的、搜索、阅读、听书、笔记、阅读记录、导入、书源、备份、设置、欢迎和读完的外观。
- `lib/ui/components/`：分组、详情、目录、换源、阅读设置、笔记和共用行、卡片的外观。
- `lib/ui/design_icons.dart`：图标与设计稿对应项不一致时修正映射。
- `test/`：为受影响的布局、导航和关键空状态补充或更新组件测试。

交付策略：一次变更覆盖上述已有界面。后续计划按页面和共用组件拆任务。验证包括窄屏和宽屏，加载、空、失败状态，以及阅读位置恢复。

### Handoff Decision Ledger

| ID | Decision | Source | Blocking | Status | Evidence / explicit confirmation |
| --- | --- | --- | --- | --- | --- |
| P-001 | 对齐已有页面的外观和已有交互呈现，不新增设计稿独有流程 | user answer | yes | `user-confirmed` | P-001: selected「把应用里已有的页面外观对齐这份完整设计稿」; user message「2」 |
| P-002 | 窄屏按手机稿对齐；宽度 ≥ 1000 沿用现有侧栏并隐藏底栏 | user answer | yes | `user-confirmed` | P-002: selected「窄屏按手机稿对齐，宽屏沿用现有侧栏」; user message「1」 |
| P-003 | 全局色值继续使用当前 `AppColors`，其值已与设计稿 `:root` 一致 | `lib/ui/theme.dart:11-23`；设计稿第 12 行 | no | `code-verified` | P-003: `blue #2878F0`、`background #F3F4F6`、`ink #23262C`、`muted #858B96`、`line #EDF0F3`、`softBlue #EDF4FF` 与设计稿 `--blue`、`--canvas`、`--ink`、`--muted`、`--line`、`--blue-soft` 一致 |

### Pre-write Confirmation Evidence

- Covered IDs: `P-001`, `P-002`, `P-003`
- Outstanding blocking decisions: `none`
- Explicit user authorization to write: 用户已看到 slug `ui-design-restoration`、入口 `fp-docs/changes/ui-design-restoration/proposal.md`，以及 Why / What Changes / Out of Scope / Impact 摘要。用户随后回复「请用你的最佳推荐决策，不需要再询问我」。该回复授权按已终态的 P-001、P-002、P-003 写入这份 small proposal，范围是已有页面的窄屏对齐和现有宽屏侧栏，不覆盖其他产物。
