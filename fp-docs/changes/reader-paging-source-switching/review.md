# 阅读分页与书源切换能力 — 开发设计评审

## 评审结论

建议通过。设计完整覆盖左右分页、一步导入、手动换源、封面刷新和正文整理，并把段落锚点、事务发布、迟到下载和安全网络边界放在同一主线中。实现阶段最需要关注分页测量与切源竞态，现有设计已经给出可测试的处理方式。

| 评审面 | 结论 | 设计依据 |
| --- | --- | --- |
| 决策 | 共 15 项；阻塞 15 / 非阻塞 0；全部终态 | `design/frontend.md#Decision-Ledger` |
| 数据 | 设置增加阅读流模式；切源事务更新现有书籍和笔记记录 | `design/frontend.md#数据模型` |
| 接口 | 控制器增加候选、切源和封面入口；transport 增加可选字节响应 | `design/frontend.md#接口权限与兼容边界` |
| 前端 | 阅读页双模式、详情换源面板、一步导入和安全封面回退 | `design/frontend.md#前端设计` |
| 不做事项 | 不复制上游 Kotlin，不扩展登录、远程脚本、代理或完整 Legado 兼容 | `../proposal.md#Out-of-Scope` |

## 业务和技术主线

阅读页根据持久化设置选择分页或滚动。分页器按当前视口和文本样式生成页面，但阅读进度仍保存章节索引与段落索引。字号、行高或窗口变化后，阅读器重新分页并恢复到同一段落。

书源导入保留现有准备、校验和事务提交，只把两步 UI 合并为一次用户操作。用户不再查看预览或逐源勾选；任何失败都在关闭面板前呈现。

换源从详情页发起。控制器复用现有有界并发搜索，筛选同名候选并由用户手动选择。目标详情、目录和当前映射章节加载成功后，仓储才在一个事务中更新书籍和笔记；事务成功后控制器发布新状态。

封面继续使用书源解析出的同源 URL，但图片字节也经过现有安全 transport。正文整理复用安全正则替换，再执行纯本地、确定性的空白和重复标题规范化。

这是满足当前验收的最小安全方案。它复用 `ChangeNotifier`、`SourceSearchScheduler`、`SourceTransport`、规则解释器和 Sembast stores，只新增真实分页、切源映射、字节读取和正文整理所需的专用对象，没有引入第三方依赖或第二套架构。

## 核心对象与职责

| 对象/模块 | 职责 | 不负责 | 协作对象 | 设计依据 |
| --- | --- | --- | --- | --- |
| `ReaderPaginator` | 按视口测量文本并生成段落锚点页面 | 不保存进度 | `PagedReader`、`TextPainter` | `design/frontend.md#核心对象与职责` |
| `PagedReader` | 展示页面、处理左右滑动和跨章 | 不决定持久化格式 | `ReaderScreen` | `design/frontend.md#状态并发与执行流程` |
| `SourceSwitchMapper` | 映射章节、位置和笔记 | 不访问网络或数据库 | `Book`、`Bookmark` | `design/frontend.md#核心对象与职责` |
| `ContentNormalizer` | 做确定性正文规范化 | 不猜测广告关键词 | `SourceEngine` | `design/frontend.md#核心对象与职责` |
| `SourceEngine` | 加载候选详情、目录、正文和封面字节 | 不发布应用状态 | transport、interpreter | `design/frontend.md#架构主线` |
| `AppController` | 编排候选、切源、封面和持久化后发布 | 不实现解析规则 | engine、repository | `design/frontend.md#接口权限与兼容边界` |
| `AppRepository` | 事务保存书籍、笔记和设置 | 不匹配候选 | Sembast stores | `design/frontend.md#数据模型` |
| `SourceSwitchSheet` | 展示候选状态并接收选择 | 不持久化 | `BookDetails`、controller | `design/frontend.md#前端设计` |

## 数据模型评审

### 接近实现的模型代码

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

### 物理存储、继承与重复存储

| 逻辑对象 | 物理表/存储 | 继承字段来源 | 主键与关联键 | 重复存储结论 |
| --- | --- | --- | --- | --- |
| 阅读设置 | Sembast `meta/settings` | 无 | 固定 key `settings` | `flow` 与现有设置同记录，无重复 store |
| 书籍 | Sembast `books` | 无 | `Book.id` | 来源字段继续服务离线展示和规则定位，不拆表 |
| 笔记 | Sembast `notes` | 无 | `Bookmark.id`、`bookId` | 只更新映射位置，不复制书籍字段 |
| 书源 | Sembast `sources` | 无 | `BookSource.id` | 不新增来源关联表 |

