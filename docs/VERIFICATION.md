# 构建与验证记录

本记录基于实际命令、真实浏览器操作和已查看的截图，不将原生工程生成等同于原生应用验证。

## 2026-10-31 本地提交前复核

- 按已登记 Flutter/Dart 项目规范审查当前完整改动；本轮只授权本地 commit，不推送、不创建 PR、不归档，也不将本次局部审查当作 `fp-final-review`。没有新增项目规范或修改规范登记。
- 正式红绿回归修复了换源时重复章名/正文/引用误跳第一处、预取后目标章节改变、迟到正文和进度污染新来源，以及阅读页未随来源绑定失效的问题。歧义锚点保留约束后的原索引，未验证的最终换源目标明确拒绝。
- 阅读恢复回归覆盖迟到设置保存、旧来源进度拒绝、短视口滚动回退往返及系统文字放大；正文和章节标题采用一致测量策略。正文标题去重保留标点，替换限额错误提示改为准确的 UTF-16 单位。
- 一步导入的原子保存阶段明确显示“正在保存书源…”并禁用取消；获取/准备阶段仍可取消且不进入持久化。新增控件回归先观察到保存阶段仍可取消，再修复转绿。
- 当前快照：`dart format --output=none --set-exit-if-changed lib test integration_test` 检查 **81 个文件，0 修改**；`flutter analyze --no-pub` 为 **No issues found**；`flutter test --no-pub` **275 项全部通过**；Python 图标测试 **6/6 通过**。
- 当前源码的 Web release 和 Android release 均构建成功。Android 保留既有 Java native-access 与 file_picker/KGP 未来兼容性警告；未修改依赖锁、全局权限或系统配置，81 个 Dart 文件在测试和两次构建后哈希未变。
- 新构建 APK 位于 `build/app/outputs/flutter-apk/app-release.apk`，v2 签名、ZIP/CRC 及三个 ABI 的 app/Flutter/QuickJS 库检查通过；本轮未重新安装到模拟器。之前交付并安装的 `artifacts/releases/read-pilot-0.1.0-universal-release.apk` 保持原 SHA-256 `14c95edb1411e32687c1de9bb8b9d5f0a113afa052ea978f2b0a932035542289`，不能将其视为已包含本次审查修复。
- 正式 Web 构建在独立 4175 origin 实测《浮生六记》点击翻页 1/15→2/15；375×250 自动退回滚动，实际滚动后恢复 375×812 显示 3/15，未回到旧分页控制器位置。[实际阅读截图](../artifacts/commit-checks/20261031-reader-mobile.jpg)留在本机；控制台无 error，网络无失败请求，临时预览与 launch 条目已清理。
- 本次导入浏览器观察只确认单一“确认导入”入口、无效 JSON 错误保留弹层及来源数量仍为 0。文本输入适配未将测试 JSON 成功传入 Flutter 控制器，未记录为真实导入成功；取消/保存时序以正式控件回归为补充，不替代完整真实 E2E。
- 真实双源换源、严格视觉参考及完整异常/时序 E2E 的历史 **BLOCKED** 保持不变；未进行第四次真实双源尝试，没有注入业务数据库或拦截请求伪造通过。日志、截图、APK、CodeGraph 索引与机器执行/恢复状态留在本机，不纳入提交。

## 2026-10-31 目录顺序与排版偏好

