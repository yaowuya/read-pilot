# 实施进度

## 2026-11-07 书架顶部与分组内书籍操作

- 去掉手机端全局 AppBar（图标 + 「阅读」）：各页面本来就各有自己的头部，顶部再压一条品牌栏只是重复产品名。`SafeArea` 改为 `top: true`，内容直接顶到状态栏下方；宽屏侧栏的品牌区保留。
- 删除书架页脚「书与阅读记录，安心留在本机。」整块，网格直接衔接底部导航。
- 修掉一个真实缺陷：分组内的书无法退回默认书架。书籍更多操作菜单只有「移出书架」（会连正文、进度、笔记一起删），没有只解除归属的入口。现在分组作用域里多一项「移出分组」，走 `setShelfGroupMembership(groupId, bookId, false)`；「全部书籍」里不显示这一项。
- 搜索胶囊去掉右侧「书城」按钮与分隔线（底部导航已有「发现」），输入框吃满整条胶囊。hint 原来比输入框中心高 6.5px —— `isCollapsed: true` 把输入框压成 20px，hint 仍按主题的 1.65 行高排；改成 `isDense: true` + `contentPadding: EdgeInsets.zero` 后偏差为 0。
- 测试：`test/bookshelf_layout_test.dart` 新增「组内移出分组只解除归属」「胶囊 hint 垂直居中且没有书城」两条；`test/app_widget_test.dart` 的「阅读」标题与品牌标志断言随 AppBar 删除同步调整。
- 全量 `flutter test` 640 项通过 / 1 项跳过；`dart format` 153 文件 0 修改；`flutter analyze` 无问题。
- MuMu 安卓 15 真机确认：书架顶部无品牌条、胶囊文字居中且无书城、底部说明行消失、组内菜单出现「移出分组」、点击后该组变为 0 本而「全部书籍」仍是 5 本。APK 为 `read-pilot-v0.1.0-beta9.apk`。

## 2026-11-07 书架参考微信读书改为分组卡片

- 用户要求书架布局参考微信读书，并先出草稿图确认；草稿在 `docs/drafts/bookshelf-layout-draft.html`，用户就三点拍板：无分组时退回平铺网格、只做排序不做「在读/已读」筛选、组卡角标显示「在读 N」。
- 有分组时书架首层是分组卡片：组内前四本拼成 2×2 封面墙（固定 205:268 比例，不足四本留白而不是拉伸），右上角「在读 N」，卡下是组名与总本数，最后一张是「新建分组」占位卡。点「全部书籍」进全部书，点分组卡进组内；组内标题行左侧是返回箭头，右侧仍能管理分组。没有分组时退回原来的平铺书籍网格。
- 搜索框改成胶囊样式，把「书城」收进同一个胶囊；「全部/在读/已读」三个筛选 chip 与排序下拉合并成一行排序 tab（默认 / 进度 / 书名 / 分类）+ 网格列表切换，为书架主体腾出空间。「进度」把在读的排前面，其次按进度降序。
- 新增 `test/bookshelf_layout_test.dart` 5 项（无分组平铺、卡片层与进组、全部书籍与在读计数、搜索出书不出卡、四个排序 tab 的顺序），并改写 `test/bookshelf_groups_test.dart` 3 项到新语义。
- 全量 `flutter test` 638 项通过 / 1 项跳过；`dart format` 153 文件 0 修改；`flutter analyze` 无问题。
- MuMu 安卓 15 真机逐屏确认：卡片层（「全部书籍」5 本 + 在读 4 角标、空组占位、新建分组卡）、进组空态、返回、全部书籍、进度/书名/分类排序、搜索无结果、列表切换。APK 为 `read-pilot-v0.1.0-beta8.apk`。

## 2026-10-31 本地提交前复核

