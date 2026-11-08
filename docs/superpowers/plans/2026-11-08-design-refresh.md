# 「阅读」按完整设计稿重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` inline. Steps use checkbox syntax for tracking.

**Goal:** 按 `docs/阅读助手_完整设计稿.html` 的 27 个页面与状态重排 `lib/ui/`，把入口收敛为「书架 / 发现 / 我的」三项，对齐设计 token，并补齐设计稿里尚未实现的信息结构（筛选行、添加卡、统计卡、列表行、阅读页头部与工具底栏、本地回顾助手）。

**Architecture:** 现有 `AppController` + `AppRepository` + `SourceEngine` 三层不动。UI 层新增一层“设计系统组件”（`lib/ui/components/design.dart`），把设计稿反复出现的结构（顶栏、分区标题、列表行、圆角按钮、搜索胶囊、卡片、空状态）收敛为可复用 widget；各屏幕改为组合这些组件，不再各自手写 padding/字号。业务逻辑（导入、书源、搜索、缓存、分页、恢复）不重写。

**Tech Stack:** Flutter 3.47.8 / Dart 3.13.7、Material 3、`flutter_localizations`、sembast（既有）。

## Global Constraints

- 只改 `lib/ui/`、`lib/main.dart`、`lib/app.dart` 与对应测试；`lib/domain/`、`lib/data/`、`lib/services/`、`lib/application/` 的公开行为不变。
- 不新增依赖；不引入代码生成或主题插件。
- 设计稿的 `.statusbar` / `.homebar` 是原型外壳，不进入应用。
- 保留 P004（位置是章节+段落锚点）、P002（写成功后才发布状态）语义，重构不得改变它们的行为。
- 保留 P006 门禁：`dart format --output=none --set-exit-if-changed lib test`、`flutter analyze --no-pub`、`flutter test --no-pub`。
- 每次提交前清理 `.tmp-design/`、`.tmp-shots/` 等临时目录。
- 文案用中文；不使用设计稿里的“阅见”作为产品名（产品名仍是“阅读”，P005）。

---

### Task 1: 设计 token 与设计系统组件

**Files:**
- Modify: `lib/ui/theme.dart`
- Create: `lib/ui/components/design.dart`
- Modify: `test/brand_identity_test.dart`（若断言了旧色值）

**Interfaces:**
```dart
class AppColors {
  static const ink = Color(0xFF23262C);
  static const muted = Color(0xFF858B96);
  static const blue = Color(0xFF2878F0);
  static const background = Color(0xFFF3F4F6);
  static const line = Color(0xFFEDF0F3);
  static const softBlue = Color(0xFFEDF4FF);
  static const paper = Color(0xFFF6F3EC);
  static const night = Color(0xFF202225);
  static const green = Color(0xFF4A8B74);
}

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, this.onBack, this.title = '', this.actions = const []});
  final VoidCallback? onBack;
  final String title;
  final List<Widget> actions;
}

class LargeTitle extends StatelessWidget {
  const LargeTitle({super.key, required this.title, this.trailing = const []});
  final String title;
  final List<Widget> trailing;
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
}

class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.onTap,
    this.trailing,
  });
}

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({super.key, required this.icon, required this.onPressed, required this.tooltip, this.selected = false});
}

class SearchPill extends StatelessWidget {
  const SearchPill({
    super.key,
    required this.hintText,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.trailing,
  });
}

class SwitchDot extends StatelessWidget {   // 设计稿 .switch：44x26 圆角胶囊 + 白色圆钮
  const SwitchDot({super.key, required this.value, required this.onChanged, required this.semanticLabel});
}

class InfoNote extends StatelessWidget {
  const InfoNote(this.lines, {super.key});
  final List<String> lines;
}

class EmptyBlock extends StatelessWidget {  // 设计稿 .empty-state：圆形图标底 + 标题 + 说明 + 主按钮 + 次链接
  const EmptyBlock({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });
}
```

