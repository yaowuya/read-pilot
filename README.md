# 阅读

一个用 Flutter 独立实现的、离线优先的中文阅读应用。阅读体验参考微信读书的简洁布局，书源机制参考 Legado 的声明式规则，但不复制微信读书品牌素材，也不移植 Legado 的 Kotlin 实现。

![阅读古风图标](assets/branding/icon-32.png)

品牌图标以宣纸、墨色展卷、朱砂月轮和闲章为核心；这些古风色彩只用于图标，应用界面继续使用原有科技蓝和冷灰背景。用户可见名称统一为“阅读”；仓库、Dart 包、Bundle ID 与数据库继续保留 `read-pilot` / `read_pilot` 内部标识，以兼容现有安装和本地数据。图标可用 `python -I tool/generate_brand_assets.py` 从同一母版重新生成。

## 当前功能

- **书架**：搜索书名/作者、在读/已读筛选、排序、网格/列表切换、书籍详情与移除确认。
- **离线书库**：内置六部公版作品的明确标注节选，首次启动三本在书架中，其余可从“发现”加入。
- **本地导入**：TXT 文件，支持 UTF-8、UTF-8 BOM 和带 BOM 的 UTF-16，最大 2 MiB；自动识别中文章节。
- **阅读器**：章节目录、上一章/下一章、段落锚点恢复、阅读完成标记和文本选择。更换字号或视口不会把屏幕页码误作阅读位置。
- **书签与笔记**：收藏当前段落、添加想法、回到原文、删除笔记，均保存在本机。
- **阅读偏好**：纸张/明亮/夜间主题、18–32 px 字号、1.4–2.4 倍行距，跨书籍持久化。
- **自己的书源**：JSON 文本或文件导入，校验、启停、删除和配置复制；支持搜索、详情、目录、正文与按需章节缓存。
- **响应式布局**：手机底部导航、宽屏侧栏、限制行长的正文阅读区。

这不是完整 Legado 引擎，也不是微信读书服务的客户端。首版没有账号、社交、云同步、付费商城、EPUB/PDF、朗读和仿真翻页。

## 本机开发环境

Flutter SDK 按指定位置安装：

- `D:\ProgramFiles\flutter`
- Flutter **3.47.8 stable** / Dart **3.13.7**
- 原始发行包经过官方发布索引所给 SHA-256 校验。
- 没有修改全局 PATH 或代理设置。以下命令使用 SDK 的绝对路径，适用于 Git Bash。

安装依赖（网络较差时使用 Flutter 中国镜像）：

```bash
PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn "D:/ProgramFiles/flutter/bin/flutter" pub get
```

开发运行：

```bash
NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 "D:/ProgramFiles/flutter/bin/flutter" run -d chrome --web-port=5173
```

本机已有 HTTP 代理。`NO_PROXY` 仅对这条命令生效，避免 Flutter 的本地调试 WebSocket 被代理截走。

## 验证与构建

完成显式依赖安装后，重复验证使用 `--no-pub`，避免验证命令重新解析锁定依赖或重复触发本机原生插件设置。依赖有意变更时，先重新执行上面的镜像安装命令并检查 `pubspec.lock`。

静态分析：

```bash
"D:/ProgramFiles/flutter/bin/flutter" analyze --no-pub
```

自动化测试：

```bash
NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 "D:/ProgramFiles/flutter/bin/flutter" test --no-pub
```

Web 生产构建（CanvasKit 等渲染资源随包部署）：

```bash
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn "D:/ProgramFiles/flutter/bin/flutter" build web --release --no-pub --no-web-resources-cdn
```

构建结果位于 `build/web/`。应通过 HTTP 服务器访问，不要直接双击 `index.html`：

```bash
python -I -m http.server 4173 --bind 127.0.0.1 --directory build/web
```

打开 <http://localhost:4173>。Claude 桌面应用的预览启动配置保存在 [.claude/launch.json](.claude/launch.json)。如果该预览服务器已经运行，不要再次占用同一个端口。

### 平台状态

| 平台 | 本次状态 |
| --- | --- |
| Web | 已生成并运行 production build；详细结果见验证记录 |
| Android | 原生工程已生成并声明网络权限；Flutter 未检测到 Android SDK，未生成或验证 APK |
| iOS | 原生工程已生成；本机为 Windows，未编译或验证 iOS |
| Windows | 原生工程、名称和图标已准备；实际构建被系统未启用符号链接支持阻止，未生成 EXE |

