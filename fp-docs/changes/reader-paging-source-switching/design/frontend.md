# 阅读分页与书源切换能力 — 技术方案设计

本设计在现有 Flutter 客户端内增加左右分页、一步导入和多书源管理能力。主线是复用现有段落锚点、书源搜索调度器、安全网络层和 Sembast 仓储，只新增当前验收需要的纯布局、切源映射、字节响应和正文整理边界。

## 第一部分：架构决策

### Decision Ledger

| ID | Decision | Source | Blocking | Status | Evidence / explicit confirmation |
| --- | --- | --- | --- | --- | --- |
| D-001 | 只生成 frontend end，领域、服务、仓储和 UI 都属于同一 Flutter app | `fp-docs/settings/frontend.md:7-12` | yes | `code-verified` | D-001: 当前仓库是单一 Flutter 客户端，无生产后端 |
| D-002 | 视觉来源使用用户提供的截图原图和现有页面 | `proposal.md` P-005；用户附图 | yes | `user-confirmed` | D-002: selected 截图原图；user message 要求纸张颜色参考所附微信读书截图 |
| D-003 | 采用现有分层内的安全增量方案，不做 UI 捷径或 Legado 架构移植 | 用户 auto 授权；`engineering-quality.md:49-55` | yes | `user-confirmed` | D-003: selected 安全增量方案；user message 为“用你的最佳实践完成，不要询问我” |
| D-004 | 阅读支持 `paged` 和 `scrolling`，默认 `paged`，两种模式都保存段落锚点 | `proposal.md` P-001/P-003；`code-standards.md` P004 | yes | `user-confirmed` | D-004: selected 双模式和段落锚点；user message 授权最佳实践决策 |
| D-005 | 纸张背景使用 `#F4EFDC`，正文墨色保留 `#34332F` | 用户原图；`reader_screen.dart:235-241` | yes | `code-verified` | D-005: 原图多点像素采样均为 RGB `(244, 239, 220)`；现有正文墨色为 `#34332F` |
| D-006 | 导入按钮在一次操作内依次 prepare 和 commit，不展示预览或逐源选择 | `proposal.md` P-004 | yes | `user-confirmed` | D-006: selected 一步确认导入；user message 明确要求不要预览 |
| D-007 | 候选源复用并发搜索，规范化书名精确筛选、作者相同优先、排除当前来源 | `app_controller.dart:212-262`；用户 auto 授权 | yes | `user-confirmed` | D-007: selected 有界候选匹配；user message 授权最佳实践决策 |
| D-008 | 切源先完整加载目标，再事务更新书籍与笔记；迟到旧缓存按来源和章节身份拒绝 | `code-standards.md` P001/P002/P004；用户 auto 授权 | yes | `user-confirmed` | D-008: selected 事务切源与竞态保护；user message 授权最佳实践决策 |
| D-009 | 封面经安全 transport 的字节模式获取，验证同源、私网、跳转、大小和 `image/*` | `source_transport.dart:66-287`；`source_engine.dart:484-495` | yes | `user-confirmed` | D-009: selected 安全字节路径；user message 授权最佳实践决策 |
| D-010 | 正文使用确定性规范化和已有安全正则替换，不用广告关键词猜测删除 | `rule_interpreter.dart:473-492`；`source_engine.dart:250-307` | yes | `user-confirmed` | D-010: selected 安全整理；user message 授权最佳实践决策 |
| D-011 | 沿用 Sembast 现有 stores；新增设置字段用兼容默认值，不做 schema migration | `app_repository.dart:34-102`；`reader_settings.dart:24-41` | yes | `code-verified` | D-011: 数据以 JSON map 存储，旧记录可通过缺省值读取 |
| D-012 | 详情页新增次要“换源”和“刷新封面”，候选用响应式底部面板，无新路由 | `book_details.dart:27-131`；用户 auto 授权 | yes | `user-confirmed` | D-012: selected 现有详情页内操作；user message 授权最佳实践决策 |
| D-013 | 使用 small form：`design/frontend.md`，索引为 `design/00-index.md` | artifact-layout contract；写前路径检查 | yes | `code-verified` | D-013: 目标路径原先不存在，预计未超过 500 行或 30,000 字符，无转换或删除 |
| D-014 | 执行 format、analyze、全量 test、Web build 和真实浏览器视觉/交互检查 | `code-standards.md` P006；`frontend.md:46-52` | yes | `code-verified` | D-014: 项目已登记这些验证入口和本机 Flutter SDK/代理要求 |
| D-015 | 按已展示设计和 exact paths 写入并继续自动流程 | 用户本次会话授权 | yes | `user-confirmed` | D-015: selected 写入 `design/00-index.md` 与 `design/frontend.md`；user message 为“走 fp-start auto 模式，请你用你的最佳实践完成，不要询问我” |