- 三项代码功能已落地：目录正序/倒序、0–40px段距、正文粗体；旧设置维持20px/普通字重/正序。章节原始顺序、内容锚点、书签和网络边界不变。
- 新增红绿证据覆盖缺失字段、控件和目录入口，以及测量key/两种阅读流。测试还先捕获了“失败回退到弹层初始值”和“新Switch在已有装饰卡片内缺少Material绘制面”两项边界，再修复并转绿。
- `dart format --output=none --set-exit-if-changed lib test integration_test`：81个文件，0修改；`flutter analyze --no-pub`：No issues found；`flutter test --no-pub`：**247项通过**。
- Web release和Android debug构建成功。APK已使用`adb install -r`覆盖安装至`emulator-5556`并启动MainActivity，未清除本地数据；不将安装启动等同于三项功能的原生完整E2E。构建仍有现有Java native-access和file_picker/KGP未来兼容性警告，未为此修改依赖或系统设置。
- 真实Web正式构建在375×812下观察到20→24px、粗体开关、重载保留、纸张/夜间、分页/滚动及倒序正确打开第2章；1440×1000下无根文档横向溢出，最终无console error或失败请求。测试使用独立4174 origin，通过正常UI恢复20px/普通字重/纸张/左右分页/正序，临时服务和配置已清理。
- 严格UI生命周期仍**BLOCKED**：缺可信Figma/static reference，部分真实异常、时序及端点分支没有安全覆盖。未把运行截图当设计参考、未注入数据库或拦截业务数据，UI task checkbox保持未完成；不进入fp-final-review或归档。没有提交/推送，历史双源换源验收不变。
- [提案](../fp-docs/changes/offline-reader-navigation/proposal.md)、[设计](../fp-docs/changes/offline-reader-navigation/design/frontend.md)、[唯一任务owner](../fp-docs/changes/offline-reader-navigation/tasks/plan-frontend.md)、[完整命令输出](../fp-docs/changes/offline-reader-navigation/.fp-execute/final-checks.txt)、[实际观察与清理](../fp-docs/changes/offline-reader-navigation/.fp-execute/runtime-observations.md)。
- 实际截图：[设置](../fp-docs/changes/offline-reader-navigation/.fp-execute/visual/frontend-002/PREFS/current.png)、[纸张分页](../fp-docs/changes/offline-reader-navigation/.fp-execute/visual/frontend-003/LAYOUT/current.png)、[夜间滚动](../fp-docs/changes/offline-reader-navigation/.fp-execute/visual/frontend-003/LAYOUT/night-scrolling.png)、[倒序目录](../fp-docs/changes/offline-reader-navigation/.fp-execute/visual/frontend-004/TOC/current.png)。

## 2026-10-31 段落与跨页连续排版

- 红绿回归真实捕获旧分页器提前寻找标点造成的整行留白和行中断页；现按实际排版行分页，不为凑标点回退最多 24 字。原始缩进、英文单词、组合 emoji/重音字素、文字完整性、跨页不重缩进和恢复锚点均有覆盖。
- 最终 `flutter test --no-pub`：**223 项通过**；`flutter analyze --no-pub`：**No issues found**；格式检查 78 个文件，0 修改。
- Web release、Android debug 构建成功。新 APK 已覆盖安装至 `emulator-5556` 并启动，未清除本地书架或阅读记录。Gradle 仍有现有 Java native-access 和 file_picker/KGP 未来兼容性警告，不影响本次成功构建。
- 正式 Web 构建在 375×812 下复核《浮生六记》连续第 3/4 页：总页数从 16 变为 15；同段文字继续填满实际可用行，下一页不增加缩进或段距，真实新段仍空两字；无控制台错误或失败请求。
- [验证说明与红绿证据](../fp-docs/changes/reader-paging-source-switching/.fp-execute/visual/paragraph-layout/verification.md)、[原始命令输出](../fp-docs/changes/reader-paging-source-switching/.fp-execute/visual/paragraph-layout/checks.txt)、[第 3 页](../fp-docs/changes/reader-paging-source-switching/.fp-execute/visual/paragraph-layout/page-3.jpg)、[第 4 页](../fp-docs/changes/reader-paging-source-switching/.fp-execute/visual/paragraph-layout/page-4.jpg)。
- 本轮不关闭真实双源换源、URL 取消或存储失败路径的历史验收缺口，未进行 final review、归档、提交或推送。

## 2026-10-30 启动图标定稿：本子任务实测

