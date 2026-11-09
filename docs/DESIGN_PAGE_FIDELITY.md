# 相对 `docs/阅读助手_完整设计稿.html` 的逐页还原审计

基准：设计稿 **27 个 screen**（`screens[]` 注册表）+ 全局 **Lucide** 图标 + `AppColors` token。  
应用：**Flutter Material 3** + `lib/ui/components/design.dart` 结构组件 + **Material Icons**（非 Lucide）。

图例：**✅** 结构/交互基本对齐 · **⚠️** 有明显视觉或图标偏差 · **❌** 缺失或与设计冲突 · **➖** 设计有、产品刻意不做

---

## 全局（所有页面）

| 维度 | 设计稿 | 当前 App | 判定 |
|------|--------|----------|------|
| 图标体系 | Lucide（如 `List`/`RefreshCw`/`ChevronLeft`） | `Icons.*` Material 线性图标 | ⚠️ **全站未像素级还原** |
| 主色 / 背景 | `#2878F0` / `#F3F4F6` 等 | `lib/ui/theme.dart` 已按稿抄写 | ✅ |
| 底部导航 | 书架 / 发现 / 我的 + 选中蓝点 | 三项 + 自绘 tab（`Icons.auto_stories`/`explore`/`person`） | ⚠️ 图标非 Lucide；交互对齐 |
| 顶栏 | `.app-topbar` 圆钮 + 居中标题 | 各页混用 `LargeTitle` / `AppTopBar` | ⚠️ 部分页仍用 `AppBar` 默认样式 |
| 状态栏壳 | 设计含假 `.statusbar` | 系统状态栏 | ➖ 故意不做 |

---

## 逐页对照

### 日常入口（home）

| ID | 设计标题 | App 入口 | 布局/结构 | 图标 | 备注 |
|----|----------|----------|-----------|------|------|
| `shelf` | 书架 | `bookshelf_screen.dart` | ✅ | ⚠️ | 大标题、筛选、继续读、三列网格、添加卡、整理模式已有；**分组封面 2×2 拼贴**与稿需肉眼再对间距 |
| `shelfGroups` | 分组书架 | 书架内分组路由 | ✅ | ⚠️ | 组内网格、返回、更多菜单；页脚「N 本书 · 组名」有 |
| `shelfOrganize` | 批量分组 | 书架「选择」模式 | ✅ | ⚠️ | 全选/移出/分组到；底部批量条样式接近稿 |
| `discover` | 发现 | `discover_screen.dart` | ✅ | ⚠️ | 搜索、最近搜索、浏览书源、能力标签；**管理发现来源**为圆钮 |
| `profile` | 我的 | `profile_screen.dart` | ✅ | ⚠️ | 统计卡、笔记/记录、内容与数据区；头像区文案与稿「阅读者」演示不同（产品名「阅读」） |

### 阅读链路（reading）

| ID | 设计标题 | App 入口 | 布局/结构 | 图标 | 备注 |
|----|----------|----------|-----------|------|------|
| `search` | 搜索 | `search_screen.dart` | ⚠️ | ⚠️ | 范围/精确/聚合/进度已有；**目录式结果行**与稿的封面比例、标签密度需再对 |
| `detail` | 书籍详情 | `book_details.dart` | ⚠️ | ⚠️ | 封面头图+指标+导读+双按钮有；**在线书操作**收进更多，与稿一致；部分 metrics 文案非演示数据 |
| `reader` | 沉浸阅读 | `reader_screen` 沉浸态 | ⚠️ | ⚠️ | 曾去 AppBar 改浮层；**顶 `reader-head`、底 `进度%·页/总页` 右对齐**已修；**分页 inset** 已补；与稿比：head 左为章名非书名 |
| `readerTools` | 阅读工具 | `reader_screen` 工具态 | ⚠️ | ⚠️ | `reader-tool-top` + `reader-bottom` 叠层有；底栏四工具语义已对，**仍是 Material 图标** |
| `changeSource` | 换源 | `source_switch_sheet.dart` | ⚠️ | ⚠️ | 书上下文、筛选、进度、字数排序有；**停止/刷新/选项**图标与稿 Lucide 不一致 |
| `toc` | 目录与书签 | `reader_toc_sheet.dart` | ⚠️ | ⚠️ | 封面块+搜索+双 tab+当前章有；章节行用 `ListTile`，非稿中 `.chapter-row` 双列序号样式 |
| `readingSettings` | 阅读设置 | `reader_preferences.dart` + 阅读内 sheet | ⚠️ | ⚠️ | 六行排版有；**App 在面板内还含自动翻页/朗读/标注等**，设计稿「设置」仅六行 |
| `night` | 夜间阅读 | `ReaderTheme.dark` | ✅ | ⚠️ | `#202225` / `#C3C0B8`；层级同阅读页 |
| `selection` | 划线与想法 | 划词条 `reader-selection-bar` | ⚠️ | ⚠️ | 已改深色四动作条；**无设计稿「笔记 sheet」同屏叠层**的完整形态 |
| `reader-more`（稿内 sheet） | 阅读工具列表 | `_showReaderMoreSheet` | ⚠️ | ⚠️ | 已有列表 sheet；**未含稿内「查看加载失败状态」**；离线/换源项视书源类型显示 |

### 阅读与积累（companion）