### 关键决策说明

#### 现有分层内的安全增量方案

- **ID**：`D-003`
- **选择**：在现有 domain、application、data、services 和 ui 边界内增加小型专用对象。
- **理由**：UI 快捷方案无法保证分页精度、网络安全和持久化一致性；完整移植上游架构会引入没有当前证据支持的插件、缓存和兼容层。
- **来源**：当前代码、proposal 和用户 auto 授权。
- **状态**：`user-confirmed`
- **是否阻塞**：是。

#### 段落锚点驱动的真实分页

- **ID**：`D-004`
- **选择**：用 `TextPainter` 按视口测量并生成页面片段，页面只保存展示切片和首段锚点。
- **理由**：简单按字符数或一段一页会在长段、字号变化和不同视口下溢出。段落锚点能继续兼容阅读进度、书签和布局重算。
- **来源**：`reader_screen.dart:65-143` 和项目规则 P004。
- **状态**：`user-confirmed`
- **是否阻塞**：是。

#### 事务化切源与安全封面

- **ID**：`D-008`、`D-009`
- **选择**：目标详情、目录和当前映射章节先加载成功，再由一个 Sembast 事务替换书籍与笔记。封面通过现有 transport 读取字节，不走直接 `Image.network`。
- **理由**：切源涉及书籍、缓存、进度和笔记；直接网络图片会绕过私网、跳转和来源限制。
- **来源**：项目规则 P002/P003/P004 和当前 transport 实现。
- **状态**：`user-confirmed`
- **是否阻塞**：是。

### Pre-write Confirmation Evidence

- Covered IDs: `D-001`, `D-002`, `D-003`, `D-004`, `D-005`, `D-006`, `D-007`, `D-008`, `D-009`, `D-010`, `D-011`, `D-012`, `D-013`, `D-014`, `D-015`
- Outstanding blocking decisions: `none`
- Explicit user authorization to write: 用户在本次会话明确要求“走 fp-start auto 模式，请你用你的最佳实践完成，不要询问我”，授权按上述方案、small form、`design/00-index.md` 和 `design/frontend.md` 写入并继续；不授权提交、推送或合并。

## 第二部分：技术方案详述

### 设计范围适用性

| 评审范围 | 要求 | Canonical owner section | 证据或不适用理由 |
| --- | --- | --- | --- |
| 架构主线 | 必填 | `#架构主线` | proposal 与 D-003 |
| 核心对象与职责 | 必填 | `#核心对象与职责` | 当前 domain/application/data/services/ui 边界 |
| 数据模型 | 适用 | `#数据模型` | `ReaderSettings`、`Book`、`Bookmark` 和 Sembast map 会改变 |
| 状态、并发与执行流程 | 适用 | `#状态并发与执行流程` | 分页重算、候选搜索、切源和迟到下载有并发状态 |
| 接口、权限与兼容边界 | 适用 | `#接口权限与兼容边界` | 新控制器、引擎和仓储方法；沿用书源安全策略 |
| 前端方案 | 适用 | `#前端设计` | 阅读页、设置、导入、详情和封面组件改变 |
| 风险、迁移、发布、回滚与监控 | 必填 | `#风险迁移发布回滚与监控` | 视口分页、源匹配、缓存竞态和网络图片风险 |
| 验证方案 | 必填 | `#验证方案` | P006 和 frontend settings 已登记命令与视觉检查 |

