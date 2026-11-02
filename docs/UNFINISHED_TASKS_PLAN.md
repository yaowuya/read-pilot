# 未完成任务与恢复计划

> 状态：当前选定范围已完成并验证。单段文字选区标注通过聚焦回归、424 项串行完整 Flutter 测试、静态分析、Web 生产构建和最终 Android 包检查；本文保留为真实书源验证与后续边界的记录。
>
> 发布规则：本批只生成了一次最终 APK，后续新增范围必须重新验证后再单独交付。

## 1. 已停止的自动工作

- 十分钟会话级监控任务已取消；不会再自动投递旧的迁移提示。
- 没有可运行的侧会话、后台代理或预览服务器。
- 已归档的“Finish mark management”侧会话不应恢复；其已交接的实现状态已保留在当前工作树。
- 不要执行 `git reset`、`git clean`、删除未跟踪文件、提交、推送或安装 APK，除非用户再次明确要求。

## 2. 当前范围：实现已完成，待全量验证与最终打包

### 已完成实现与聚焦验证的部分

以下文件已有未提交改动：

- `lib/domain/reader_mark.dart`
  - 新增可选 `selectedText`，保持旧整段标注 JSON 兼容。
  - 限制选区为 1–240 字符，拒绝空字符。
  - 用“段落中恰好一次出现”而非全局偏移作为稳定性条件。
- `lib/application/app_controller.dart`
  - `addReaderMark` 接受 `selectedText`。
  - `readerRangeMarksAt` 只返回来源、章节、指纹和唯一文本都仍匹配的选区。
- `lib/data/app_repository.dart`
  - 同一片段更新原记录；不同且不重叠的片段可同段共存。
  - 重叠选区应被事务内拒绝。
- `lib/ui/reader/reader_paragraph.dart`
  - `ReaderTextHighlight` 和安全、非重叠的高亮 `TextSpan`。
  - `SelectionArea` 选中纯文本回调。
- `lib/ui/screens/reader_screen.dart`
  - 仅滚动模式、无正文显示替换规则时收集唯一选区。
  - 阅读设置新增“选中文字标注”入口；选区保存后应清理临时选择。
  - 分页模式保持禁用选区入口，避免分页碎片偏移歧义。
- `lib/ui/components/reader_marks_sheet.dart`
  - 管理页优先预览选区文本，并显示“选区标注”标签。

### 已通过的聚焦与全量证据

- `test/reader_mark_test.dart`：选区同段共存、重复同片段更新、唯一出现检查、重叠选区拒绝、来源/正文/唯一性失效与重载后查找。
- `test/reader_paragraph_test.dart`：精确高亮 Span、首行缩进不变、SelectionArea 回调桥接。
- `test/reader_mark_screen_test.dart`：滚动阅读选择唯一文本后启用并保存、取消选择、翻页方式切换、分页入口禁用、正文替换和章节切换后禁用，以及精确高亮。
- `test/reader_marks_sheet_test.dart`：管理页展示选区标签、已失效选区筛选、回跳拒绝与确认删除。
- 与 `test/reader_recovery_test.dart` 一起运行的选区聚焦回归共 55 项通过。
- 串行完整 Flutter 测试 424 项通过；`flutter analyze` 无问题。
- `flutter build web --no-web-resources-cdn` 以退出码 0 完成；窄屏预览确认分页入口提示，控制台与网络失败记录为空。
- 最终 APK 已归档为 `artifacts/releases/read-pilot-0.1.0-bounded-text-selection-release-debug-signed.apk`，SHA-256 为 `31165d5d5af2abcb23f9a3bb1e3351f8f252aef9d033bcb076d82daaddef74ec`；v2 签名、包元数据、ZIP CRC 和内置主图均已核验。

### 本批完成记录

1. **Web 验证完成**
   - 分页阅读显示“切换到上下滚动后可选择文字”；浏览器控制台和网络失败记录为空。
   - 不把浏览器自动拖选伪称为 Flutter 原生选区手势证据；精确保存与高亮由 Widget 回归证明。
2. **最终 APK 打包完成**
   - 使用 `FLUTTER_WINDOWS=false flutter build apk --release` 生成且只归档了一次最终包。
   - APK 使用 Android Debug 证书；包名、SDK 范围、ZIP CRC、签名与主图字节均已检查，尚未安装到原生设备。

## 3. 已完成但未提交的书源管理工作

