# FeaturePilot Project Code Standards

这些规则来自用户已确认的要求和多个当前实现/测试位置。2026-10-29，用户逐文件批准创建，并在 `frontend.md` 的 Project rule sources 登记。它们只约束现有应用，不引入新框架或功能。

## Rules

### P001 — 领域对象拥有自己的不可变数据

- Rule ID: P001
- Applies to: appRoot `.`，`lib/domain/` 及其 Dart 消费方，当前 Dart SDK 范围。
- Rule: 章节和书籍构造时隔离调用方可变集合；copyWith 的替换集合也必须隔离。书源的嵌套 JSON 输入与导出不能反向改变已校验对象。未改变的不可变集合可以复用，不为进度保存重复复制正文。
- Evidence: `lib/domain/book.dart` 的 Chapter/Book 构造和 Book.copyWith；`lib/domain/book_source.dart`；`test/domain_test.dart` 的集合和嵌套 JSON 隔离测试。对象会跨解析、缓存和 UI 共享，不能暴露可变别名。

### P002 — 持久化成功后才发布状态

- Rule ID: P002
- Applies to: appRoot `.`，`lib/application/`、`lib/data/` 和阅读 UI。
- Rule: 写入失败不得表现为已保存或已完成；阅读页保留重试或显式不保存退出路径。缓存章节与更新位置合并最新记录，不覆盖并发位置；删除后的迟到更新不复活书籍或来源。首次种子使用持久化标记，不因空书架重复灌入。
- Evidence: `lib/application/app_controller.dart` 的 savePosition、chapter 和 setSourceEnabled；`lib/data/app_repository.dart` 的事务、record.update 和种子标记；`test/repository_test.dart`、`test/controller_test.dart` 和 `test/reader_recovery_test.dart`。

### P003 — 书源是有界声明式协议

- Rule ID: P003
- Applies to: appRoot `.`，书源导入、HTTP/CSS 引擎、对应 UI 和测试。
- Rule: 只支持项目已声明的 Legado CSS 子集；不执行远程脚本，不静默接受不支持行为。模板展开后的首个请求、详情、目录、正文和每次跳转，在发送前都要与 bookSourceUrl 同源且为无 userinfo 的 HTTP(S)。保持超时、响应字节数、DOM 深度/节点数和有效唯一章节上限；超过章节上限明确拒绝，不能保存静默截断结果。enabled 省略时默认 true，提供时只能为 JSON 布尔值。
- Evidence: `lib/services/source_importer.dart`、`lib/services/source_engine.dart`；`test/source_engine_test.dart` 中跨源负向用例、5000/5001 章节边界和 enabled 类型测试；协议范围见 `docs/BOOK_SOURCES.md`。Web 遵守 CORS，不引入公共代理或关闭浏览器安全机制。

### P004 — 阅读位置是内容锚点

- Rule ID: P004
- Applies to: appRoot `.`，领域位置、阅读器、目录和笔记。
- Rule: 用章节索引与段落索引保存位置，不能用依赖字号和视口的屏幕页号替代。恢复与失败重试保留请求的逻辑锚点；更换章节从首段开始时保留标题。保存位置前按当前章节范围约束索引。
- Evidence: `lib/domain/book.dart` 的 ReadingPosition；`lib/application/app_controller.dart` 的 savePosition；`lib/ui/screens/reader_screen.dart` 的 _load/_restore；`test/domain_test.dart`、`test/app_widget_test.dart` 和 `test/reader_recovery_test.dart`。

### P005 — 品牌更新不破坏配色与兼容标识

- Rule ID: P005
- Applies to: appRoot `.`，Flutter UI、Web/Android/iOS/Windows 元数据、图标生成器和用户文档。
- Rule: 用户可见名称为“阅读”，保留原标语和蓝灰界面配色；宣纸/墨色/朱砂限于图标。Dart 包名 read_pilot、Android applicationId dev.readpilot.read_pilot、iOS Bundle ID dev.readpilot.readPilot、数据库 read-pilot.db/read-pilot-v1 等现有内部标识不随可见名称迁移。平台图标由同一生成器生成，保留可读的小尺寸及平台格式约束。
- Evidence: 用户明确要求“名字叫阅读”及“只要求改图标和名称，原有的背景色不变”；`lib/ui/theme.dart`、`lib/ui/components/brand_mark.dart`、`tool/generate_brand_assets.py`、`test/brand_identity_test.dart`、`test/brand_assets_test.py` 和平台元数据。

### P006 — 用现有工具验证实际提交快照

- Rule ID: P006
- Applies to: appRoot `.`，手写 Dart、正式测试及 Python 图标工具。
- Rule: 沿用 analysis_options.yaml 的 flutter_lints；提交前运行 `dart format --output=none --set-exit-if-changed lib test`、`flutter analyze` 和 `flutter test`。图标改动运行 `python -I -m unittest discover -s test -p brand_assets_test.py -v`。行为修复加入正式回归测试；不把 .tooling 中的隔离历史脚本当正式套件。测试异步存储使用现有 setUp/真实异步模式，避免在 testWidgets 的 FakeAsync 内等待无法推进的初始化。平台构建能力分开报告，不用 Web 结果冒充 APK/EXE/iOS 验收。
- Evidence: `analysis_options.yaml`、`pubspec.yaml`、`test/app_widget_test.dart`、`test/reader_recovery_test.dart`、`test/brand_assets_test.py` 和 `docs/VERIFICATION.md`。只使用项目现有工具；本规则不授权安装新 checker 或改变系统权限。