### 架构主线

1. 阅读页根据 `ReaderSettings.flow` 选择纵向滚动或左右分页。分页器只计算布局，不写存储；页面变化仍通过 `AppController.savePosition` 保存章节和段落。
2. 书源导入界面把输入交给现有 `SourceImportService.prepare`。准备成功后立即提交全部来源，仓储事务完成后再关闭面板并刷新列表。
3. 详情页发起候选搜索。控制器复用 `SourceSearchScheduler(maxConcurrent: 4)` 搜索启用来源，过滤和排序后返回候选。
4. 用户选择候选后，控制器先让引擎加载目标详情和目录，再生成切源映射。仓储在一个事务中写入新书籍和映射后的笔记；成功后控制器发布新状态。
5. 正文加载沿用规则解释器。引擎聚合分页正文后调用纯 `ContentNormalizer`，缓存的仍是段落列表。
6. 封面 URL 仍由搜索或详情规则给出。图片字节通过安全 transport 获取，UI 加载失败时显示现有生成封面。

不新增第三方依赖、通用插件系统、后台任务或第二套状态管理。新增对象都对应分页测量、切源映射、安全字节读取或正文整理的当前需求。

### 核心对象与职责

| 对象/模块 | 职责 | 不负责 | 协作对象 | 证据 |
| --- | --- | --- | --- | --- |
| `ReaderPaginator` | 根据文本样式和视口生成不可变页面及段落锚点 | 不保存进度，不发网络请求 | `ReaderScreen`、`TextPainter` | D-004 |
| `PagedReader` | 展示页面、处理左右滑动和跨章哨兵 | 不决定持久化格式 | `ReaderScreen` | D-004 |
| `SourceSwitchMapper` | 规范化标题，映射章节、位置和笔记 | 不访问网络或数据库 | `Book`、`Bookmark` | D-007/D-008 |
| `ContentNormalizer` | 规范化空白、空段和重复标题 | 不按关键词猜测广告，不执行脚本 | `SourceEngine` | D-010 |
| `SourceEngine` | 搜索、详情/目录/正文、封面字节和安全网络编排 | 不直接发布应用状态 | transport、interpreter | 当前 `source_engine.dart` |
| `AppController` | 编排候选、切源、封面刷新和持久化后状态发布 | 不实现解析规则 | engine、repository | 当前 `app_controller.dart` |
| `AppRepository` | 事务保存书籍、笔记和设置 | 不进行候选匹配或网络加载 | Sembast stores | 当前 `app_repository.dart` |
| `BookCover` | 展示安全获取的图片，失败时回退生成封面 | 不直接请求任意 URL | controller loader | D-009 |
| `SourceSwitchSheet` | 展示候选和触发用户选择 | 不做匹配或持久化 | `BookDetails`、controller | D-012 |

### 数据模型

#### 接近实现的模型代码

```dart
enum ReaderFlow { paged, scrolling }

/// Persisted reading preferences with backward-compatible defaults.
class ReaderSettings {
  const ReaderSettings({
    this.theme = ReaderTheme.paper,
    this.flow = ReaderFlow.paged,
    this.fontSize = 22,
    this.lineHeight = 1.9,
  });

  final ReaderTheme theme;
  final ReaderFlow flow;
  final double fontSize;
  final double lineHeight;
}

/// Prepared replacement that preserves a shelf book's stable identity.
final class SourceSwitchPlan {
  const SourceSwitchPlan({required this.book, required this.bookmarks});

  final Book book;
  final List<Bookmark> bookmarks;
}
```

`Book` 新增语义明确的 `rebindSource`，保留 `id`、`addedAt`、`lastOpenedAt`、`finished` 和用户数据，只替换来源、详情、目录、封面与映射后位置。`Bookmark` 新增不可变 `copyWithPosition`。不把临时候选或封面字节写入领域对象。

#### 字段与存储取舍

