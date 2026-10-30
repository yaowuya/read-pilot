# 实施进度

## 2026-10-30 书源兼容与网络导入

- 已完成 raw-preserving 类型化书源、字段级能力报告、URL/文件/粘贴预览、选择后原子提交与 provenance sidecar。
- 请求编译器支持 GET/POST/HEAD、form/JSON/raw、静态/URL option headers、UTF-8/GBK、取消、手动重定向和敏感头剥离。
- 规则运行时支持 CSS/legacy、exact-text selector、安全 XPath 子集、RFC 9535 JSONPath、有界 regex、`||` fallback、发现与目录/正文分页；未确认语义的 `&&`、`%%`、put/get 保持 blocked。
- Android 使用 QuickJS disposable worker 执行限定 `searchUrl <js>` 与 `ruleContent @js:`；Web、Windows/iOS 未验证平台不执行脚本。
- native 网络客户端统一 canonical IP 检查、DNS 全答案验证、250 ms 错峰地址竞速、请求级取消、成功地址 pinning、并发 pin 代际保护和 HTTPS hostname/SNI 证书校验；Web 保持浏览器 CORS/PNA 边界。
- 用户提供的 8027 URL 已取得并指纹化；MuMu 上完成 URL import → preview → commit → 中文搜索 → 详情 → 目录 → 第一章正文，章节已缓存。
- 最终验证：Flutter analyze 无问题、171 项 Flutter 测试、6 项 Python 图标测试、Web release、Android debug build/install 均通过；详情见 `docs/VERIFICATION.md` 与 `docs/SOURCE_COMPATIBILITY.md`。

## 2026-10-30 启动图标定稿

- 已用严格 TDD 将被否决的朱砂/墨色 launcher painter 替换为原创的蓝色渐变、白色开卷轮廓和右页羽叶。
- `tool/generate_brand_assets.py` 以归一化 Bézier 几何生成 39 个 Web、Android、iOS AppIcon、Windows 和品牌预览资源；maskable/adaptive 分别使用独立安全区缩放。
- iOS AppIcon 尺寸改由 `Contents.json` 推导并输出 opaque RGB；LaunchImage 不再由 launcher 生成器写入，三个 PNG SHA-256 保持不变。
- 6 项 Python 图标测试通过，覆盖 1024/32/16 px、ordinary/maskable/adaptive、安全区、Android legacy/round、iOS 元数据、ICO 七帧、两次完整生成确定性与仓库快照。
- 已打开检查母版、32/16 px、Web maskable 和 Android adaptive 前景。应用内 `BrandMark`、主题和 iOS LaunchImage 未修改。
- Flutter analyze/test、Web/Android build 与设备启动器验收等待主会话在书源并行改动汇合后统一执行，本子任务不冒充这些集成验证已完成。

## 2026-10-29 “阅读”名称与古风图标更新（历史）

用户要求将产品名改为 **阅读**，并重新设计更古风的图标；随后明确只改名称和图标，原有背景色与界面配色不得改变。品牌验收结束时，代码保留在 `feat/flutter-reader`，尚未提交或推送。后续用户明确要求初始化规范并执行自动提交，提交前补充验证见 `docs/VERIFICATION.md`。

## 已完成

- Flutter、Web、Android、iOS、Windows 和用户文档中的可见名称统一为“阅读”。
- 内部 `read_pilot` / `read-pilot` 包名、Bundle ID、数据库和仓库标识保持不变，避免破坏已有安装和本地数据。
- 新图标采用宣纸底、朱砂闲章/月轮、墨色展卷的原创平面构图，不使用文字、渐变、照片或第三方素材。
- 新增 `tool/generate_brand_assets.py`，从同一母版确定性生成 Web、Android、iOS、Windows 和品牌预览资源；Android 含圆形与 v26 自适应图标。
- 应用内 `BrandMark` 使用同一构图，并提供“阅读标志”语义标签。
- 原界面配色保持不变：背景 `#F7F8FA`、主要蓝色 `#2468DE`、淡蓝选中态和原正文色全部恢复；原标语“让阅读，自由发生”也保持不变。

## 验证

- Python 图标测试：3 项通过。
- Flutter 静态分析：`No issues found`。
- Flutter 自动化测试：77 项全部通过。
- Web release：构建成功。
- 桌面 `1440×1000` 与手机 `390×844`：无横向溢出、旧名称不可见、0 个新增 console error。
- 像素验证同时检测到原背景/蓝色，以及只位于图标中的宣纸/朱砂/墨色。
- 部署包：`artifacts/read-pilot-web-0.1.0.zip`；提交前修复后已重新生成，当前 SHA-256 与完整验证结果统一记录在 `docs/VERIFICATION.md`。

## 位置

- 图标母版与小尺寸预览：`assets/branding/`
- 图标生成器：`tool/generate_brand_assets.py`
- 最终截图：`artifacts/brand-redesign/desktop-final.png`、`mobile-final.png`
- 验证日志：`artifacts/brand-redesign/`
- 详细验证：`docs/VERIFICATION.md`

## 环境限制（品牌历史记录）

该段对应 2026-10-29 的品牌阶段：当时 Android SDK 尚未配置、Windows symlink 不可用且 iOS 无法在 Windows 构建。当前 Android/Web 结果以上方 2026-10-30 记录及 `docs/VERIFICATION.md` 为准；Windows QuickJS 与 iOS 仍未验证。

`read-pilot-watchdog` 在本轮执行期间只负责恢复原主会话，最终验证完成后已停用。