# 书源兼容矩阵

本项目以独立 Dart/Flutter 实现兼容 Legado 书源的公开 JSON 格式和可观察行为。导入成功只表示格式可保留；运行实现、平台许可和验证证据分别报告。

## 状态定义

- **格式接受**：字段可解析、保留并再次导出。
- **运行实现**：当前解释器已实现该规则或 workflow。
- **平台允许**：当前平台具备所需安全边界和网络能力。
- **验证证据**：合成 fixture、真实来源或具体设备上的实测结果。

暂未实现的合法字段不得伪装成空结果；格式错误也不得误报为网络失败。

## 参考基线

- `HapeLee/legado-with-MD3`
- commit `b21025d3769ec9c4028514914f3c555a1ba284b8`
- GPL-3.0，仅用于互操作规格研究；实现边界见 [CLEAN_ROOM.md](CLEAN_ROOM.md)。

## 相对 legado-with-MD3 核心差距

对照参考仓公开行为（`WebBook` / `AnalyzeRule` 可观察输入输出）与本仓实现，按三栏区分，避免把「跳过非法规则」说成「已完全兼容」。

| 能力 | 已复刻 | 本轮补齐 | 安全拒绝（保持） |
| --- | --- | --- | --- |
| 书源 JSON 导入/启停/分组/字段保留/健康诊断 | ✓ | — | — |
| 搜索 / 发现 / 详情 / 目录分页 / 正文分页 / 封面同源 / 章节缓存 | ✓ | — | — |
| CSS + legacy、`\|\|` fallback、有界 `##` 替换、XPath 安全子集、JSONPath | ✓ | — | 复杂 XPath / JSONPath 正则函数 |
| `&&` 多选拼接、`%%` 交错合并 | — | ✓ 规则解释器 | — |
| `@put:` / `@get:` 会话变量 | — | ✓ 单次 search/loadBook/loadChapter 有界 Map | 跨书源共享、WebView/登录态变量 |
| `replaceRegex`：`pattern##repl`、`##pattern` 删除、选择器尾部空 `##` | 部分（仅安全 `pattern##repl`；非法曾硬失败后改为跳过） | ✓ 删除式与空 `##` 语义收敛；不安全仍诊断+跳过正文清洗 | 无界/回溯爆炸正则、trust-all 清理 |
| Android QuickJS `@js:` / `<js>` 沙箱 | ✓（Android 验证） | 能力画像与运行态对齐 | Web `eval`、Rhino Java/Ajax、无期限脚本 |
| 换源：并发搜候选 → 目录 → 锚点映射 → 原子写库 | ✓ | — | — |
| `loginUrl` / `loginUi` / Cookie jar / trust-all TLS / 媒体书源 | — | — | ✓ 字段保留 + 能力诊断，不执行 |

「跳过非法 `replaceRegex`」只保证章节仍可读，不宣称广告清洗已与 Legado 逐条一致。

## 当前实现（2026-11-09）