| 字段/数据 | 候选表示 | 最终选择 | 数据体积与读取方式 | 选择理由 | 证据 |
| --- | --- | --- | --- | --- | --- |
| 阅读流模式 | 独立 store / settings 枚举名 | `meta/settings.flow` 字符串 | 启动读取一次，设置变更写一次 | 与现有主题、字号、行高同生命周期 | D-011 |
| 切源候选 | 持久化 / 内存结果 | 内存 `List<Book>` | 用户打开面板时按需搜索 | 候选易过期，无离线读取要求 | D-007 |
| 封面字节 | base64 入书籍 / 文件缓存 / 组件 Future | 组件生命周期内的字节 Future | 按可见封面请求，失败回退 | 避免放大 Sembast 记录和新增缓存生命周期 | D-009 |
| 正文整理结果 | 原始 HTML / 规则结果 / 段落列表 | 现有 `Chapter.paragraphs` | 章节首次下载后缓存 | 保持阅读、书签和离线路径不变 | D-010 |

#### 逻辑模型与物理存储

| 逻辑对象 | ORM/Schema 对象 | 物理表或存储 | 主键与关联键 | 证据 |
| --- | --- | --- | --- | --- |
| 阅读设置 | `ReaderSettings` JSON | Sembast `meta` store 的 `settings` record | 固定 key `settings` | `app_repository.dart:80-87` |
| 书籍 | `Book` JSON | Sembast `books` store | `Book.id` | `app_repository.dart:34-40` |
| 笔记/书签 | `Bookmark` JSON | Sembast `notes` store | `Bookmark.id`，关联 `bookId` | `app_repository.dart:90-102` |
| 书源 | `BookSource` JSON | Sembast `sources` store | `BookSource.id` | `app_repository.dart:109-176` |

#### 继承字段与重复存储结论

项目没有公共 ORM 基类、manager 或 mixin。`sourceLabel`、`sourceId` 和 `url` 继续存于书籍记录，分别服务离线展示、规则定位和远程详情；不另建来源关联表。封面字节不重复存储。

#### 索引、约束与软删除

Sembast 当前按 record key 访问书籍、书源和笔记。切源沿用 `bookId` 过滤相关笔记，不新增索引；本地数据量和既有查询模式没有证据要求新索引。项目没有软删除、审计或唯一约束层，删除行为保持不变。

#### 查询模式与索引映射

| 查询模式 | 过滤/排序/关联字段 | 对应索引或访问路径 | 选择理由 | 证据 |
| --- | --- | --- | --- | --- |
| 读取单本书 | `Book.id` | Sembast record key | 现有稳定主键路径 | `saveBook` / `book(id)` |
| 映射本书笔记 | `Bookmark.bookId` | 现有 Finder filter | 切源只在用户操作时执行一次 | `removeBook` 已使用相同过滤 |
| 搜索候选来源 | 启用来源、书名、作者 | 内存来源列表 + 并发搜索 | 结果来自外部来源，不能由本地索引替代 | `searchSources` |

#### 生命周期数据归属

候选、分页布局和封面字节属于临时 UI/控制器状态。已确认切源结果归 `books` 和 `notes`。导入来源及来源 provenance 继续归 `sources` 和 `source_state`。不新增发布、下线或调试记录。

#### Migration 影响

Sembast 使用无 schema 的 JSON map。旧 `settings` 没有 `flow` 时由 `ReaderSettings.fromJson` 返回 `ReaderFlow.paged`；无需 migration。`Book` 和 `Bookmark` 的持久化字段不新增，只改变一次事务中的值。回滚代码后，未知 `flow` 字段会被旧版本忽略。

#### 技术栈专项结论

项目不是 Django/ORM 应用。物理存储为 Sembast record stores；不生成 SQL migration、数据库索引或 Django 元数据。

### 状态、并发与执行流程

#### 阅读分页