### 书源导入预览与选择

- 文件：`lib/ui/components/source_import_sheet.dart`、`test/sources_screen_test.dart`。
- 行为：URL/文件/文本输入先检查并预览；用户默认全选，但可清空、全选或逐条选择；空选择不能提交；只用 `selectedSourceIds` 原子提交明确选中的来源。
- 安全边界：预览阶段不持久化、不执行来源规则、不显示响应正文/请求头/Cookie；仍执行来源数、JSON 深度、URL、重定向、内容类型与主机限制。

### 100 MiB 书源上限

- 文件：`lib/services/source_importer.dart`、`lib/services/source_import_service.dart`、`lib/ui/components/source_import_sheet.dart`、相关测试与文档。
- 统一上限：文本、文件和 URL 默认最大 **100 MiB**；URL 仍在流式读取期间中止超限响应。
- 已有验证基线（在开始选区标注前）：
  - 144 项书源导入/解析/换源回归通过。
  - 413 项完整 Flutter 测试通过。
  - `flutter analyze` 与 Web 构建通过。
  - 文件导入模式真实显示“最大 100 MiB，仅限 JSON。”
  - Android Debug 签名 release：`artifacts/releases/read-pilot-0.1.0-source-100m-release-debug-signed.apk`。
  - SHA-256：`9703c61671877004d0f57e993c17b219b60e0c215e01820ee340db4c93fc3587`。

> 第 2 节的最终验证已经覆盖共享读者与标注改动；本节保留的是开始选区工作前的书源验证历史，不能替代未来书源范围变更后的重新验证。

## 4. 真实书源验证待办

### 用户提供的来源结果

- `yiove` 合集可被安全导入器解析为 11 条来源定义。
- `yckceo` 1325 URL 在 100 MiB 上限下仍报告网络连接失败；没有使用代理、Cookie、重定向直连或安全绕过。
- 对合集来源的有界搜索没有获得第二个同名候选，因此没有真实换源成功证据。
- MuMu 当前未连接，不能声称新的 Android 联网验证成功。

### 恢复时需要的条件与步骤

1. 确认 MuMu 或另一台授权 Android 设备通过 `adb devices` 可见。
2. 使用新的最终 APK 覆盖安装，保留数据；不卸载或清理数据。
3. 在真实应用中导入合规且不超过 100 MiB 的来源 JSON 或合集子集。
4. 记录仅必要的元数据：导入数量、响应大小、状态分类；不存储第三方规则正文、请求头或 Cookie。
5. 搜索一个在至少两个已选来源中存在的同名书籍。
6. 加入书架后执行换源，验证目标目录、当前位置章节和正文均能加载，且书签/进度按既有映射规则保持一致。
7. 若没有稳定的第二个同名候选，报告“真实双源换源仍 BLOCKED”，不要以模拟或单来源搜索代替。

## 5. 后续安全迁移候选（尚未开始）

按价值与风险由低到高排序；每项都必须单独设计、先写失败测试、获得明确范围确认后实施：

1. **更完整的单段/跨段文字选区标注**：当前单段唯一选区完成后，再评估跨段语义、失效规则和无障碍。
2. **已定义的来源规则扩展**：只实现公开文档有稳定语义、可加资源上限和兼容样本的组合。`&&`、`%%`、put/get 等无公开可验证语义的方言继续拒绝。
3. **PDF、MOBI/KF、UMD 本地格式**：每种格式单独评估纯 Dart/平台依赖、畸形文件上限、DRM 拒绝、渲染和无障碍；不能以目录扫描或广泛存储权限换取支持。
4. **跨段选区与标注导出**：必须先定义唯一位置恢复、文本变化失效、备份兼容和隐私边界。
5. **云/WebDAV、Cookie/WebView、远程订阅、媒体和完整脚本方言**：目前没有实施计划；需要凭据、跨域状态、远程代码或 DRM 风险时继续排除。

## 6. 恢复前检查清单

- [ ] 读取本文件与 `docs/LEGADO_MIGRATION_STATUS.md`。
- [ ] 执行 `git status --short`，保留所有现有修改和未跟踪文件。
- [ ] 先完成第 2 节，再决定是否进入第 5 节的下一项。
- [ ] 不在每个小增量后打包；只在当前用户选定的任务集合全部通过验证后打包一次。
- [ ] 不提交、推送、安装或清理数据，除非用户另有明确指令。