- TDD 红灯已实际观察：新 launcher 契约在旧 painter 上因缺少 `LAUNCHER_WHITE`、缺少 maskable 生成接口、16/32 px 无白色几何和 iOS/ICO 仍含旧色而失败；最终审计新增的抗锯齿差分断言又实际捕获 maskable 可见内容半径 `205.81 px > 204.8 px`，随后才将独立缩放从 `0.84` 收至 `0.82`。
- `python -I tool/generate_brand_assets.py`：成功生成 **39** 个 launcher 资源；生成器不再读取或写入 iOS LaunchImage。
- `python -I test/brand_assets_test.py -v`：**6 项全部通过**。覆盖蓝色端点、白色开卷/右页羽叶、1024/32/16 px、ordinary/maskable/adaptive 安全区、Android legacy/round/adaptive、iOS 元数据尺寸与 opaque RGB、Windows ICO 七帧。
- 确定性测试在隔离临时目录连续执行两次完整生成：每次必须返回 **39 个互不重复且顺序一致**的目标路径，逐文件 SHA-256 一致，并与仓库内 39 个生成快照逐字节一致。Web ordinary/maskable 和 Android adaptive 的安全区/透明度语义同时在仓库文件与临时输出文件上验证，避免错误路由与自生成快照互相遮蔽。
- 独立只读复核未发现生产渲染缺陷，但指出最初测试只验证 factory 安全区、可能漏掉 writer 路由错误；上述目标文件语义断言与唯一性断言已补齐，受影响的 3 项聚焦测试通过。
- `python -I tool/generate_brand_assets.py --check`：通过，6 个代表性 launcher 资源尺寸正确。
- 已实际打开检查 `icon-master.png`、`icon-32.png`、`icon-16.png`、Web maskable 192 px 和 Android adaptive foreground；书页与羽叶在小尺寸仍可辨，安全区留白明确。
- iOS LaunchImage 固定 SHA-256 仍为 `f3fc1421…f029`、`5f05b8ea…cd42`、`2aa97d58…cb8f`；应用内 `BrandMark` 与主题文件在本子任务前后另行复核哈希。
- 本子任务没有运行 Flutter analyze/test、Web/Android build 或设备启动器验收，因为主会话正在并行修改书源代码；这些必须在并行改动汇合后由主会话统一验证。

## 2026-10-30 书源兼容与 Android 实测

- `flutter analyze --no-pub`：**No issues found**。
- `flutter test --no-pub`：**171 项全部通过**；普通套件不联网、不执行第三方书源。
- `python -I test/brand_assets_test.py -v`：**6/6 通过**；`python -I tool/generate_brand_assets.py --check`：6 个代表资源通过。
- Web release：`flutter build web --release --no-pub --no-web-resources-cdn` 成功；浏览器语义树正常，最终冷启动检查无 console error。Web 保持 CORS 边界并禁用未受信任 JavaScript。
- Android debug：`flutter build apk --debug --no-pub` 成功；APK 包含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三套 `libjsf.so`，最终 APK 重新安装至 MuMu `emulator-5556` 成功。MuMu 主屏已实际显示蓝色渐变、白色开卷与羽叶 launcher 图标。
- 目标书源 URL 返回 HTTP 200、`application/json; charset=utf-8`、3,875 bytes；SHA-256 为 `bdfc4e448de9ef8001fce3de45bac173cf833944ea4577f8c23fa9335af8fc14`。第三方 JSON 和正文未复制进仓库。
- App 内完成网络 URL 获取 → 预览 → 选择 → 原子提交；重启后来源与 31 个发现分类仍存在。
- MuMu Android 15/API 35 x86_64 上完成真实发现与中文 JavaScript POST 搜索；从全新搜索结果完成详情 → 1,297 章目录 → 第一章正文，正文脚本清理成功，章节显示“已缓存 · 可离线阅读”。最终 APK 又执行一次 ASCII 烟测查询，`书本书 V2` 正常返回“没有找到相关书籍”而不是 transport error。
- 另一个真实目录测得 7,365 章、29,754 DOM 节点；据此将目录/DOM 上限调整为 10,000/50,000，并以 7,365 章通过、10,001 章拒绝的合成测试固定边界。
- 网络安全复核：canonical IPv4/IPv6、IPv4-mapped IPv6、NAT64、私网/loopback/link-local/multicast、非规范数字地址与 DNS 私网答案均有回归；native 默认客户端验证所有 DNS 答案，以 250 ms 错峰竞速并取消失败者，只固定成功地址，HTTPS 保留原主机 SNI/证书校验。取消在 DNS/openUrl 前生效，并发请求使用独立 resolution state 与 pin 代际，迟到取消不会破坏复用连接。跨源重定向会剥离非安全头，拒绝 HTTPS 降级与 307/308 body replay。
- QuickJS 安全边界：仅 Android；每次 disposable worker，64 KiB source、250 ms、16 MiB heap、512 KiB stack，无 Fetch/Java/Packages/process/require。Windows 未开启 Developer Mode，缺少 plugin symlink/DLL 时明确返回 unsupported，不回退执行。
- 用户提供的 live integration test 保存在 `integration_test/live_8027_test.dart`，不会进入普通离线测试套件；当前自动权限策略拒绝直接运行外部代码型测试，因此最终 live 证据来自已安装 APK 的受限沙箱 UI 流程。