| 能力 | Android | Web | 说明 |
| --- | --- | --- | --- |
| object/array、0–4 类型、未知字段保留 | 已实现 | 已实现 | 导入最多 10,000 个源，原始 JSON 可往返 |
| string/object header | 已实现 | 受浏览器限制 | CR/LF、hop-by-hop header 在联网前拒绝 |
| URL 导入 | 已验证 | 受 CORS/混合内容限制 | paste/file/URL 共用有界解析；先在内存检查并预览，用户明确选择来源子集后一次原子提交 |
| GET/POST/HEAD、form/JSON/raw | 已实现 | 依浏览器 transport | source → 默认 UA → URL options 合并 |
| UTF-8/GBK 请求与响应 | 已实现 | 已实现 | GBK 仅用 whole-buffer codec；未知 charset 明确拒绝 |
| CSS 与 legacy | 已实现子集 | 已实现子集 | CSS、`class.*`、`id.*`、`tag.*`、bare `text/href`、`text.文本@属性` |
| XPath | 安全子集 | 安全子集 | 普通 HTML 上支持元素路径、属性等值/contains、位置、`text()` 与属性；复杂 XPath 仍诊断为未完整兼容 |
| JSONPath | RFC 9535 已实现 | RFC 9535 已实现 | 使用 `json_path`；正则函数因不可终止风险而拒绝 |
| regex/组合/变量 | 已实现子集 | 已实现子集 | `\|\|` fallback、`&&` 拼接、`%%` 交错；有界 `@put:`/`@get:` 会话变量；`replaceRegex` 支持安全 `pattern##替换` 与 `##pattern` 删除；选择器尾部空 `##` 只保留选择器；不安全正则诊断后跳过清洗，不吞正文 |
| 正文段落 | 已实现 | 已实现 | 逻辑段落首行两字几何缩进；续页不重复缩进；HTML `br`/常见实体边界、空段、首部重复章名与相邻重复段安全归一；不默认自动重分段 |
| 搜索/发现/详情/目录/正文 | 已实现 | 安全子集 | 发现分类（`url`/`text`/`button`/`toggle`/`select` 五种 `ExploreKind`，JSON 数组与 `title::url` 旧式写法）、分页、循环检测、去重、取消；跨来源搜索并发上限 16（对齐 Legado `threadCount`），书源声明的 `concurrentRate` 按 `bookSourceUrl` 限速 |
| 目录/正文分页 | 已实现 | 已实现 | 目录最多翻 500 页，到上限或连续 10 页无新章节时保留已解析目录；正文最多读 50 页，到上限保留已取到的正文；目录最多 10,000 章，不静默截断 |
| JavaScript | **Android 已验证** | **禁止** | `jsf`/QuickJS disposable worker；250 ms、16 MiB heap、512 KiB stack；无 fetch/Java/Packages/process/require |
| 登录/Cookie/WebView/媒体/文件/设备 helper | 未实现 | 未实现 | 保留字段并给出能力诊断，不进入核心沙箱 |

## 安全硬上限

- 导入：100 MiB、最多 10,000 个源、JSON 深度 64。
- 单请求：15 秒、4 次跳转、响应 2 MiB。
- workflow：目录最多翻 500 页，到上限或连续 10 页无新章节时保留已解析目录；正文最多读 50 页，到上限保留已取到的正文；跨来源搜索并发 16，书源声明的 `concurrentRate` 按 `bookSourceUrl` 限速。
- DOM：50,000 节点、深度 128；目录 10,000 个唯一章节。
- JSON DOM：25,000 节点、深度 128。
- 脚本：64 KiB source、250 ms、16 MiB heap、512 KiB stack；每次在 disposable worker 中执行。
- 所有跳转重新检查 scheme、userinfo、origin、headers 和私网字面地址。

永久拒绝 trust-all TLS、关闭 CORS、任意文件或 shell、Java/JNI 反射、native library、设备标识、源控制代理/DNS、跨源凭据共享和未授权的 DRM/验证码绕过。

## 8027 目标来源验证

目标 URL：

`https://www.yckceo.com/yuedu/shuyuan/json/id/8027.json`

### 获取证据

- 日期：2026-10-30
- HTTP：`200`
- final URL：与请求 URL 相同
- Content-Type：`application/json; charset=utf-8`
- body：`3,875` bytes
- SHA-256：`bdfc4e448de9ef8001fce3de45bac173cf833944ea4577f8c23fa9335af8fc14`
- 第三方 JSON 与正文未复制进仓库。

### 实测结果

平台：MuMu `emulator-5556`，Android 15/API 35，x86_64。

1. App 内网络 URL 获取并预览成功；识别 1 个来源、静态 `user-agent`/`accept-language`、发现、JavaScript 和正文分页能力。
2. 明确确认后原子提交，重启后来源与分类仍存在。
3. 发现分类真实联网成功并显示远程结果。
4. JavaScript 生成的 POST 搜索以中文关键词成功返回结果。
5. 从全新搜索结果完成详情 → 1,297 章目录 → 第一章正文；正文脚本完成清理，章节已缓存并可离线阅读。
6. 另一个真实目录测得 7,365 章、29,754 DOM 节点，推动安全上限从 5,000/25,000 调整为 10,000/50,000；合成边界测试保留 10,001 章拒绝。
7. Android APK 实际包含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三套 `libjsf.so`。

因此该来源当前状态为：

- retrieval：已取得并指纹化
- format accepted：是
- runtime implemented：Android 上满足该来源实际使用能力
- platform permitted：Android 是；Web 的 JavaScript 否
- verified：**Android 完整链路通过**

Windows 当前未开启 Developer Mode，Flutter 无法生成插件 symlink，故本机 QuickJS DLL 测试只验证“不安全回退被拒绝”；不能把 Android 结果外推为 Windows/iOS 已验证。
