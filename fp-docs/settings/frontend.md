# FeaturePilot Frontend Settings

本配置适用于“阅读”的现有 Flutter 应用。它登记项目规范和 UI 约束，不授权创建原型、修改系统配置或扩大功能范围。2026-10-29，用户逐文件批准创建本文件和 `code-standards.md` 并登记规则来源。

## Frontend Framework and Source Locations

- Framework: Flutter 3.47.8 stable / Dart 3.13.7（本机实际版本）；`pubspec.yaml` 声明 Dart `>=3.8.0 <4.0.0`，Flutter 来自 SDK。
- App root: `.`；appId: `read-pilot`。Web、Android、iOS 和 Windows 共用同一 Dart 应用，不作为多个独立 app。
- Source roots: `lib/`；入口 `lib/main.dart`、`lib/app.dart`；Web 宿主 `web/index.html`。
- Route locations: `lib/app.dart` 管理 `/` 和 `/read/<encoded-book-id>`；无效阅读地址回书架。
- State/data: `lib/application/app_controller.dart` 使用 ChangeNotifier；持久化在 `lib/data/`，外部内容导入和 HTTP/CSS 解析在 `lib/services/`。
- Evidence: `pubspec.yaml`、`analysis_options.yaml`、当前应用入口和 `flutter --version`。没有 Django/Vue 生产应用信号，不套用其 preset。

## Code Standards

- Built-in preset: none
- Rule resources: N/A
- Applies to: appRoot `.`，Flutter/Dart 客户端及对应测试；平台资源和项目 Python 工具只适用项目规则中明确注明的条目。
- Project rule sources: `fp-docs/settings/code-standards.md`，按各条 Applies to 限定范围；Dart 工具规则另由现有 `analysis_options.yaml` 的 `flutter_lints` 和 `dart format` 实施。
- Confirmed overrides: none。项目没有 Flutter 内置 preset；不得将 `none` 误读为没有已登记项目规则。

## Component Library and Imports

- Library: Flutter Material 3，`flutter_localizations` 和 `cupertino_icons`；不新增 Web CSS 组件库。
- Import patterns: SDK/package 导入在前；应用内部沿用相对路径，测试使用 `package:read_pilot/...`。
- Component prefix: 无强制前缀；复用 `lib/ui/components/`，不为单次复用引入新的通用框架。

## Design Tokens and Styling

- Token/style sources: `lib/ui/theme.dart` 的 AppColors 和 appTheme；阅读页主题在 `lib/ui/screens/reader_screen.dart`，用户偏好范围在 `lib/domain/reader_settings.dart`。
- Layout/responsive rules: 沿用 `lib/ui/app_shell.dart` 的宽屏侧栏/窄屏底部导航及现有内容宽度限制；窄屏不得横向溢出。
- 用户确认：名称为“阅读”，标语为“让阅读，自由发生”；界面背景 `#F7F8FA`、蓝色 `#2468DE` 和淡蓝选中态保持原值。宣纸/墨色/朱砂仅用于古风标志，不替换应用主题。
- 本地中文字体为 NotoSansSC；许可保存在 `assets/fonts/OFL.txt`。

## Figma / Screenshot Handling

- Design sources: `docs/VISUAL_DESIGN.md`、品牌设计文档、实际应用和现有截图验收记录；未登记 Figma 文件。
- Mapping rules: Flutter 使用 CanvasKit 时，DOM/CSS 不代表实际绘制样式。结合组件测试、语义层、真实操作和截图核对；截图不能证明原生端通过验收。

## Prototype Base Reference

- Selected app and root: `read-pilot` / `.`。
- Base manifest: not initialized。本轮不创建原型，不安装原型依赖，也不登记不存在的基座。
- Source/build/preview rules: 后续只有明确选择原型工作时，才按独立批准进入 fp-prototype-init。

## Preview and Visual Verification

- 项目根构建：`flutter build web --release --no-web-resources-cdn`。
- Local preview command: `python -I -m http.server 4173 --bind 127.0.0.1 --directory build/web`。Claude 预览通过已存在的 `.claude/launch.json` 启动，不重复占用端口。
- 本机 Flutter SDK 为 `D:/ProgramFiles/flutter`；不要求修改全局 PATH。代理环境下，测试命令局部设置 NO_PROXY/no_proxy 为 `localhost,127.0.0.1,::1`。
- Browser/visual checks: UI 改动核对桌面和窄屏、加载/空/失败/重试状态；阅读改动核对段落恢复和本地存储失败。只依据本次实际运行报告通过，不将旧记录当新验证。
- 工具门禁见 P006：格式、静态分析、Flutter 测试；图标改动还需 Python 资源测试。Web release 与原生打包结果分别报告。

## Unknowns

- Android、iOS 和 Windows 的设备级验收仍未完成。现有记录表明本机缺 Android SDK、Windows 符号链接支持不可用，且 Windows 不能构建 iOS；不得自动改系统权限或声称原生包已验证。