1. `LayoutBuilder` 提供正文可用宽高。
2. 分页缓存 key 包含章节 ID、宽、高、字号、行高和主题排版参数。
3. key 变化时以当前段落锚点重新分页，找到包含该段落的页面并恢复。
4. `PageView.onPageChanged` 更新首段锚点，沿用 500 ms 延迟保存。
5. 首尾哨兵页只在存在相邻章节时出现；触发后先保存当前位置，再加载相邻章节。

#### 候选搜索与切源

1. 面板创建取消信号，调用 `findSourceCandidates(bookId)`。
2. 控制器复用 `searchSources(title)`，排除当前来源，保留规范化书名相同结果；作者相同优先，来源原顺序作为稳定次序。
3. 用户选中候选后锁定面板操作。引擎加载候选详情和目录。
4. `SourceSwitchMapper` 按规范化章节名映射当前章节和笔记；当前目标章节再加载一次正文，用规范化段落文本匹配当前段落，失败时约束原索引。
5. 仓储事务写入替换后的书籍及该书笔记。事务失败不改变控制器状态。
6. 成功后清除该书封面 Future 和旧章节加载引用，再发布书籍与笔记。

#### 迟到下载保护

`cacheChapter` 新增 `expectedSourceId` 和 `expectedChapterId`。事务内重新读取书籍，只有当前来源和目标章节身份都匹配时才写正文。切源前启动的旧请求即使较晚完成，也不能污染新目录。

#### 一步导入

按钮进入 busy 后创建取消信号，依次执行 `prepareSourceImport(input)` 和 `commitSourceImport(preview)`。只有两个步骤都成功才关闭面板。prepare 失败没有写入；commit 使用现有事务，不产生部分来源状态。

### 接口、权限与兼容边界

```dart
Future<List<Book>> findSourceCandidates(
  String bookId, {
  Future<void>? abortTrigger,
});

Future<Book> switchBookSource(String bookId, Book candidate);
Future<Book> refreshBookCover(String bookId);
Future<Uint8List?> loadBookCover(Book book);

Future<void> replaceBookSource(
  Book book,
  List<Bookmark> bookmarks,
);
```

`SourceEngine` 增加：

```dart
Future<Book> refreshBookInfo(BookSource source, Book book);
Future<Uint8List> loadCover(BookSource source, String coverUrl);
```

`SourceTransport.execute` 增加默认开启的 `decodeText` 参数。封面调用传 `false`，仍返回同一个含 `bytes` 的 `ResponseEnvelope`。文本调用行为不变。

所有书源请求继续要求无 userinfo 的 HTTP(S)、来源授权、私网拒绝、HTTPS 不降级、有限重定向和有限响应。封面只接受与书源同源的 URL 和 `image/*` 响应。Web 仍受 CORS 约束；CORS 失败显示生成封面，不引入代理。

### 前端设计

#### 页面/视图

- 阅读路由不变：`/read/<encoded-book-id>`。
- 书籍详情仍在现有详情面板中展示，不增加路由。
- 换源候选使用 `showModalBottomSheet`。窄屏占可用高度的大部分，宽屏内容最大宽度 600。
- 书源导入仍从“我的书源”打开现有 `SourceImportSheet`。

#### 组件

- 新建 `ReaderPaginator` 和 `PagedReader`；纵向布局提取为同文件私有构建方法或小组件，避免 `ReaderScreen` 继续膨胀。
- `ReaderPreferences` 使用 Material 3 `SegmentedButton<ReaderFlow>`。
- `SourceImportSheet` 删除 `_preview` 和 `_selectedSourceIds`，保留输入、busy、cancel 和 error 状态。
- 新建 `SourceSwitchSheet`，复用 `QuietPanel`、现有按钮和错误文案模式。
- `BookCover` 接收安全字节 loader，用 `FutureBuilder` 展示 `Image.memory`，失败保持原生成封面。

#### API 模块

项目没有独立 API 客户端层。UI 只调用 `AppController`；控制器调用 `SourceEngine` 和 `AppRepository`，不让组件直接访问 transport 或 database。

#### 路由

不新增路由或权限守卫。功能仅对已加入书架且具有 `sourceId` 的远程书籍显示；本地 TXT 和样例节选不显示换源或刷新来源操作。