### 字段与存储取舍

| 字段或存储选择 | 最终方案 | 主要取舍 | 项目证据 |
| --- | --- | --- | --- |
| 阅读模式 | `meta/settings.flow` 枚举名 | 与主题同生命周期，旧记录可缺省 | `design/frontend.md#字段与存储取舍` |
| 候选来源 | 内存 `List<Book>` | 每次打开按需刷新，不维护过期数据 | `design/frontend.md#字段与存储取舍` |
| 封面字节 | 组件生命周期 Future | 避免放大数据库记录，不提供离线封面缓存 | `design/frontend.md#字段与存储取舍` |
| 整理后正文 | 现有 `Chapter.paragraphs` | 保持阅读、书签和离线数据结构 | `design/frontend.md#字段与存储取舍` |

### 查询模式与索引映射、约束与迁移

| 查询模式 | 过滤/排序/关联字段 | 索引或访问路径 | 设计依据 |
| --- | --- | --- | --- |
| 单书读取 | `Book.id` | Sembast record key | `design/frontend.md#查询模式与索引映射` |
| 本书笔记映射 | `Bookmark.bookId` | 现有 Finder filter | `design/frontend.md#查询模式与索引映射` |
| 候选搜索 | 启用来源、书名、作者 | 来源列表与并发外部搜索 | `design/frontend.md#查询模式与索引映射` |

项目没有唯一约束、审计或软删除层。Sembast JSON map 新增 `flow` 不需要 schema migration；旧代码会忽略未知字段，回滚不要求数据转换。

## 状态、并发和执行流程

阅读分页缓存由章节、视口、字号和行高组成的 key 控制。key 变化后用段落锚点重新定位，页面变化延迟保存。跨章哨兵先保存当前位置，再加载相邻章节。

候选搜索可取消且沿用最大并发 4。切源期间 UI 禁止重复选择；引擎先完成网络读取，仓储后执行单事务。任何网络或事务错误都保留原书、目录、缓存和笔记。

章节缓存写入增加预期 `sourceId + chapterId`。事务内重新读取书籍后再核对，阻止旧来源请求在切源完成后覆盖新目录。

## 接口、权限和旧入口隔离

| 接口/入口 | 主键或资源 | 权限 | 兼容或隔离边界 | 设计依据 |
| --- | --- | --- | --- | --- |
| `findSourceCandidates` | `bookId` | 本地用户操作 | 仅启用来源；排除当前来源 | `design/frontend.md#接口权限与兼容边界` |
| `switchBookSource` | `bookId` + candidate | 本地用户确认 | 仅远程书籍；成功后发布状态 | `design/frontend.md#状态并发与执行流程` |
| `refreshBookCover` | `bookId` | 本地用户操作 | 失败保留当前封面 | `design/frontend.md#接口权限与兼容边界` |
| `loadBookCover` | `sourceId` + same-origin URL | 现有 source policy | 私网、跨源、降级和非图片响应拒绝 | `design/frontend.md#接口权限与兼容边界` |
| `replaceBookSource` | `Book.id` | 本地仓储事务 | 同时写书籍和相关笔记 | `design/frontend.md#数据模型` |

现有路由、书源导入类型和文本 transport 默认行为保持不变。本地 TXT 和样例节选不显示来源操作。Web 继续遵守 CORS，不增加公共代理或安全绕过。

## 前端方案

阅读页保留现有路由和 AppBar。`PagedReader` 使用横向 `PageView`，`ReaderPreferences` 用 Material 3 分段按钮切换“左右翻页 / 上下滚动”。纸张背景统一为 `#F4EFDC`，正文墨色保留 `#34332F`。

书源导入面板保留三种输入模式、busy、取消和错误状态，删除 preview 与 selection 状态。详情页保留主阅读按钮，新增次要“换源”和“刷新封面”。候选使用最大宽度 600 的响应式底部面板。