- [ ] 1.1 改写 `AppColors` 为设计稿色板，新增 `paper`/`night`/`green`；`appTheme()` 同步字号（`headlineLarge` 28）、圆角（输入框 12、按钮 10）、`navigationBarTheme` 改为自定义（高度 56、无 indicator，选中蓝字）。
- [ ] 1.2 新增 `design.dart`，实现上列 9 个组件；所有组件只用 `AppColors` 与 `appTheme` 的字号，不硬编码色值。
- [ ] 1.3 运行 `flutter analyze --no-pub`，确认新组件无告警。

### Task 2: 壳层三 tab + 我的页

**Files:**
- Modify: `lib/ui/app_shell.dart`
- Modify: `lib/ui/screens/profile_screen.dart`
- Modify: `lib/ui/screens/bookshelf_screen.dart`（仅 `onSources` 回调链路调整）

**Interfaces:**
```dart
// AppShell 新增：
void _openSources();                  // push SourcesScreen
static const _labels = ['书架', '发现', '我的'];
```
- [ ] 2.1 `AppShell._labels`/`_icons`/`IndexedStack` 收为三项；`SourcesScreen` 从 tab 改为 `Navigator.push`，`DiscoverScreen.onSources` 与 `ProfileScreen.onSources` 都走它。
- [ ] 2.2 底部导航改为设计稿 `.tabbar`：白底、三项等高、选中项蓝字 + 图标下 3px 小圆点，高度 56 + 底部安全区。
- [ ] 2.3 宽屏侧栏保留三项 + 「书源管理」作为侧栏底部入口；侧栏品牌区保留 `BrandMark` 与「阅读」。
- [ ] 2.4 `ProfileScreen` 按设计稿重写：`profile-header`（圆形头像“阅” + 昵称「阅读者」+ 签名「给生活留一页空白」+ 齿轮）+ 统计卡（累计阅读 / 读完的书 / 读书笔记）+ 列表行（读书笔记、阅读记录）+ `内容与数据`（导入书籍、书源管理、备份与同步）+ `偏好`（通用设置）+ 引言。
- [ ] 2.5 统计卡数值取自 `controller`：累计阅读由 `readingActivities` 时长求和（无时长时显示阅读本数），读完的书 = `books.where((b) => b.finished)`，读书笔记 = `bookmarks.length`。
- [ ] 2.6 新建 `lib/ui/screens/app_settings_screen.dart`：`阅读`（阅读排版、正文净化开关、阅读助手开关）、`内容与下载`（书源管理、仅 Wi-Fi 下载、离线内容）、`数据与应用`（备份与同步、关于、开源许可）。
- [ ] 2.7 运行目标测试 `test/app_widget_test.dart`，修掉「四个 tab」「我的阅读」等旧断言。

### Task 3: 书架按稿补齐

**Files:**
- Modify: `lib/ui/screens/bookshelf_screen.dart`
- Modify: `test/bookshelf_layout_test.dart`、`test/bookshelf_groups_test.dart`

**Interfaces:**
```dart
// 新增 key：
Key('shelf-status-filter')   // 「全部状态 ∨」
Key('shelf-select')          // 「选择」
Key('shelf-add-card')        // 网格末尾添加卡
Key('shelf-group-add-books') // 组内添加书籍卡
```
- [ ] 3.1 标题行改 `LargeTitle('书架')` + 搜索/添加两个 `CircleIconButton`；删除「调参」图标按钮的独立入口，管理分组改由长按卡片或 `添加` 面板进入。
- [ ] 3.2 标题下方加筛选行：`全部状态 ∨`（弹层：全部状态 / 在读 / 已读 / 未读）+ `N 本书` + `选择`。
- [ ] 3.3 `选择`进入整理模式：顶栏「整理书架 / 完成」、`已选 N 本`、`全选`、底部「移出书架 / 分组到」；实现多选与分组到（复用 `setShelfGroupMembership`）。
- [ ] 3.4 网格末尾加「添加书籍 / 导入 · 搜索」虚线卡（点击弹出导入/搜索菜单）。
- [ ] 3.5 组内层加「添加书籍 / 从书架选择」卡与页脚 `N 本书 · 组名`；组内顶栏用 `AppTopBar(onBack, title: 组名, actions: [更多])`，更多菜单含重命名/调整顺序/解散。
- [ ] 3.6 页脚文案改「长按书籍或分组，即可整理书架」。
- [ ] 3.7 更新两个书架测试：新的 key、添加卡、筛选行、整理模式。