#### 状态管理

全局持久化状态继续由 `AppController extends ChangeNotifier` 发布。候选搜索、选择、分页控制器和封面 Future 是组件局部状态。忙碌操作禁用重复点击，并在 dispose 时触发取消信号。

#### UI/UX Settings Source

- Settings read: `fp-docs/settings/frontend.md`、`fp-docs/settings/code-standards.md`
- Existing references: `lib/ui/screens/reader_screen.dart`、`lib/ui/components/reader_preferences.dart`、`lib/ui/components/source_import_sheet.dart`、`lib/ui/components/book_details.dart`、`lib/ui/components/book_cover.dart`
- Confirmed tokens/components: Flutter Material 3、`AppColors`、`QuietPanel`、现有中文字体 NotoSansSC、窄屏断点 650、内容最大宽度 600/760
- Confirmed UX rules: 持久化成功后发布状态；加载/空/错误/重试状态；窄屏不横向溢出；UI 改动做桌面和窄屏检查
- Unknowns requiring user confirmation: none

#### Visual Source

- 类型：截图原图
- 来源：`C:/Users/Lenovo/AppData/Local/Temp/claude/D--01-code-read-pilot/a36c177d-80ee-4d3c-bcc4-9908bc839fac/images/2.jpg`
- 可信边界：可确认暖奶油背景、近黑正文、同色工具栏、极淡分隔线、宽松行距和两字缩进。截图不能证明响应式尺寸、横向动画、加载/错误态和深色模式，这些由现有代码与项目 UI/UX 设置约束，并在本地 viewer 验证。

#### UI 组件树与 Figma 解析映射

| 设计区域/节点 | 目标 DOM/组件层级 | 项目组件 | 布局策略 | 关键 token/尺寸 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 暖纸阅读背景 | `Scaffold > body` | `ReaderScreen` | 全屏填充 | `#F4EFDC` | 工具栏与正文同底色 |
| 左右正文页 | `Expanded > PageView > SelectionArea` | `PagedReader` | 水平分页、页内垂直 Column | 正文最大宽度 760；窄屏左右 24 | 页面按真实视口测量 |
| 阅读模式选择 | 设置面板内分段按钮 | `ReaderPreferences` | `SegmentedButton` | Material 3 默认高度 | “左右翻页 / 上下滚动” |
| 一步导入 | 模式、输入、错误、主按钮 | `SourceImportSheet` | 单列、自适应宽度 | 现有 sheet padding 24 | 不出现预览列表 |
| 详情来源操作 | 封面、信息、次要操作、主按钮 | `BookDetails` | Row + Wrap | 现有 28 padding；按钮可换行 | 只对远程书显示 |
| 换源候选 | modal sheet 标题、状态、列表 | `SourceSwitchSheet` | 最大宽度 600 的 ListView | 紧凑列表、来源为辅助文字 | 有取消、空、错误和重试 |
| 网络封面 | `ClipRRect > FutureBuilder > Image.memory` | `BookCover` | `BoxFit.cover` | 保留 5 px 书脊圆角 | 失败回退生成封面 |

#### Visual Checks

- [ ] 纸张主题的 `Scaffold`、AppBar 和正文背景均为 `#F4EFDC`；来源：用户截图原图像素采样。
- [ ] 正文在 375 px 窄屏和桌面宽度都无横向溢出，左右 padding 分别沿用 24/48；来源：`frontend.md` 与现有 ReaderScreen。
- [ ] 左右滑动只翻一页，页面底部不截断字符；字号、行高或窗口变化后仍回到同一段落；来源：D-004。
- [ ] 阅读设置清楚显示“左右翻页 / 上下滚动”，选中态持久化；来源：项目 Material 3 与 D-004。
- [ ] 导入面板不出现来源预览或勾选列表，主按钮显示 busy，成功提示新增/更新数量；来源：P-004/D-006。
- [ ] 换源面板在加载、无候选、部分失败、失败和成功状态下都有可观察反馈；来源：项目 UI/UX 设置。
- [ ] 远程封面使用 `BoxFit.cover`，加载失败或 CORS 拒绝时仍显示完整生成封面；来源：D-009。
- [ ] 本地 TXT、样例节选和夜间主题不显示不适用操作且视觉不回退；来源：proposal Out of Scope 和现有代码。

