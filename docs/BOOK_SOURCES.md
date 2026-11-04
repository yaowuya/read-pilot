# 书源格式与边界

阅读以独立 Dart/Flutter 实现支持 Legado 书源 JSON 的部分能力，不是完整的 Legado 引擎。格式参考 [HapeLee/legado-with-MD3](https://github.com/HapeLee/legado-with-MD3) 的公开数据定义，没有复制或逐行翻译 Kotlin 源码。导入成功仅表示格式可保留；字段的运行实现、平台许可和实际验证分别报告，完整边界见 [书源兼容矩阵](SOURCE_COMPATIBILITY.md)。

## 支持

- JSON 对象或对象数组；规则组也可为编码后的 JSON 对象字符串。未知字段保留并可往返序列化；空的 `ruleReview: []` 兼容为缺省评论规则，非空数组仍拒绝。
- `bookSourceUrl`、`bookSourceName`、0–4 类型和 `enabled` 可保留；当前阅读流程面向文本书源。`enabled` 省略时默认启用，提供时必须是 JSON 布尔值，字符串 `"false"` 等错误类型会拒绝。
- CSS、已实现的 legacy 选择器、`@text` / `@ownText` / `@textNodes` / `@html` 和属性提取；安全 XPath 子集、JSONPath、有界正则替换及 `||` fallback 的范围见兼容矩阵。
- HTTP(S) GET/POST/HEAD、form/JSON/raw 请求体、静态及 URL option headers、UTF-8/GBK 编解码；不把格式可解析等同于任意请求或脚本均可运行。
- 搜索、发现、详情、目录和正文；目录最多翻 500 页，连续 10 页没有解析到新章节即视为已到底，到达上限时保留已解析的目录继续阅读，不整本书报错；正文最多读 50 页，到上限保留已取到的正文继续阅读，不整章报错；每本书最多 10,000 个有效唯一章节，超过章节上限同样明确拒绝，不保存静默截断的目录。
- 搜索模板中的 `{{key}}`、`{{page}}`、`{{baseUrl}}` 按声明式规则展开；任意表达式不因此获准执行。Android 已有的限定脚本入口另按平台许可及沙箱规则处理。
- 相对链接以实际响应地址解析；搜索、详情、目录、正文和封面请求，以及每次重定向，都必须满足书源的同源策略和地址检查。默认拒绝本机、私网及不安全目标，不使用公共代理绕过限制。
- HTML 最大深度 128 层、最多 50,000 节点；JSON DOM 最多 25,000 节点、深度 128。过度嵌套或展开过大的页面会报错，不继续解析。
- 已缓存章节可离线阅读；不会自动抓取整站或全书。粘贴、文件与网络 JSON 导入共用 100 MiB、10,000 个源及 JSON 深度 64 的限制；聚合书源里个别无法解析的条目会被跳过并在预览中按原因计数，但整批不可解析、超过条目上限或结构损坏仍整体拒绝。检查阶段不写库，用户明确选择来源子集后一次原子提交。

## 正文段落与替换

正文先按真实换行和 HTML `br` 边界形成逻辑段落，再进入阅读布局：

- 段首和段尾的半角、全角、NBSP、Tab、BOM 等空白会归一；空段会移除。段内不额外压缩空白数量，Tab 和 NBSP 归一为普通空格，不合并原有逻辑换行。
- 文本形式的 `<br>`、`&nbsp;`、`&amp;`、`&lt;`、`&gt;` 和 `&quot;` 会做轻量语义归一。完整 HTML 仍应使用 `@html`，由安全 DOM 提取处理。
- 比较时归一大小写和空白，但保留标点：只去除正文开头与章节标题一致的独立段落，并合并相邻重复段。后续正文即使与章名相同，不会被删除。
- 阅读器对每个逻辑段落的首行使用两个汉字宽的几何缩进；原始空格不会叠加，视觉换行及跨页续段不会重新缩进。分页按字体排版器的实际行边界用满可用高度，不为向前寻找标点而提前断页；段间距只用于真实段落结束。缩进只属于展示层，不写入章节缓存、书签或阅读位置。
- 可选 `ruleContent.replaceRegex` 使用单条 `正则##替换文本`。它在整章文本上、段落归一之前执行，支持 `$1` 等捕获组替换。正则模式限制在安全子集，输入最多 262,144 个、输出最多 2,097,152 个 UTF-16 代码单元，最多 10,000 次匹配；不安全格式会在请求前明确拒绝。

不会默认开启“自动重分段”：这类启发式会合并原换行、删除段内空白、重写引号或强制切句，可能破坏诗歌、英文与原书排版。全局/按书的替换规则管理界面也不在当前版本范围。

## 未实现或平台禁止的能力

登录、持久 Cookie、WebView、正文解密、付费解锁、媒体/设备 helper、任意脚本桥，以及未确认语义的 `&&`、`%%`、`@get`/`@put` 等组合，仍不作为可执行能力。合法字段可以保留并给出能力诊断，不等于会在导入时执行，也不保证相关来源可运行。

Android 已有的 `searchUrl <js>` 与 `ruleContent @js:` 仅在受限 QuickJS worker 中执行，具有时间、堆和栈预算，不提供网络、Java、文件或 shell 桥。Web 不执行来源脚本，Windows/iOS 未验证平台也不回退执行。`jsLib` 或其他脚本字段不能借此获准作为通用脚本运行。具体字段和平台结论以兼容矩阵及能力报告为准。

未使用的说明性元数据可保留并导出，不会被执行。只允许文本书源。没有内置盗版站点、账号凭据或第三方代理。

## 基本形状

```json
{
  "bookSourceUrl": "https://books.example.org",
  "bookSourceName": "我的授权书库",
  "bookSourceType": 0,
  "enabled": true,
  "searchUrl": "/search?q={{key}}&page={{page}}",
  "ruleSearch": {
    "bookList": "@CSS:.book",
    "name": "@CSS:a.title@text",
    "author": "@CSS:.author@text",
    "bookUrl": "@CSS:a.title@href"
  },
  "ruleBookInfo": {"tocUrl": "@CSS:a.toc@href"},
  "ruleToc": {
    "chapterList": "@CSS:#chapters a",
    "chapterName": "@text",
    "chapterUrl": "@href"
  },
  "ruleContent": {"content": "@CSS:article@html"}
}
```

`books.example.org` 只是说明域名，不是承诺可用的在线书库。

## 网络与隐私

请求 15 秒超时、最多 4 次重定向、单次最多 2 MiB；不允许 `file:`、`javascript:` 或任意原生代码桥。单次导入 JSON 限制 100 MiB。HTTPS 优先；HTTP 仅用于用户明确授权且满足地址策略的网络内容，不因此允许本机或私网访问。Web 运行时仍受浏览器 CORS 约束：来源必须允许应用的 Origin。不要关闭浏览器安全策略；没有“万能代理”。

书源配置、本地书籍、笔记和阅读进度存储在本机。Web 使用 IndexedDB，清理站点数据会删除阅读数据；首版没有跨设备同步与数据导出备份，重要原始 TXT 请自行保留。

## 参考与许可证

调研版本：`b21025d3769ec9c4028514914f3c555a1ba284b8`（2026-10-31）。

- [BookSource.kt](https://github.com/HapeLee/legado-with-MD3/blob/b21025d3769ec9c4028514914f3c555a1ba284b8/app/src/main/java/io/legado/app/data/entities/BookSource.kt)
- [rule 数据结构](https://github.com/HapeLee/legado-with-MD3/tree/b21025d3769ec9c4028514914f3c555a1ba284b8/app/src/main/java/io/legado/app/data/entities/rule)
- [AnalyzeByJSoup.kt](https://github.com/HapeLee/legado-with-MD3/blob/b21025d3769ec9c4028514914f3c555a1ba284b8/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt)
- [AnalyzeUrl.kt](https://github.com/HapeLee/legado-with-MD3/blob/b21025d3769ec9c4028514914f3c555a1ba284b8/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeUrl.kt)
- [上游 GPL-3.0 许可证](https://github.com/HapeLee/legado-with-MD3/blob/b21025d3769ec9c4028514914f3c555a1ba284b8/LICENSE)

如果后续复制或移植上游实现，必须重新评估 GPLv3 对整合作品及分发的要求，不能把“独立实现”的当前说明用于复制后的代码。正式发布还需对书籍授权、站点服务条款和分发地区版权作独立核查。