### Task 4: 发现页按稿重排

**Files:**
- Modify: `lib/ui/screens/discover_screen.dart`
- Modify: `test/discover_screen_test.dart`

**Interfaces:**
```dart
Key('discover-search-field')   // SearchPill 内 TextField
Key('discover-search-submit')  // 右侧蓝色「搜索」
Key('discover-source-${id}')   // 书源行
Key('discover-add-source')
```
- [ ] 4.1 顶部 `LargeTitle('发现')` + 右侧「管理发现来源」圆形按钮。
- [ ] 4.2 搜索区：`SearchPill` + 右侧蓝色「搜索」按钮（合计 40 高），下方提示「搜索书架与已启用的书源」；提交后进入搜索页（复用现有 `discover_search_sheet` 的检索能力，改为整页 `SearchScreen`）。
- [ ] 4.3 `最近搜索` 区块：`SectionLabel` + `清空`，chips 横排；无历史时不渲染。
- [ ] 4.4 `浏览书源` 区块：`N 个已启用` 计数 + 书源行（图标、名称、`分类`/`仅搜索` 能力标签、描述）+ `添加书源` 按钮 + 说明两行。
- [ ] 4.5 无书源时显示 `EmptyBlock`（`添加书源，发现更多书` + 主按钮 `添加书源` + 次链接 `导入本地书籍`）。
- [ ] 4.6 保留现有浏览模式（分类页）与内容模式跳转链路，仅替换外观。
- [ ] 4.7 更新 `test/discover_screen_test.dart`。

### Task 5: 搜索页与详情页

**Files:**
- Create: `lib/ui/screens/search_screen.dart`
- Modify: `lib/ui/components/book_details.dart`
- Create/Modify: `test/search_screen_test.dart`、`test/book_details_test.dart`

**Interfaces:**
```dart
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.controller, required this.onOpen});
  final AppController controller;
  final void Function(Book book) onOpen;
}
```
- [ ] 5.1 `SearchScreen`：顶栏（返回 / 搜索 / 选择范围）+ 固定搜索区（胶囊 + 蓝色「搜索」）+ 条件行（`全部书源` 范围触发 + `精确搜索` 复选）+ 主体（历史列表 / 空态 / 结果列表）。
- [ ] 5.2 结果行按设计稿 `book-row`：封面、书名、作者、`N 个来源` 标签、最新章节。
- [ ] 5.3 详情页按稿重排：`detail-hero`（封面 + 书名 + 作者 + 类型 + 来源标签）+ 三项指标（章节数 / 阅读进度 / 正文状态）+ 助手入口 + `关于这本书` 简介 + 目录行 + 笔记行 + 来源说明；底部固定「已在书架 / 继续阅读」双按钮，更多菜单收起换源与离线。
- [ ] 5.4 新增测试；更新 `book_details_test.dart` 的旧断言。

### Task 6: 阅读页、目录、阅读设置、换源面板

**Files:**
- Modify: `lib/ui/screens/reader_screen.dart`
- Modify: `lib/ui/components/reader_toc_sheet.dart`、`reader_preferences.dart`、`source_switch_sheet.dart`、`reader_mark_sheet.dart`
- Modify: `test/reader_*_test.dart`

**Interfaces:**
```dart
Key('reader-head-title')、Key('reader-head-chapter')
Key('reader-footer-chapter')、Key('reader-footer-progress')
Key('reader-tool-toc')、Key('reader-tool-source')、Key('reader-tool-notes')、Key('reader-tool-settings')
```
- [ ] 6.1 阅读页视觉层改为 `reader-head` + `reader-paper` + `reader-footer`；正文首段不缩进、段间距按行距；夜间 `#202225` / 正文 `#C3C0B8`。
- [ ] 6.2 工具顶栏（返回/书签/更多）与工具底栏（进度条 + 上一章/下一章 + 目录/换源/笔记/设置四项）按稿实现；保留现有分页、缓存、恢复、朗读行为。
- [ ] 6.3 目录面板按稿：简介块 + 章节搜索 + `目录/书签` tab + `当前章节` 跳回 + 序号章节行 + 当前章高亮。
- [ ] 6.4 阅读设置按稿六行：亮度/字号/字体/行距/背景/翻页；背景四色（纸白/米色/护眼/夜间）映射到现有 `ReaderTheme`。
- [ ] 6.5 换源面板按稿加：书上下文块、`当前来源` 行、筛选胶囊、`全部书源` 范围、`N 个候选来源`、排序说明、进度行、列表、页脚声明。
- [ ] 6.6 更新阅读相关测试（`reader_recovery_test`、`reader_settings_test`、`reader_toc_sheet_test`、`source_switch_sheet_test`）。

