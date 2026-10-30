# “阅读”启动图标定稿实施计划

> **执行方式：** `superpowers:executing-plans` + 严格 TDD。只修改 launcher 图标生成器、正式图标测试、生成资源和图标专属文档；不修改应用内 `BrandMark`、主题或书源代码。

**目标：** 用原创的“蓝色渐变 + 白色开卷 + 右页羽叶”替换已否决的朱砂/墨色 launcher painter，并为所有平台生成确定、可复现的资源。

**实现边界：** `tool/generate_brand_assets.py` 为唯一几何源；iOS LaunchImage 不参与生成；iOS AppIcon 尺寸来自 `Contents.json`；maskable/adaptive 使用独立缩放安全区。

## 任务 1：先锁定失败契约

- [x] 重写 `test/brand_assets_test.py`，覆盖颜色、开卷/羽叶位置、16/32/1024 px、ordinary/maskable/adaptive 安全区、Android、iOS、ICO 和确定性。
- [x] 对旧 painter 运行新测试并观察失败：`LAUNCHER_WHITE` 不存在、maskable 生成接口不存在、旧图标没有白色小尺寸几何。
- [x] 修正隔离 Python 的执行方式：使用 `python -I test/brand_assets_test.py ...`，避免 `-I` 移除项目根后模块导入失败。

## 任务 2：实现归一化原创几何

- [x] 保留已确认的竖向渐变 `#3AA9FF` → `#28A1FF`。
- [x] 用归一化 Bézier 路径绘制白色左右书页、中央折线、右页羽叶主干和六条交错叶片。
- [x] 增加 `generate_maskable_icon`，并将 Web maskable 图标切换到独立安全区版本。
- [x] 将 Android adaptive foreground 缩放到中央 `66dp / 108dp` 安全区，背景继续使用本地 XML 渐变。
- [x] 保持普通输出全幅不透明，由各平台 mask 提供圆角或圆形外观。

## 任务 3：修正平台生成边界

- [x] Android 五档 legacy 普通/圆形、adaptive 前景和 XML 均从同一生成器输出。
- [x] iOS AppIcon 不再读取待验证 PNG 的现有尺寸，改为解析 `Contents.json`。
- [x] iOS AppIcon 强制保存为 opaque RGB。
- [x] 从 `write_all_assets` 移除 LaunchImage 写入，保证三个启动图 PNG 字节不变。
- [x] Windows ICO 保持 16–256 px 七帧。

## 任务 4：生成与聚焦验证

- [x] 运行 `python -I tool/generate_brand_assets.py`，生成 39 个 launcher 资源。
- [x] 运行 6 项正式 Python 图标测试。
- [x] 在临时目录连续完整生成两次，要求每次返回 39 个互不重复且顺序一致的目标路径，比较所有输出 SHA-256，并与仓库快照逐字节比较。
- [x] 对仓库与临时目标文件分别复验 Web ordinary/maskable 透明度与安全圆、Android adaptive 透明安全区，避免 writer 路由错误被自生成快照遮蔽。
- [x] 打开检查 1024、32、16 px、Web maskable 和 Android adaptive 前景。
- [x] 复核 LaunchImage、应用内 BrandMark 与主题文件哈希未变化。

## 任务 5：文档与主会话交接

- [x] 用本定稿设计覆盖旧的朱砂/墨色 launcher 方案，并更新 README、视觉、进度和验证记录。
- [x] 记录本会话实际执行的 Python 命令与结果，不冒充 Flutter/原生集成验证。
- [x] 将 Flutter analyze/test、Web/Android build 和设备启动器验收留给主会话在并行改动汇合后统一执行。