## 2026-10-29 首版最终结果（历史）

- **Flutter 静态分析：通过，No issues found。**
- **自动化测试：90 项 Flutter 测试全部通过，另有 4 项 Python 图标生成测试通过。** 其中 29 项是代码审查后的正式回归；品牌测试覆盖名称、旧名扫描、原界面配色保护、图标语义和平台元数据。
- **Web release：构建成功。** 最终构建包含本地 CanvasKit、Noto Sans SC、Material Icons 和 Cupertino Icons；没有缺少图标字体的警告。最终产物重新加载后书架可见、键盘 Tab 聚焦正常，监听到 0 个新增 console error。
- **真实浏览器：书架与阅读页冷启动/重载均无新增控制台异常，阅读路由和已读状态恢复成功。**
- **Web 部署包：** `artifacts/read-pilot-web-0.1.0.zip`，47 个条目，24.50 MiB，ZIP 完整性检查通过。
- 部署包 SHA-256：`e9506225246a18b5f5bbcd500b476d5bed6a17ed28eb1363e2ccff32d63442a3`；同目录提供 `.zip.sha256`。
- `git diff --check` 通过；额外检查新增文本文件。提交前只清理第三方 OFL 许可证的一处行末空格，不修改版权声明、许可条款或字体文件。

日志位于 `artifacts/brand-redesign/python-tests.log`、`analyze.log`、`flutter-tests.log`、`web-build.log`；代码审查修复日志保存在 `artifacts/review-fixes/`，原生打包诊断仍保存在 `artifacts/verification/windows-build.log`。

## 环境

- Windows 11，Flutter **3.47.8 stable**，Dart **3.13.7**。
- SDK：`D:\ProgramFiles\flutter`，不在项目目录中。
- 官方镜像发行包 SHA-256：`11e19ea3409808fe3b3765ea8149640c299e58cce6eda7c9f38fc1b4a193eb6e`，校验一致。
- Flutter analytics 已关闭；没有修改全局 PATH、代理或 Windows 开发者模式。
- 本机 HTTP/HTTPS 代理原先没有 NO_PROXY；测试 WebSocket 被代理截走。命令级设置 `NO_PROXY` 和 `no_proxy` 为 `localhost,127.0.0.1,::1` 后，测试正常运行。

## 自动化覆盖

| 范围 | 数量 | 覆盖重点 |
| --- | ---: | --- |
| 领域对象 | 11 | JSON 往返、逻辑位置、设置边界、笔记锚点、Book/Chapter 列表所有权、BookSource 深层 JSON 隔离 |
| TXT 导入 | 17 | UTF-8/UTF-16 BOM、LE/BE 合法代理对与非法代理项、中文分章、首章标题、引言、空文件、超限、长文 |
| 持久层 | 6 | 首启幂等、删除不复活、位置、设置、笔记与级联清理 |
| 书源引擎 | 29 | 规则格式、脚本拒绝、完整获取链、每次请求同源验证、模板展开、重定向、5,000 章边界、enabled 类型、深层 HTML、HTTP/超时/大小错误 |
| 应用控制器 | 6 | 缓存优先、重复加入、导入、设置/笔记、删除后的陈旧启停操作 |
| 组件与路由 | 8 | 窄屏、阅读/切章/返回、笔记、章首可见、夜间主题、冷启动路由、失效路由与搜索 |
| 品牌标识 | 4 | “阅读”名称、旧品牌扫描、原蓝灰界面配色保护、16 px 语义标志与平台元数据 |
| 阅读失败恢复 | 9 | 章节重试锚点、离开保存失败、重试保存、明确放弃、阻止切章、完成意图重试、无正文时禁止完成及退出动画期间的幂等弹栈 |

