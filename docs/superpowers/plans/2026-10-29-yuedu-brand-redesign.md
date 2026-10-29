# 「阅读」品牌重设计实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` inline. Steps use checkbox syntax for tracking. User previously required autonomous execution and no automatic commits or pushes.

**Goal:** 将产品用户可见品牌统一改为“阅读”，并用可重复生成的古风图形替换现有蓝色书页图标。

**Architecture:** 内部包名、Bundle ID、数据库标识和仓库路径保持不变；用户可见品牌通过 Flutter 常量、平台元数据和文档统一。图标由一个 Pillow 脚本从同一几何母版生成所有平台尺寸，应用内 `BrandMark` 用 Flutter CustomPainter 重画同一构图。

**Tech Stack:** Flutter 3.47.8 / Dart 3.13.7、Material 3、Python 3.9 + Pillow、Android/iOS/Web/Windows 平台资源。

## Global Constraints

- 产品正式名称只能显示“阅读”，不显示旧品牌或新英文品牌。
- `read_pilot`、`read-pilot`、`dev.readpilot.read_pilot`、`read-pilot.db`、`read-pilot-v1` 保留为内部兼容标识。
- 图标必须使用宣纸 `#F2E8D5`、墨色 `#28302C`、朱砂 `#A54636`，不使用渐变、照片、Emoji 或字体字形。
- 不改变导航、阅读器、书源和存储行为。
- 不自动提交或推送，不改系统权限。

---

### Task 1: 品牌文字契约

**Files:**
- Create: `test/brand_identity_test.dart`
- Modify: `lib/app.dart`, `lib/main.dart`, `lib/ui/app_shell.dart`, `lib/ui/screens/profile_screen.dart`, `lib/ui/screens/sources_screen.dart`, `lib/ui/components/book_cover.dart`
- Modify: `pubspec.yaml`, `web/index.html`, `web/manifest.json`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `windows/runner/main.cpp`, `windows/runner/Runner.rc`
- Modify: 品牌文档、样例内容与署名文件。

**Interfaces:**
- Produces: visible product name `阅读`; technical identifiers remain unchanged.

- [x] 写失败测试：渲染 `ReadPilotApp` 后找到“阅读”，找不到旧品牌；读取关键元数据确认产品名。
- [x] 运行品牌测试，确认旧实现未满足“阅读”契约。
- [x] 替换所有用户可见旧名称；保留内部标识并在 README 说明。
- [x] 扫描用户可见内容，确认旧品牌只出现在用于防回归的否定断言中。
- [x] 运行品牌测试转绿。

### Task 2: 可重复的古风图标母版

**Files:**
- Create: `tool/generate_brand_assets.py`
- Create: `assets/branding/icon-master.png`
- Modify: `web/favicon.png`, `web/icons/*.png`, Android mipmap、iOS AppIcon、Windows ICO。
- Create/Modify: Android v26 自适应图标资源。

**Interfaces:**
- `generate_icon(size: int, safe_zone: float) -> PIL.Image.Image`
- `write_all_assets(project_root: Path) -> list[Path]`

- [x] 写脚本自检：目标尺寸、RGBA/RGB、ICO 多尺寸和 maskable 安全区。
- [x] 先运行自检，确认旧图标不符合新像素/配色契约。
- [x] 用超采样曲线绘制宣纸底、朱砂方印、墨色展卷和朱砂月轮；禁止渐变。
- [x] 从母版生成所有平台资源和 Android 自适应图标。
- [x] 再次运行生成器，验证确定性哈希和目标尺寸。
- [x] 打开 1024、192、32、16 px 输出检查识别度。

### Task 3: 应用内标志与配色回归保护

**Files:**
- Modify: `lib/ui/components/brand_mark.dart`; keep `lib/ui/theme.dart` behavior unchanged.
- Test: `test/brand_identity_test.dart`, existing widget tests.

**Interfaces:**
- `BrandMark(size)` renders the same four elements as the launcher icon.
- `AppColors.blue`, `AppColors.softBlue`, `AppColors.background`, `AppColors.ink` retain the original interface palette.

- [x] 增加主题测试，断言科技蓝、冷灰背景和选中态保持原值。
- [x] 运行测试确认朱砂主题改动违反该契约。
- [x] 重绘 `BrandMark`，将宣纸/墨色/朱砂限定在标志内部；恢复所有界面配色。
- [x] 更新调用并运行静态分析、品牌测试与组件测试。

### Task 4: 文档、构建与视觉验收

**Files:**
- Modify: `README.md`, `THIRD_PARTY_NOTICES.md`, `LICENSE`, `docs/*.md`, task state/progress.
- Regenerate: `build/web`, `artifacts/read-pilot-web-0.1.0.zip`, checksum and screenshots.

- [x] 更新文档：产品名为“阅读”；内部 ID 保留原因；图标生成方式与配色。
- [x] 运行全量格式化、静态分析和全部测试。
- [x] 构建 Web release 并重新打包、校验 SHA-256。
- [x] 真实浏览器检查桌面与 390px 手机：标题、新标志、原蓝色操作色、原冷灰背景、无溢出和无新增 console error。
- [x] 查看品牌母版、桌面和手机截图；确认小尺寸仍能辨认书卷/月轮/朱印。
- [x] 全仓扫描旧名称；历史迁移文档之外不得出现旧用户品牌。
- [x] 更新验证记录并停用恢复任务。

## Completion record

用户补充确认只改名称和图标，原界面背景和配色保持不变；实施与测试据此调整。最终完成名称、全平台图标、应用内标志、元数据和文档更新，保留所有内部兼容标识。3 项 Python 图标测试、77 项 Flutter 测试、静态分析和 Web release 均通过；桌面/手机截图确认原蓝灰界面和新古风图标同时存在。没有提交或推送。

## Self-review

覆盖名称、应用内标志、主题、全平台图标、平台元数据、文档、回归和部署包。没有更改内部持久化标识，因此不会造成已有 Web/原生数据迁移。没有占位项；所有验证命令和成功条件均明确。