| ID | 设计标题 | App 入口 | 布局/结构 | 图标 | 备注 |
|----|----------|----------|-----------|------|------|
| `assistant` | 阅读助手 | `reading_assistant_sheet.dart` | ✅ | ⚠️ | 本地回顾+声明；无模型 |
| `audio` | 听书 | `audio_screen.dart` | ⚠️ | ⚠️ | 基础 TTS 页有；**睡眠定时/15s 进退**设计标注本版弱化 |
| `notes` | 读书笔记 | `notes_screen.dart` | ⚠️ | ⚠️ | 搜索+卡片+导出；卡片发丝线与稿需对 |
| `stats` | 阅读记录 | `reading_history_screen.dart` | ⚠️ | ⚠️ | 周切换+柱状+三项统计；**演示数据 vs 真实活动**混合展示 |

### 内容与数据（manage）

| ID | 设计标题 | App 入口 | 布局/结构 | 图标 | 备注 |
|----|----------|----------|-----------|------|------|
| `import` | 导入书籍 | `import_screen.dart` | ⚠️ | ⚠️ | 三选项卡有；EPUB 流程展示、非完整引擎（与稿一致声明） |
| `sources` | 书源管理 | `sources_screen.dart` | ⚠️ | ⚠️ | 功能多于稿（批量/编辑）；**视觉密度**高于稿示例 |
| `appSettings` | 通用设置 | `app_settings_screen.dart` | ⚠️ | ⚠️ | 分区列表有；阅读排版跳转阅读设置 |
| `backup` | 备份与同步 | `backup_screen.dart` | ⚠️ | ⚠️ | 本机备份有；**WebDAV 如实标注未接入**（与稿「演示配置」一致） |

### 开始与结束（states）

| ID | 设计标题 | App 入口 | 布局/结构 | 图标 | 备注 |
|----|----------|----------|-----------|------|------|
| `welcome` | 首次打开 | `welcome_screen.dart` | ⚠️ | ⚠️ | 有欢迎流；产品名「阅读」非稿「阅见」 |
| `empty` | 空书架 | 书架空态 | ✅ | ⚠️ | 引导导入/找书 |
| `noSources` | 尚未添加书源 | 发现空态 | ✅ | ⚠️ | 有 |
| `loadError` | 内容加载失败 | `reader_screen` 错误区 | ⚠️ | ⚠️ | 重试/换源有；**非独立全屏态**，与设计独立屏略异 |
| `finish` | 读完一本书 | `finish_screen.dart` | ⚠️ | ⚠️ | 有读完页；统计数字部分为演示/估算 |

---

## 图标对照（阅读核心 · 用户高频反馈）

| 位置 | 设计稿 Lucide | 当前 Material | 判定 |
|------|---------------|---------------|------|
| 底栏·目录 | `List` | `Icons.list` | ⚠️ 形体接近，非同一套 |
| 底栏·换源 | `RefreshCw` | `Icons.refresh` | ⚠️ |
| 底栏·笔记 | `NotebookPen` | `Icons.edit_note_outlined` | ⚠️ |
| 底栏·设置 | `Type` | `Icons.title` | ⚠️ |
| 顶栏·返回 | `ChevronLeft` | `CircleIconButton` + `chevron_left` | ⚠️ 结构已对 |
| 顶栏·书签 | `Bookmark` | `bookmark_outlined` | ⚠️ |
| 顶栏·更多 | `Ellipsis` | `more_horiz` | ⚠️ |
| 划词条 | `Highlighter` 等 | 纯文字四按钮 | ⚠️ 已改深色条，**无 Lucide 图标** |
| Tab·书架 | 稿为书本类 | `auto_stories_outlined` | ⚠️ |
| Tab·发现 | `Compass` | `explore_outlined` | ⚠️ |
| Tab·我的 | 用户轮廓 | `person_outline` | ⚠️ |

**结论：图标层面目前没有任何一页达到设计稿 Lucide 像素级还原**；结构还原度高于图标。

---

## 汇总

| 类别 | 数量（约） |
|------|------------|
| ✅ 结构基本对齐 | 8 |
| ⚠️ 部分对齐（含图标/密度/子状态） | 18 |
| ❌ 明显缺失 | 0（核心屏均在代码中） |
| ➖ 刻意不做 | 假状态栏等 |

**最大系统性差距**

1. **全站 Material Icons ≠ Lucide**（影响用户说的「图标不一样」）。  
2. **阅读设置**：设计单面板六行 vs App 合并辅助能力列表。  
3. **阅读页**：近期改为浮层头/底后曾出现排版重叠，**已通过 `\_readerContentInsets` 修复**，需重装 APK 验收。  
4. **`fp-docs/settings/frontend.md` 仍写旧色 `#2468DE`**，与 `theme.dart` 不一致（文档滞后，非 UI 回退）。

---

## 建议修复顺序（若继续落地）

1. **P0 阅读页**：MuMu 复验沉浸/工具/更多/设置；确认分页与页脚无重叠。  
2. **P1 图标**：`lib/ui/design_icons.dart` + `lucide_icons_flutter`；已覆盖 Tab、阅读顶栏/底栏四工具、「阅读工具」sheet 主行。
3. **P2 阅读设置**：底栏「设置」仅 `ReaderPreferences` 六行；自动翻页/朗读/标注等在「阅读工具」→「辅助能力」。
4. **P3 其余屏**：搜索/详情/目录/换源行的间距与封面比例按稿走查表逐项改。  
5. **文档**：同步 `frontend.md` token 与 `PROGRESS.md` 阅读页描述（页脚、更多菜单形态）。

验证：MuMu 27 屏走查截图集 + `flutter analyze` + 关键 widget 测试（本机 tester 可用时）。