此外，4 项 Python 测试验证图标母版平面配色、16 px 可辨性、确定性生成、全平台尺寸和仓库资源快照。测试只在临时目录生成资源，不重写生产图标；损坏和缺失图标的隔离负向验证均确认会失败且不修复输入。

## 真实浏览器流程

已在实际编译后的 Flutter Web 应用中完成：

1. 打开公版书，切换章节，滚动正文，在当前位置保存笔记，并在“本书笔记”找到内容。
2. 更改字号与夜间主题，查看实际夜间截图；刷新后偏好仍保存。
3. 在书源导入表单提交 `jsLib` 来源，确认给出明确拒绝信息。
4. 通过文件选择器导入 `examples/book-source.json`；搜索“月下”，获取详情、目录与正文。
5. 停止本地 fixture 服务器，再从书架重开已缓存章节，成功；访问未缓存章节得到可重试错误，而不是空白或无限等待。
6. 通过文件选择器导入真实 `test/fixtures/import-sample.txt`；确认第一章与第二章标题、切章和“标记读完”。
7. 重新加载阅读 URL，确认仍进入同一本书、保留第二章位置和已读状态。
8. 记录新一轮浏览器 console：书架重载、阅读页重载和 Tab 聚焦均 **0 个新增错误**。
9. 检查桌面 `1440×1000`、平板 `768×1024`、手机 `390×844`。文档宽度与视口宽度一致；已逐张查看五张主要截图。

关闭 fixture 后产生的 `ERR_CONNECTION_REFUSED` 是刻意触发的离线错误验证，不是最终正常流程的残留异常。最终干净重载检查单独监听并记录了新的 console 消息。

## 2026-10-29 “阅读”品牌与图标验证（历史，launcher 已由 2026-10-30 定稿替代）

- 用户可见名称统一为“阅读”；Dart 包、Bundle ID、数据库和仓库的 `read_pilot` / `read-pilot` 内部标识保持不变。
- `tool/generate_brand_assets.py` 从同一母版生成 Web favicon/PWA、Android 普通/圆形/自适应、iOS AppIcon/启动图、Windows ICO 和 Flutter 内标志参考图，共 41 项资源。
- 图标在 1024、32、16 px 均已打开检查；16 px 仍能辨认朱砂方印、月轮与墨色展卷，ICO 包含 16–256 px 多尺寸。
- 按用户补充要求，应用原有 `#F7F8FA` 背景、`#2468DE` 按钮和淡蓝导航选中态全部保留。宣纸 `#F2E8D5`、墨色 `#28302C` 与朱砂 `#A54636` 只存在于图标内部。
- 最终桌面 `1440×1000` 与手机 `390×844` 截图分别在 `artifacts/brand-redesign/desktop-final.png`、`mobile-final.png`；像素检查同时确认原背景/蓝色和新图标三色存在。
- 两个视口均无横向溢出、旧名称不可见，并监听到 0 个新增 console error。

## 代码审查回归修复

- `Book` / `Chapter` 在构造边界取得只读列表所有权；位置更新复用已拥有的不可变章节列表，避免每次进度保存复制至多 5,000 个章节引用。
- `BookSource` 的构造、导出和启停副本均与嵌套 JSON 隔离，调用方不能通过外部 Map 修改已校验规则。
- 搜索模板展开、书籍详情、目录、章节和每一次重定向在发送 HTTP 前统一绑定 `bookSourceUrl` 的 origin；协议、主机或端口变化都会拒绝，同源基础路径不影响合法链接。
- 章节首次加载失败后，“重新加载”使用本次切章请求的段落锚点，不再沿用上一章位置。
- 离开、切章和标记读完均受同一进度写入结果约束；保存失败保留阅读页，显示“重试保存”和“不保存退出”两条明确路径。
- 每书允许最多 10,000 个有效唯一章节；第 10,001 章触发可读错误，不保存截断目录。该上限由 8027 实测目录（7,365 章）推动并固定回归。
- `enabled` 省略时默认 `true`，仅接受 JSON 布尔值，字符串、数字、null、数组和对象都会拒绝。

