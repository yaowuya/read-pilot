# 现有页面按设计稿还原外观 — 技术方案设计

窄屏已有页面按 `D:\download\阅读助手_完整设计稿.html` 的手机框对齐。实现方式是修正现有 Flutter 组件和页面间距，不新建一套界面框架。宽度 ≥ 1000 时保留现有左侧栏。

## 第一部分：架构决策

### Decision Ledger

| ID | Decision | Source | Blocking | Status | Evidence / explicit confirmation |
| --- | --- | --- | --- | --- | --- |
| D-001 | 视觉来源是用户给出的完整设计稿 HTML，不使用 Figma | `proposal.md` P-001 | yes | `user-confirmed` | D-001: selected「以 `D:\download\阅读助手_完整设计稿.html` 的手机界面为视觉来源」; user message「2」确认 P-001，来源即该 HTML |
| D-002 | 在现有页面和 `lib/ui/components/design.dart` 上修正外观，不新建平行组件库 | user answer | yes | `user-confirmed` | D-002: selected「在现有组件上按设计稿修正」; user message「请用你的最佳推荐决策，不需要再询问我」选择该推荐 |
| D-003 | 只写 small `design/frontend.md` 与 `design/00-index.md`，不写后端设计，不迁移旧路径 | user answer | yes | `user-confirmed` | D-003: selected「small frontend-only，路径 `design/frontend.md` 与 `design/00-index.md`」; user message「请用你的最佳推荐决策，不需要再询问我」选择该推荐 |

### 决策 1：视觉来源

- **ID**：`D-001`
- **选择**：以 `D:\download\阅读助手_完整设计稿.html` 的手机界面为视觉来源。
- **理由**：提案已把这份 HTML 定为窄屏外观基准。文件内没有 Figma 链接。工作室顶栏、屏幕目录和标注页不是应用界面。
- **来源**：`proposal.md` P-001。
- **状态**：`user-confirmed`
- **是否阻塞**：是

### 决策 2：在现有组件上修正

- **ID**：`D-002`
- **选择**：在现有页面和 `lib/ui/components/design.dart` 上修正外观。
- **理由**：`LargeTitle`、`ListRow`、`AppTopBar` 和 `AppColors` 已经按这份设计稿建立。当前偏差是间距和个别硬编码颜色，直接改这些实现就能满足验收。新建平行组件库没有当前需求。
- **来源**：本轮用户回复选择推荐项。
- **状态**：`user-confirmed`
- **是否阻塞**：是

### 决策 3：设计产物形式

- **ID**：`D-003`
- **选择**：small `design/frontend.md`，并由 `design/00-index.md` 直接指向它。不创建 `design/backend.md`，不删除任何旧设计路径。
- **理由**：本次没有后端变更。预计前端设计低于 500 行和 30,000 字符。
- **来源**：本轮用户回复选择推荐项。
- **状态**：`user-confirmed`
- **是否阻塞**：是

### Pre-write Confirmation Evidence

- Covered IDs: `D-001`, `D-002`, `D-003`
- Outstanding blocking decisions: `none`
- Explicit user authorization to write: 用户回复「请用你的最佳推荐决策，不需要再询问我」。该回复授权写入 `fp-docs/changes/ui-design-restoration/design/00-index.md` 和 `fp-docs/changes/ui-design-restoration/design/frontend.md`。不写入后端设计，不移除其他路径。

## 第二部分：技术方案详述

### 设计范围适用性

| 评审范围 | 要求 | Canonical owner section | 证据或不适用理由 |
| --- | --- | --- | --- |
| 架构主线 | 必填 | `#架构主线` | 提案要求只改已有页面外观 |
| 核心对象与职责 | 必填 | `#核心对象与职责` | 现有 `AppColors`、共用组件和各屏 |
| 数据模型 | 条件适用 | `N/A` | 不新增或修改持久化字段 |
| 状态、并发与执行流程 | 条件适用 | `N/A` | 继续使用现有 `AppController` 和页面局部状态，不新增状态机 |
| 接口、权限与兼容边界 | 条件适用 | `N/A` | 不新增路由、接口或权限 |
| 前端方案 | 条件适用 | `#前端设计（仅 UI 范围）` | 本次全部是界面外观 |
| 风险、迁移、发布、回滚与监控 | 必填 | `#风险迁移发布回滚与监控` | 间距变化可能影响阅读分页测试 |
| 验证方案 | 必填 | `#验证方案` | 组件测试与窄屏、宽屏核对 |