视觉来源是用户原图。实现后必须检查背景颜色、真实分页、段落恢复、模式持久化、导入无预览、候选各状态和封面失败回退。完整检查点由 `design/frontend.md#Visual-Checks` 唯一持有。

## 主要风险、迁移、发布和验证

### 主要风险

| 具体失败场景 | 影响 | 预防或处理 | 设计依据 |
| --- | --- | --- | --- |
| 分页测量与实际渲染不一致 | 末行被截或空白过大 | 相同样式测量、长段二分、widget 边界测试 | `design/frontend.md#风险迁移发布回滚与监控` |
| 章节命名差异导致错误映射 | 位置或笔记落错章节 | 规范化精确匹配，失败回退邻近索引 | `design/frontend.md#风险迁移发布回滚与监控` |
| 旧下载迟到 | 新目录混入旧正文 | 事务核对来源和章节身份 | `design/frontend.md#风险迁移发布回滚与监控` |
| 封面指向私网、跳转或非图片 | 安全边界绕过或 UI 失败 | 安全 transport 与 `image/*` 校验，失败回退 | `design/frontend.md#风险迁移发布回滚与监控` |
| 正文清理误删内容 | 阅读内容丢失 | 不做关键词删除，只做确定性规范化 | `design/frontend.md#风险迁移发布回滚与监控` |
| 一步导入提交失败 | 用户误以为已导入 | 事务成功后才关闭和提示 | `design/frontend.md#风险迁移发布回滚与监控` |

有意延后项：无。自动后台换源、登录/WebView 和全量 Legado 兼容属于明确的不做事项，不是临时技术债。

### 迁移与发布

无需 schema 或数据 migration。发布时先由兼容读取测试证明旧设置可加载，再验证切源事务和 UI。代码回滚后，旧版本会忽略 `flow` 字段；书籍和笔记仍使用原有字段格式。

监控以本地可观察错误为主：分页恢复失败、候选搜索错误、切源事务错误、封面加载回退和导入错误都在对应 UI 显示，不增加遥测服务。

### 验证清单

- [ ] `flutter test test/reader_paginator_test.dart`：长段、视口和锚点分页通过；依据 `design/frontend.md#验证方案`。
- [ ] `flutter test test/source_switch_mapper_test.dart test/content_normalizer_test.dart`：章节/笔记映射和正文整理通过。
- [ ] `flutter test test/source_transport_test.dart`：字节响应与现有文本、安全行为通过。
- [ ] `flutter test test/controller_test.dart test/repository_test.dart`：事务回滚和迟到缓存拒绝通过。
- [ ] `flutter test test/reader_recovery_test.dart test/sources_screen_test.dart test/app_widget_test.dart`：阅读恢复、一步导入和 UI 回归通过。
- [ ] `dart format --output=none --set-exit-if-changed lib test`、`flutter analyze`、`flutter test`：格式、静态分析和全量测试通过。
- [ ] `flutter build web --release --no-web-resources-cdn`：Web release 构建通过。
- [ ] 本地 preview 在桌面和 375 px 完成 `design/frontend.md#Visual-Checks`，没有控制台和网络错误。
- [ ] 对照实际 diff 完成公开对象契约说明、事务/竞态/安全原因注释和复杂度自审。

## 评审顺序与抽查路径

1. 先评审切源事务、章节映射与迟到下载保护，因为它们直接决定书籍、进度和笔记一致性；见 `design/frontend.md#状态并发与执行流程`。
2. 再评审分页器和段落锚点，因为视口变化会影响恢复位置；见 `design/frontend.md#阅读分页`。
3. 然后评审安全封面与正文整理，确认没有绕过来源策略或误删内容；见 `design/frontend.md#接口权限与兼容边界`。
4. 最后按 Visual Checks 评审阅读、导入和详情交互；见 `design/frontend.md#前端设计`。

- 建议抽查：`lib/ui/screens/reader_screen.dart:65`
- 建议抽查：`lib/application/app_controller.dart:132`
- 建议抽查：`lib/data/app_repository.dart:39`
- 建议抽查：`lib/services/source_engine.dart:250`
- 建议抽查：`lib/services/source_runtime/source_transport.dart:66`

## 评审结论记录

- [x] 通过：设计完整，可以进入计划阶段。
- [ ] 有条件通过：无。
- [ ] 退回修改：无。

## 设计入口

- `design/00-index.md`