Windows 打包需要设备管理员提供符号链接权限或开启 Windows 开发者模式；本次没有自动更改该系统设置。原生 Android/iOS 默认遵守平台的 HTTPS 策略，明文 HTTP 书源可能被系统拦截；本地 HTTP fixture 仅在 Web 中验收。

## 书源不是“万能解析”

支持 **Legado 声明式 CSS 子集 v1**：

- `bookSourceType: 0`，四类 JSON 规则对象也可编码为 JSON 字符串。
- 显式 `@CSS:`、单个 CSS 选择器、`@text` / `@ownText` / `@textNodes` / `@html` / 属性提取。
- HTTP(S) GET、UTF-8、单页目录与单页正文；每本最多 5,000 个有效章节，超限明确拒绝而不静默截断。
- 精确的 `{{key}}`、`{{page}}`、`{{baseUrl}}`，相对 URL；模板展开、详情、目录、正文和重定向在请求前都必须与声明书源 **同源**。
- `enabled` 省略时默认启用，提供时必须是 JSON 布尔值。
- 超时、响应大小、DOM 深度与节点数限制；不执行远程代码。

JavaScript、XPath、JSONPath、旧式链式规则、正则后处理、动态登录和自动翻页不受支持。复杂来源会报告具体字段错误。Web 必须遵守来源的 CORS；不通过公共代理或关闭浏览器安全机制绕过。

完整规范和上游依据见 [docs/BOOK_SOURCES.md](docs/BOOK_SOURCES.md)。

### 受控书源示例

[examples/book-source.json](examples/book-source.json) 是**本地验收示例**，不是线上书库。启动它对应的服务器：

```bash
python -I tool/source_fixture_server.py --port 8766
```

然后在“书源”中导入这个 JSON，在“发现”中搜索“月下”。示例正文为本项目原创测试内容，只用于验证真实 HTTP 流程；服务器只监听本机地址，并仅向本地应用的 4173 / 5173 端口开放跨域。Claude 预览配置中的 `read-pilot-source-fixture` 也可运行它。

## 数据与隐私

- 不需要账号，不发送遥测，也没有自建后端。
- 原生端使用应用数据目录中的 Sembast 数据库；Web 使用 IndexedDB `read-pilot-v1`。
- Web 数据绑定当前浏览器及站点来源（协议、域名和端口）；切换 `localhost` / `127.0.0.1` 或开发端口不会共享书架。
- 阅读进度、笔记、书源和已获取正文留在当前设备。
- 已缓存的章节在书源离线后仍可阅读；未下载的章节不会假装已缓存。
- 清理应用/站点数据会删除阅读数据。当前没有备份导出或跨设备同步，请保留重要 TXT 原文件。
- 只导入你有权使用的内容与来源；不要在来源地址中放账号、密码或令牌。

## 目录

```text
lib/
  domain/          书籍、章节、位置、笔记、设置与书源
  data/            Sembast 持久层、平台数据库与公版目录
  services/        TXT 解码/分章、书源校验与受限 HTTP/CSS 引擎
  application/     状态协调、持久化操作与章节缓存
  ui/              书架、发现、书源、个人页、阅读器与共用组件
assets/
  books/           明确标注来源的公版节选
  fonts/           Noto Sans SC 及 SIL OFL 许可证
examples/          可导入的受控书源示例
test/              领域、导入、持久化、书源、状态和组件回归测试
tool/              本地 HTTP 验收服务
```

## 设计、进度与许可

- [设计说明](docs/superpowers/specs/2026-10-28-read-pilot-design.md)
- [实施计划](docs/superpowers/plans/2026-10-28-read-pilot.md)
- [视觉方向](docs/VISUAL_DESIGN.md)
- [实际验证记录](docs/VERIFICATION.md)
- [实施进度](docs/PROGRESS.md)
- [项目规范入口](fp-docs/manifest.md) / [Flutter/Dart 项目规则](fp-docs/settings/code-standards.md)
- [原始代码 MIT 许可](LICENSE) / [字体、样本文字及参考项目说明](THIRD_PARTY_NOTICES.md)

公版书籍均为节选或原创选编，不冒充全本，不包含现代译注。字体使用完整 Noto Sans SC，并附 OFL；图标与书封为原创。Legado-with-MD3 为 GPL-3.0；如后续复制或移植其实现，必须重新评估 GPL 的分发要求，不能沿用当前“独立实现”的声明。