### 架构主线

界面数据仍是 `AppController` 里的书籍、阅读位置、笔记和书源。这些对象的字段不变。读者打开应用后，窄屏仍进入书架、发现或我的。页面读取上述数据，再用现有共用组件绘制。本次只改变间距、字号、圆角和颜色。点击后的现有流程保持不变。

最简单可行方案是修正 `AppSpacing.page`、`LargeTitle`、`ListRow`、`AppTopBar` 和各屏里偏离设计稿的硬编码间距。Flutter 的 `Row`、`Column`、`GridView` 和 `SafeArea` 继续承担布局。不增加主题引擎、新状态库或新依赖。

从一开始就会采用的结构也是这一套共用组件。可核验单元按共用度量、主框架、书架与发现、阅读相关界面、其余已有页面拆开。宽屏分支不改：`lib/ui/app_shell.dart` 在宽度 ≥ 1000 时显示左侧栏并隐藏底栏。

有意延后：无。

### 核心对象与职责

| 对象/模块 | 职责 | 不负责 | 协作对象 | 证据 |
| --- | --- | --- | --- | --- |
| `AppColors` / `AppSpacing` / `AppRadii` | 持有设计稿色值、页边距、圆角和热区 | 页面业务 | 全部界面 | `lib/ui/theme.dart:9-55` |
| `LargeTitle` / `AppTopBar` / `ListRow` | 绘制标题、子页顶栏和列表行 | 决定跳转到哪一屏 | 各 `Screen` | `lib/ui/components/design.dart:15-180` |
| `AppShell` | 窄屏底栏与宽屏侧栏 | 单页内部排版 | 书架、发现、我的 | `lib/ui/app_shell.dart:233-451` |
| 各已有 Screen 与 Sheet | 按真实数据组合上述组件 | 新业务流程 | `AppController` | `lib/ui/screens/`、`lib/ui/components/` |
| `ReaderPaginator` | 按当前阅读度量分页 | 为对齐外观而改变分页规则 | `ReaderScreen` | `lib/ui/reader/reader_paginator.dart:78` |

### 前端设计（仅 UI 范围）

#### 页面/视图

不新增页面。窄屏入口仍是底部「书架 / 发现 / 我的」。子页仍由现有 `Navigator.push` 进入搜索、阅读、笔记、导入、书源、备份和设置。欢迎页仍在首次进入时盖住主框架。

手机框宽度是 390。页内容左右边距采用设计稿 `.pad` 的 25。大标题行采用 `.large-title` 的上 12、右 19、下 9、左 25。子页顶栏高度采用 `.app-topbar` 的 55。底栏内容区保持图标、10 号文字和 4 像素选中圆点；底部安全区继续交给 `SafeArea`，不把设计稿里的 27 像素 Home 指示条写死。

#### 组件

复用下表中的现有组件。只有设计稿里重复出现、而 `AppColors` 尚未命名的面板底色 `#F5F7FA` 补到 `AppColors`。书架继续卡和我的统计卡都使用这个底色。

`AppSpacing.page` 从 20 改为 25，并改掉「稿面大约 24」的注释。阅读正文的分页测量不跟着这个页边距改。阅读页只调整顶栏、工具条、目录和设置弹层的外观。

#### Frontend Reuse Decisions

Frontend Scope: `refactor`

