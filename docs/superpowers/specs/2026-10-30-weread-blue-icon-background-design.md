# “阅读”启动图标定稿设计

- **状态：** 2026-10-30 定稿
- **范围：** 仅限各平台 launcher/AppIcon 资源及其生成器，不扩散到应用内视觉系统。

## 锁定结果

启动图标采用以下原创构图：

- 全幅竖向蓝色渐变：顶部 `#3AA9FF`、底部 `#28A1FF`；
- 白色展开书页轮廓，保留蓝色页内留白，不做实心书本；
- 一枚白色羽叶从右页向右上方生长，与书页在起点处相连；
- 不使用文字、阴影、第三方图片或远程素材。

用户提供的视觉目标只用于确认方向，原始参考文件不在仓库中。实现没有描摹或复制微信读书的书本、气泡或其它图形；书页、折线、羽叶主干与叶片均由本项目的归一化 Bézier 几何重新构造。

“圆角背景”由 iOS、Android adaptive/round 和 Web maskable 等平台 mask 呈现。普通位图保持全幅不透明渐变，避免在 iOS AppIcon 中预烘焙圆角或透明角；Android 另有圆形 legacy 资源。

## 几何与安全区

`tool/generate_brand_assets.py` 是唯一资源源头。所有坐标和线宽均相对于画布归一化，并在高分辨率画布上绘制后用 Lanczos 缩小：

- ordinary 图标使用 `1.00` 倍标志，白色内容约束在画布中央；
- Web maskable 图标使用 `0.82` 倍标志，包含抗锯齿边缘在内的可见白色内容位于中心 `80%` 安全圆内；
- Android adaptive foreground 使用 `0.62` 倍标志，所有非透明像素位于中央 `66dp / 108dp` 安全区内；
- 蓝色背景始终全幅延伸到边缘，裁切后不会露出空角。

书页由左右两条开页轮廓和中央折线组成。羽叶主干从右页内部出发，沿右上方向弯曲，六条交错叶片形成与任何第三方品牌不同的原创轮廓。

## 平台输出

- `assets/branding/`：1024、32、16 px 母版与小图；
- Web：ordinary favicon/PWA 图标和独立 maskable 图标；
- Android：五档 legacy 普通/圆形图标、432 px 透明 adaptive foreground、本地渐变 background drawable；
- iOS：由 `AppIcon.appiconset/Contents.json` 推导每个像素尺寸，全部输出为不透明 RGB；
- Windows：ICO 内含 16、24、32、48、64、128、256 px 七帧。

`ios/Runner/Assets.xcassets/LaunchImage.imageset/` 不属于本次 launcher 图标生成范围，三个 PNG 保持原字节不变。应用内 `lib/ui/components/brand_mark.dart` 和 `lib/ui/theme.dart` 也保持不变，因此宣纸、朱砂、墨色的应用内 `BrandMark` 与蓝灰界面不受影响。

## 确定性与验收

正式测试必须覆盖：

1. 蓝色端点、白色开卷与右页羽叶的语义位置；
2. 1024、32、16 px 的可辨性和两次函数调用一致；
3. ordinary、maskable、adaptive 三类安全区；
4. Android legacy/round/adaptive 与 XML 引用；
5. iOS 元数据推导尺寸和 opaque RGB；
6. Windows ICO 的全部七帧；
7. 两次完整生成的逐文件 SHA-256 一致，并与仓库快照逐字节一致；
8. iOS LaunchImage 三个固定 SHA-256 不变。

更广的 Flutter analyze/test、Web/Android build 与设备启动器验收由主实施会话在合并其它并行改动后统一执行，避免把并行中的非图标变化误归因于本子任务。