### 风险、迁移、发布、回滚与监控

| 具体失败场景 | 影响 | 预防或处理 | 发布/回滚/监控安排 | 证据 |
| --- | --- | --- | --- | --- |
| TextPainter 与实际渲染高度不同 | 页面末行溢出或空白过多 | 相同 TextStyle/宽度测量；长段二分切分；widget 测试覆盖边界 | 先上线双模式；用户可切回 scrolling | D-004 |
| 不同来源章节命名差异过大 | 阅读位置或笔记落到错误章节 | 规范化精确匹配，失败回退邻近索引；用户手动触发且切换前展示来源 | 事务失败保留原书；测试映射样本 | D-008 |
| 旧章节下载晚于切源完成 | 新目录被旧正文污染 | repository 在事务内核对 `sourceId + chapterId` | 记录错误状态；回归测试模拟迟到写入 | D-008 |
| 封面重定向、私网或非图片响应 | 安全边界被绕过或 UI 失败 | 复用 transport policy，验证 `image/*`，失败回退生成封面 | 不持久化失败结果；Web CORS 单独报告 | D-009 |
| 通用清理误删正文 | 内容丢失 | 不做关键词广告删除，只做空白/空段/重复标题和书源安全替换 | 正文 fixture 对比；可回滚 normalizer 调用 | D-010 |
| 新设置字段被旧数据缺失 | 启动解析失败 | `fromJson` 缺省为 `paged`，未知枚举安全回退 | domain/repository 兼容测试 | D-011 |
| 一步导入 commit 失败 | 用户以为部分来源已导入 | 保留现有事务；只有 commit 成功才关闭并提示 | repository 测试故障注入 | D-006 |

有意延后项：无。自动后台换源、登录/WebView 和全量 Legado 兼容明确不在本次范围，不属于临时技术债。

### 验证方案

| 验证项 | 命令或操作 | 预期结果 | 覆盖的设计结论 | 证据 owner |
| --- | --- | --- | --- | --- |
| 分页与锚点单元测试 | `flutter test test/reader_paginator_test.dart` | 长段、字号、视口和首段映射通过 | D-004 | 本节 |
| 切源映射与正文整理 | `flutter test test/source_switch_mapper_test.dart test/content_normalizer_test.dart` | 标题映射、回退、空白和重复标题通过 | D-008/D-010 | 本节 |
| transport 字节模式 | `flutter test test/source_transport_test.dart` | 图片字节可返回；文本行为和安全拒绝不变 | D-009 | 本节 |
| controller/repository | `flutter test test/controller_test.dart test/repository_test.dart` | 持久化后发布、事务回滚、迟到缓存拒绝通过 | D-008/D-011 | 本节 |
| UI 回归 | `flutter test test/reader_recovery_test.dart test/sources_screen_test.dart test/app_widget_test.dart` | 阅读恢复、一步导入和现有应用流程通过 | D-004/D-006/D-012 | 本节 |
| 格式 | `dart format --output=none --set-exit-if-changed lib test` | 无格式差异 | P006 | 本节 |
| 静态分析 | `flutter analyze` | 0 error、0 warning | 全设计 | 本节 |
| 全量测试 | `flutter test` | 全部通过 | 全设计 | 本节 |
| Web 构建 | `flutter build web --release --no-web-resources-cdn` | release 构建成功 | 兼容边界 | 本节 |
| 视觉与交互 | 本地 preview：桌面与 375 px，执行 Visual Checks | 纸色、分页、导入、换源、封面回退均可观察符合 | D-002/D-005/D-012 | Visual Checks |
| 注释自审 | 对照本次 diff 检查公开对象与非显然约束 | 新增公开对象有职责说明，事务/竞态/安全原因注释准确 | engineering-quality | 本节 |