### Task 7: 辅助页面

**Files:**
- Modify: `lib/ui/screens/notes_screen.dart`、`lib/ui/screens/reading_history_screen.dart`、`lib/ui/screens/sources_screen.dart`
- Create: `lib/ui/screens/import_screen.dart`、`lib/ui/screens/backup_screen.dart`
- Modify: `lib/ui/components/local_backup_panel.dart`

**Interfaces:**
```dart
class ImportScreen extends StatelessWidget {  // 「从本机选择文件 / 先试读一本 / 添加在线书源」
  const ImportScreen({super.key, required this.controller, required this.onPickFiles});
}
class BackupScreen extends StatelessWidget {  // 「立即备份 / 从备份恢复 / WebDAV（未接入）」
  const BackupScreen({super.key, required this.controller});
}
```
- [ ] 7.1 读书笔记页按稿：搜索胶囊 + `N 条笔记` + 卡片（书名/时间/引文/想法/章节跳转/删除）+ 导出。
- [ ] 7.2 阅读记录页按稿：本周/上周分段 + 时长大数 + 七天柱状图 + 三项统计 + 引言 + 最近在读。
- [ ] 7.3 导入页与备份页新建；`我的` 与空态里的入口都指向它们。
- [ ] 7.4 书源管理页保留全部能力，行样式改 `source-item`（图标/名称/状态点/开关），顶部摘要卡 + `校验` + `添加书源` + 通知条。
- [ ] 7.5 `local_backup_panel.dart` 收敛为本机备份一块，供 `BackupScreen` 复用。

### Task 8: 阅读助手（本地回顾）

**Files:**
- Create: `lib/ui/components/reading_assistant_sheet.dart`
- Modify: `lib/ui/screens/reader_screen.dart`（划线「解释」入口）、`lib/ui/components/book_details.dart`（导读入口）

**Interfaces:**
```dart
class ReadingAssistantSheet extends StatelessWidget {
  const ReadingAssistantSheet({
    super.key,
    required this.book,
    required this.chapterTitle,
    required this.paragraph,
    required this.readChapters,
    required this.notes,
  });
}
```
- [ ] 8.1 面板结构按稿：头部（符号 + 阅读助手 + 副标题 + 关闭）、上下文 chip、问题、回答、引用 chip、操作行、建议、输入栏、声明。
- [ ] 8.2 回答由本机数据生成：选中段落原文、所在章节、已读章节数、该书笔记条目；不虚构作者生平或书中没有的内容。
- [ ] 8.3 声明固定为「本地回顾 · 不连接模型」；引用 chip 点击回到该段落。
- [ ] 8.4 新增 `test/reading_assistant_test.dart`：断言引用章节名、声明文案、笔记条数。

### Task 9: 门禁、真机走查与交付

- [ ] 9.1 `dart format lib test` 后跑三项门禁；测试数不得低于 640。
- [ ] 9.2 `flutter build apk --release`，`adb install -r` 到 MuMu，逐屏截图走查 27 个页面对应界面。
- [ ] 9.3 清理 `.tmp-design/`、`.tmp-shots/`；更新 `docs/PROGRESS.md` 与 `docs/LEGADO_MIGRATION_STATUS.md`（涉及书源/换源的部分）。
- [ ] 9.4 提交并 push `origin/feat/flutter-reader`；产出 beta10 APK 并交付。

## Completion record

（执行完成后回填）

## Self-review

（执行完成后回填）