| Capability | Reference | Reuse Decision | Gap / Deviation | Verification |
| --- | --- | --- | --- | --- |
| 色值与圆角 | `lib/ui/theme.dart` `AppColors`、`AppRadii` | 直接复用 | 面板底色 `#F5F7FA` 尚未命名，我的页在 `profile_screen.dart:213` 硬编码 | 两处面板使用同一 `AppColors` 常量 |
| 页边距 | `AppSpacing.page`，当前 20 | 组合扩展 | 设计稿 `.pad` 为 25 | 窄屏主列表左右为 25 |
| 大标题与顶栏 | `LargeTitle`、`AppTopBar` | 直接复用 | 顶栏高度当前 52，设计稿 `.app-topbar` 为 55；标题边距由调用方各自传入 | 书架、发现、我的标题边距一致；子页顶栏高度 55 |
| 列表行 | `ListRow` | 直接复用 | 当前左右内边距 14，设计稿行在 25 页边距内、垂直 15 | 我的和设置行高、分割线与稿一致 |
| 底栏与侧栏 | `lib/ui/app_shell.dart` `_TabBar` | 直接复用 | 底栏结构已按稿绘制；核对上内边距 8 | 窄屏三项导航，宽屏无底栏 |
| 书架、发现、阅读、弹层 | 现有 Screen 与 Sheet | 直接复用 | 各屏仍有偏离 25 页边距或面板色的硬编码 | 对应页面的空态、列表和弹层测试 |

#### Figma Source Scope

来源不是 Figma。下表按已批准 HTML 的渲染函数拆验收单元。工作室外壳排除。

| Source node / revision reference | UI unit / state | Scope / exclusion reason | Visual Check / Task ID + Case ID | Annotation status / source |
| --- | --- | --- | --- | --- |
| HTML `renderShelf` 等书架函数 | 书架、分组、整理、移动、空态 | included | 计划阶段绑定 `frontend-001` 起 | not-applicable，静态 HTML 无独立标注层 |
| HTML `renderDiscover`、`renderSearch`、`renderSourceBrowse` | 发现、搜索、书源浏览 | included | 计划阶段绑定 | not-applicable |
| HTML `renderDetail`、`renderReader`、`renderToc` | 详情、阅读、目录、阅读设置、换源 | included，只改外观 | 计划阶段绑定 | not-applicable |
| HTML `renderProfile`、`renderNotes`、`renderStats`、`renderImport`、`renderSources`、`renderBackup`、`renderAppSettings`、`renderWelcome`、`renderAudio`、`renderFinish` | 已有对应页面 | included | 计划阶段绑定 | not-applicable |
| HTML `renderHeader`、`renderSidebar`、`renderOverview`、`renderPrototype`、`renderSpecs`、`renderIconPreview`、`renderLive` | 设计稿工作室外壳 | excluded，不是应用界面 | 无 | not-applicable |

#### Visual Source

- 类型：用户提供的静态设计稿 HTML
- 来源：`D:\download\阅读助手_完整设计稿.html`，手机框 `.phone` 为 390 × 855
- 可信边界：色值、页边距、标题、顶栏、底栏、列表行、三列书架、弹层圆角和主按钮已从 CSS 读出。各屏未逐条量过的内部间距，在实现该屏时回读对应 CSS，不用当前运行截图代替设计稿。

#### UI 组件树与 Figma 解析映射

| 设计区域/节点 | 目标 DOM/组件层级 | 项目组件 | 布局策略 | 关键 token/尺寸 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `.large-title` | 页面顶部横向标题行 | `LargeTitle` | Row，左右分布 | 左 25，上 12，右 19，下 9；标题 28 / 700 | 书架、发现、我的共用 |
| `.pad` | 页面内容 | 各屏 `Padding` | 垂直滚动列 | 左右 25 | `AppSpacing.page = 25` |
| `.book-grid` / `.book-card` | 三列封面 | 书架网格与 `BookCover` | 三列网格 | 列间距 22，行间距 25 | 不改封面绘制算法 |
| `.continue-card` / `.stats-card` | 浅底信息卡 | 书架继续卡、我的统计卡 | Row 或 Column | 底色 `#F5F7FA`，圆角 13 / 12 | 收进 `AppColors` |
| `.list-row` | 图标、文案、尾部 | `ListRow` | Row | 最小高度 61，垂直 15，图标间隙 13 | 左右由页边距提供 |
| `.tabbar` | 三项导航 | `_TabBar` | 等宽 Row | 选中蓝字加 4 像素圆点 | 宽屏不渲染 |
| `.app-topbar` | 返回、标题、操作 | `AppTopBar` | AppBar | 高度 55 | 不改返回行为 |
| `.sheet` | 底部分层 | 现有 `showModalBottomSheet` | 底部圆角面板 | 圆角 22，左右 25 | `AppRadii.sheet` 已是 22 |
| `.primary-btn` | 主操作 | 现有主按钮 | 通栏 | 最小高度 48，圆角 10，底色 `#2878F0` | 不新增按钮样式体系 |