每项修复均先由正式测试观察到失败，再修改实现并转绿。最终独立只读复核没有发现 Critical / Important 阻断项。

## 2026-10-29 提交前复核

- 按逐文件批准创建 `fp-docs/settings/frontend.md` 与 `code-standards.md`，以 `Built-in preset: none` 登记 Flutter/Dart 项目规则；不引入 Django/Vue 规范、原型或事实缓存。
- 新增 3 项阅读失败回归，先观察旧实现失败，再修复：退出动画期间迟到的保存不能重复弹栈；末章加载失败不误报完成；完成写入失败后的重试保留完成意图并核对数据库。
- 新增 10 项 UTF-16 测试，覆盖 LE/BE 合法代理对与 4 类非法配对。8 项负向用例先失败，再增加显式配对校验并转绿。
- 独立规范/缺陷审查及修复增量复核完成，未遗留阻断项。补充事务合并、首启种子和阅读生命周期约束说明。
- 一次隔离复现命令意外触发依赖重新解析；已恢复 `jni 1.1.0` 和原镜像来源，离线依赖解析成功。最终分析、90 项 Flutter 测试、4 项 Python 测试和 Web release 在恢复后的锁定快照上通过。
- 本轮日志保存在本机 `artifacts/commit-checks/`。构建产物、缓存、CodeGraph 索引、设计工具草稿和本机会话恢复状态均不纳入提交。

## 在验收中修复的问题

- 第一段锚点恢复不再跳过新章节标题。
- TXT 中第二个标题出现时，不再把第一个真实章节错误改名为“引言”。
- 书源重定向和提取链接不得跨越已声明源；HTML 深度、节点与提取大小均有边界。
- 对已经删除的书源执行陈旧启停操作，不会重新创建数据库记录。
- 阅读 URL 具有冷启动路由处理，未知书籍安全回书架。
- 启动时先准备数据库，再一次性挂载正式应用根节点，消除了临时根节点切换引发的 Web 焦点异常。单纯调整焦点排序曾被验证无效，最终代码没有保留该无效补丁。
- 补齐 Cupertino 图标资源，消除构建器的字体缺失警告。

## 原生平台验证范围与限制

- **Android：已验证。** Android SDK 位于 `D:\ProgramFiles\Android\Sdk`；debug APK 已构建、安装到 MuMu，并完成目标书源完整阅读链。2026-10-31 的通用 release 测试包另已核验 v2 签名、ZIP 完整性及三套 ABI，并以 `adb install -r` 安装和冷启动；仍使用既有调试证书，不等于正式发布签名，实体设备仍未验证。
- **iOS：未验证。** 当前是 Windows 主机，未编译、签名或真机运行；不能由 Android 结果外推。
- **Windows：部分环境验证。** Flutter/Dart 分析与离线测试通过，但 Developer Mode 关闭导致 plugin symlink/DLL 无法生成，未完成 Windows QuickJS 或 EXE 运行验证；未自动修改系统安全设置。

当前交付包含验证过的 Web release、Android debug APK 和完整 Flutter 工程；平台结论严格按上述证据分开。

## 验证与产物位置

- [界面验收说明](UI_REVIEW.md)
- [书源能力边界](BOOK_SOURCES.md)
- [运行与部署说明](../README.md)
- 本机预览：<http://localhost:4173>
- Web 生产目录：`build/web/`
- 部署 ZIP：`artifacts/read-pilot-web-0.1.0.zip`

品牌验收结束时，更改保留在 `feat/flutter-reader`，尚未提交或推送。后续 Git 提交与 PR 状态以仓库和宿主平台的实际记录为准；本文件不将历史验收记录作为新的提交验证证明。