- 本轮用户明确要求本地提交；此前开发阶段“不提交”的限制不再作为本次 Git 动作终点，但没有授权推送、PR、最终审查或归档。
- 修复换源歧义映射、未验证预取目标、迟到正文/进度与阅读绑定失效，以及设置保存、短高度回退、文字缩放和标题去重的边界；正式回归覆盖相关失败状态。原子导入保存开始后禁用取消，准备阶段仍可取消且不写入。
- 当前快照 275 项 Flutter 测试、6 项 Python 图标测试、静态分析及 81 文件格式检查通过；Web release、Android release 构建与新 APK 签名/完整性检查通过。依赖锁未变；旧交付 APK 未覆盖，MuMu 未重新安装。
- 正式 Web 实测点击翻页及短视口滚动后恢复新逻辑位置，无控制台错误或失败请求；导入文本适配未成功，不计为真实导入成功。完整记录见 [构建与验证](VERIFICATION.md#2026-10-31-本地提交前复核)。
- 严格视觉/完整 E2E 与历史双源换源仍为 BLOCKED；任务 checkbox 不作虚假完成。APK、截图、索引及机器恢复状态排除在提交外。

## 2026-10-31 目录与排版偏好迁移

- 已实现目录正序/倒序、段距0–40px（默认20px）及正文加粗（默认关闭），三项偏好随现有设置保存。目录只映射展示顺序，不改原始章节列表、当前章索引或书签。
- 分页、滚动和设置预览共用新段距/字重；分页key同步更新，保持逻辑内容锚点。修复同一弹层保存失败时退回初始旧值的问题，改为恢复最近成功保存值。
- 247项Flutter测试通过，静态分析无问题；格式检查81个文件0修改；Web release、Android debug构建成功，新APK覆盖安装且未清除数据。
- 真实Web在独立4174测试origin观察到设置重载恢复、纸张/夜间、分页/滚动，以及倒序首项正确打开第2章；偏好已通过UI恢复，临时服务/launch条目已清理。
- 严格FeaturePilot视觉/完整E2E门禁仍BLOCKED：缺少静态参考，部分真实故障、时序和边界分支没有安全真实覆盖；不以单测或截图豁免。未进入fp-final-review、归档、提交或推送，历史换源缺口不变。
- 提案/设计/计划与证据在 `fp-docs/changes/offline-reader-navigation/`；每5分钟的恢复检查已停用，避免对已交付但证据受限的任务重复恢复。

## 2026-10-31 阅读分页与来源管理

- 跨页断段修正：移除向前最多 24 字寻找标点的分页退让，改为使用字体排版器的实际行边界用满可用行数；同段续页不加段距、不重新缩进，保留中英文和 Unicode 字素边界。
- 段落规则完善：正文以逻辑段落处理，首行以两字几何缩进展示，续页/视觉换行不重缩进；安全处理 `br`、常见实体、边缘空白、空段、首部重复章名和相邻重复段。新增有界 `ruleContent.replaceRegex`，不默认启用可能破坏原排版的自动重分段。
- 用户反馈修正：应用内品牌标志改为复用已定稿蓝色启动图资源；分页正文顶部收紧到 12 px，标题后 20 px，移除首屏重复离线说明及过度空白预留；支持点击左右各三分之一区域以动画上一页/下一页，中间区域不翻页，原有滑动保留。
- 阅读页新增默认左右分页，可在设置中切换上下滚动；持久化继续采用章节/段落锚点。纸张背景按用户原图采样调整为 `#F4EFDC`。
- 导入移除预览与逐源选择；确认后执行校验和原子提交。文件导入也复用 10 MiB 共享限制。
- 新增同名候选搜索、手动换源、章节/笔记映射、安全封面显示及刷新；切源和封面写入保护并发进度、已删除书籍和迟到正文。
- 正文自动规范化空白、空段、相邻重复和首段重复标题；展示使用两字缩进与两端对齐，不按关键词猜测删除正文。
- 换源真实环境验收尚未通过：8027 可搜索和加载，1325 的“追书看ws”站点连接失败，无法取得替代源；Web 另受目标服务 CORS 限制。不得将单元测试结果冒充完整 Legado 功能或双源实测通过。
- 本轮验证：223 项 Flutter 测试、静态分析、Web release、Android debug 构建通过；新 APK 覆盖安装且未清除数据。375×812 实测连续第 3/4 页已按行衔接，截图与日志见 `docs/VERIFICATION.md` 最新记录。
- 当前执行证据见 `fp-docs/changes/reader-paging-source-switching/.fp-execute/progress.md`。尚未执行 final review、归档或 Git 提交。

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