#### Visual Checks

- [ ] 窄屏宽度小于 1000 时，书架、发现、我的左右内容边距为 25。来源：设计稿 `.pad`
- [ ] 这三个主页面的大标题为 28 / 700，边距为上 12、右 19、下 9、左 25。来源：设计稿 `.large-title`
- [ ] 子页顶栏高度为 55，返回按钮仍可返回。来源：设计稿 `.app-topbar`
- [ ] 窄屏底栏为书架、发现、我的三项；选中项为 `#2878F0` 文字加 4 像素圆点。来源：设计稿 `.tabbar`
- [ ] 宽度 ≥ 1000 时仍显示左侧栏，且没有底部导航，内容不横向溢出。来源：`lib/ui/app_shell.dart:233`
- [ ] 书架书籍为三列，列间距 22，行间距 25。来源：设计稿 `.book-grid`
- [ ] 继续阅读卡和我的统计卡底色为 `#F5F7FA`，且来自同一个 `AppColors` 常量。来源：设计稿 `.continue-card`、`.stats-card`
- [ ] 列表行最小高度 61，分割线使用 `AppColors.line`。来源：设计稿 `.list-row` 与 P-003
- [ ] 弹层顶部圆角为 22，主按钮最小高度 48、圆角 10。来源：设计稿 `.sheet`、`.primary-btn`
- [ ] 阅读分页规则不变；只改阅读页外壳。来源：提案 Out of Scope 与 `ReaderPaginator`

#### 路由

沿用 `lib/app.dart` 的 `/` 与 `/read/<encoded-book-id>`，以及 `AppShell` 里的 `Navigator.push`。不增加权限守卫。

#### 状态管理

沿用 `AppController` 的 `ChangeNotifier`。选择模式、弹层和搜索词继续留在对应 Screen 的局部状态。外观修正不写入新的全局状态。

### 风险、迁移、发布、回滚与监控

| 具体失败场景 | 影响 | 预防或处理 | 发布/回滚/监控安排 | 证据 |
| --- | --- | --- | --- | --- |
| 页边距从 20 改为 25 时误改阅读正文测量 | 分页结果变化，阅读位置测试失败 | 阅读正文边距不跟随 `AppSpacing.page` | 先跑现有阅读分页测试，失败则只收回阅读正文改动 | `reader_paginator.dart` |
| 宽屏被收成 390 手机列 | 左侧栏消失 | 只改窄屏度量，保留宽度 ≥ 1000 的分支 | 宽屏组件测试确认底栏不存在 | `app_shell.dart:233` |
| 列表行再叠加一层 14 像素内边距 | 行内容比设计稿更窄 | 行的左右间距只由页边距提供 | 我的页和设置页组件测试核对边距 | `design.dart` `ListRow` |

有意延后：无。

### 验证方案

| 验证项 | 命令或操作 | 预期结果 | 覆盖的设计结论 | 证据 owner |
| --- | --- | --- | --- | --- |
| 共用度量 | `flutter test` 中针对间距、顶栏、底栏和列表行的组件测试 | 页边距 25、顶栏 55、底栏选中圆点、列表行最小高度 61 | D-002 与组件映射 | 本节 |
| 阅读回归 | 现有 `test/reader_paginator_test.dart` 与阅读恢复测试 | 分页规则和恢复位置保持通过 | 阅读正文不跟随页边距 | 本节 |
| 窄屏与宽屏 | 宽度小于 1000 和宽度 ≥ 1000 各看主框架 | 窄屏有底栏；宽屏有侧栏且无底栏 | D-001、P-002 | 本节 |
| 静态分析 | `dart format` 与 `flutter analyze` | 本次改动无新增分析问题 | 实现约束 | 本节 |
| 注释自审 | 对照本次改动的公开组件说明 | 改过行为的组件仍说明职责；页边距注释与 25 一致 | 工程质量契约 | 本节 |

实现前应当失败的测试：把页边距断言写成 25、顶栏高度断言写成 55 时，当前代码仍是 20 和 52，测试应失败。改完对应组件后这些断言转为通过。阅读分页测试在改动前后都应通过。
