# “阅读”名称与古风图标更新完成（2026-10-29）

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

## 环境限制

Android SDK 未检测到，没有 APK；Windows 因符号链接支持不可用没有 EXE；Windows 主机不能构建 iOS。本轮没有更改系统权限，也不声称原生安装包经过验证。

`read-pilot-watchdog` 在本轮执行期间只负责恢复原主会话，最终验证完成后已停用。