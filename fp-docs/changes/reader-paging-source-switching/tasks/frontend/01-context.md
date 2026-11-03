# 阅读分页与书源切换能力 Frontend Plan

> **For agentic workers:** REQUIRED FLOW: Use `fp-execute` to implement this plan task-by-task. Only task markers in `10-runtime-tasks.md` and `20-ui-verification-tasks.md` use checkbox syntax. Do not commit, push, merge, stash, reset, or discard unrelated working-tree changes.

## Goal

在现有 Flutter 客户端内交付可持久化的左右分页阅读、参考图暖纸色、一步确认导入、手动换源、安全封面和确定性正文整理，同时保持段落锚点、事务发布和书源网络安全边界。

## Architecture

沿用 domain → services → data → application → ui 的现有依赖方向。先实现纯模型与布局/整理 helper，再扩展 transport、仓储和控制器，最后接入 UI 和真实浏览器验证。没有新第三方依赖、生产后端、路由或第二套状态管理。

## Tech Stack

- Flutter 3.47.8 stable / Dart 3.13.7。
- Flutter Material 3、`ChangeNotifier`、Sembast、现有 `package:http` 和 HTML 规则解释器。
- Flutter test、现有 Web release runner 与 Claude Browser preview 工具。

## Global Constraints

- Framework/runtime: `fp-docs/settings/frontend.md:7-12`；应用根为 `.`，源码在 `lib/`。
- Component library/design system: Flutter Material 3、`AppColors`、`QuietPanel`、NotoSansSC；不新增组件库。
- Script/style conventions: SDK/package imports 在前、应用内相对导入；`dart format` 和 `flutter_lints`。
- Visual source: 用户原图 `C:/Users/Lenovo/AppData/Local/Temp/claude/D--01-code-read-pilot/a36c177d-80ee-4d3c-bcc4-9908bc839fac/images/2.jpg`、已确认 `design/frontend.md` 和现有页面。
- Paper token: `#F4EFDC`；正文墨色 `#34332F`；窄屏断点 650；阅读正文最大宽度 760；候选面板最大宽度 600。
- Reader position: 继续保存 `chapterIndex + paragraphIndex`，不得持久化视口页号。
- Source safety: 保持同源、无 userinfo、私网拒绝、HTTPS 不降级、有限重定向/超时/响应大小/DOM/章节上限。
- Persistence: 数据库成功后才能发布控制器状态；切源失败保留原书、笔记、进度和缓存。
- Browser capability: 使用现有 `.claude/launch.json` 的 `read-pilot-web` runner 与 Browser preview 工具；不安装 Playwright、不修改 lockfile/CI。
- Verification environment: Flutter SDK `D:/ProgramFiles/flutter`；测试命令设置 `NO_PROXY` 与 `no_proxy` 为 `localhost,127.0.0.1,::1`。
- Engineering quality: 遵循共享 `engineering-quality.md` 和项目 P001–P006；新增公开对象写职责与契约说明，事务、竞态和网络限制写原因注释；无有意延后项。
- Git boundary: 用户未授权 commit、push 或 merge；每个任务只更新唯一 checkbox 和 `.fp-execute/progress.md`。

## File Structure

| Path | Action | Responsibility |
| --- | --- | --- |
| `lib/domain/reader_settings.dart` | modify | 持久化 `ReaderFlow` 并兼容旧设置 |
| `lib/domain/book.dart` | modify | 提供不可变来源重绑定和笔记位置复制 |
| `lib/domain/source_switch.dart` | create | 纯章节、位置和笔记映射 |
| `lib/ui/reader/reader_paginator.dart` | create | 用 `TextPainter` 生成真实视口页面与段落锚点 |
| `lib/services/source_runtime/content_normalizer.dart` | create | 规范化正文空白、空段和重复标题 |
| `lib/services/source_runtime/source_transport.dart` | modify | 支持受同一策略保护的字节响应 |
| `lib/services/source_engine.dart` | modify | 接入正文整理、详情刷新和封面字节加载 |
| `lib/data/app_repository.dart` | modify | 事务切源和迟到章节缓存保护 |
| `lib/application/app_controller.dart` | modify | 候选搜索、切源、封面编排和持久化后发布 |
| `lib/ui/components/source_import_sheet.dart` | modify | 一次确认完成 prepare + commit |
| `lib/ui/screens/reader_screen.dart` | modify | 选择分页/滚动视图并保持段落锚点 |
| `lib/ui/components/reader_preferences.dart` | modify | 阅读流模式分段按钮和新纸色 |
| `lib/ui/components/book_cover.dart` | modify | 安全字节图片与生成封面回退 |
| `lib/ui/components/book_details.dart` | modify | 换源与封面刷新入口 |
| `lib/ui/components/source_switch_sheet.dart` | create | 候选来源加载、空、错误、重试和选择 UI |
| `test/reader_paginator_test.dart` | create | 分页边界和锚点测试 |
| `test/source_switch_mapper_test.dart` | create | 章节、位置和笔记映射测试 |
| `test/content_normalizer_test.dart` | create | 正文整理测试 |
| `test/source_transport_test.dart` | modify | 字节响应和安全回归 |
| `test/source_engine_test.dart` | modify | 整理、详情和封面引擎测试 |
| `test/repository_test.dart` | modify | 事务切源和迟到缓存测试 |
| `test/controller_test.dart` | modify | 候选、切源、封面和发布时序测试 |
| `test/sources_screen_test.dart` | modify | 一步导入 widget 测试 |
| `test/reader_recovery_test.dart` | modify | 双模式恢复和持久化测试 |
| `test/book_details_test.dart` | create | 详情来源操作与候选状态测试 |
| `integration_test/live_source_switch_test.dart` | create | 真实来源切换候选和内容链路；环境不满足时记录 BLOCKED，不使用 mock |

## Page Goal and Visual Context

- 阅读页默认左右分页，设置可切回上下滚动。分页必须按真实视口测量，长段不能被截字。
- 纸张模式背景、AppBar 和正文统一为 `#F4EFDC`；明亮与夜间主题不变。
- 导入面板不再出现预览或勾选列表；用户点击主按钮后直接校验并事务提交。
- 详情页只为远程书显示“换源”和“刷新封面”；换源面板使用现有 Material 3 风格和完整状态反馈。
- 网络封面失败、CORS 拒绝或安全策略拒绝时，必须完整回退到现有生成封面。

## Figma Source and Browser Capability Resolution

- UI design source: no trustworthy Figma UI design；阅读纸色使用用户批准的静态截图，其他 UI 使用已确认设计合同和现有组件。
- Prototype usage: `PROHIBITED_AS_UI_REFERENCE`。
- Browser capability: project runner + Claude Browser preview tools。
- Completion vocabulary: 阅读纸色 case 可由批准截图与真实运行时证据评审；导入和换源的结构 reference 由确认后的 design contract 生成静态 SVG/PNG，不使用运行时截图冒充 reference。任何缺少 source 或 real runtime 的 case 为 `CANNOT_VERIFY/BLOCKED`。
