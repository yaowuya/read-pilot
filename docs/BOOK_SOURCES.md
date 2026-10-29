# 书源格式与边界

阅读实现 **Legado 声明式 CSS 子集 v1**，不是完整的 Legado 引擎。格式参考 [HapeLee/legado-with-MD3](https://github.com/HapeLee/legado-with-MD3) 的公开数据定义；Dart 解析器独立实现，没有复制或逐行翻译 Kotlin 源码。

## 支持

- JSON 对象或对象数组；`ruleSearch`、`ruleBookInfo`、`ruleToc`、`ruleContent` 也可为编码后的 JSON 字符串。
- `bookSourceUrl`、`bookSourceName`、`bookSourceType: 0`、`enabled`、`searchUrl`。`enabled` 省略时默认为启用；提供时必须是 JSON 布尔值，字符串 `"false"` 等错误类型会拒绝导入。
- 显式 `@CSS:`（不区分大小写）及普通单个 CSS 选择器。
- 选择器末尾 `@text`、`@ownText`、`@textNodes`、`@html` 或 HTML 属性名，例如 `@href`、`@src`。
- `@text` / `@href` 直接从当前选中的目录节点提取。
- 单页搜索、单页书籍详情、单页目录、单页章节；HTTP(S) GET、UTF-8。每本书最多 5,000 个有效章节；超限会明确拒绝，不保存静默截断的目录。
- 搜索 URL 中精确的 `{{key}}`、`{{page}}`、`{{baseUrl}}`；关键词安全编码，不执行表达式。
- 相对链接以实际响应页地址解析。搜索模板展开后的 URL、书籍详情、目录、正文链接以及每一次重定向，在发送 HTTP 请求前都必须与 `bookSourceUrl` 的 origin（协议、主机和端口）完全一致。本地服务只在你明确把它配置为书源时可访问。
- HTML 最大深度 128 层、最多 25,000 节点；过度嵌套或展开过大的正文会报错，不继续解析。
- 缓存成功的章节可离线阅读；不会自动抓取整站或全书。

## 不支持且不会静默忽略

JavaScript、`jsLib`、WebView、XPath、JSONPath、`@get`/`@put`、任意模板表达式、旧式 Jsoup 链式/索引扩展、`&&`/`||`/`%%` 组合、`##` 正则替换、POST 与 URL 请求选项、脚本登录、正文解密、付费解锁、自动翻页。依赖这些行为的源会在导入时报出字段与原因，请改写为支持的声明式规则后再导入。

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

请求 15 秒超时、最多 4 次重定向、单次最多 2 MiB；不允许 `file:`、`javascript:` 或原生代码桥。单次导入 JSON 限制 1 MiB。HTTPS 优先；HTTP 来源仅用于用户明确导入的本地/授权内容。Web 运行时仍受浏览器 CORS 约束：来源必须允许应用的 Origin。不要关闭浏览器安全策略；没有“万能代理”。

书源配置、本地书籍、笔记和阅读进度存储在本机。Web 使用 IndexedDB，清理站点数据会删除阅读数据；首版没有跨设备同步与数据导出备份，重要原始 TXT 请自行保留。

## 参考与许可证

调研版本：`bba5c64df32bcc9d23ac2b3f2f717b00b0ea01b9`（2026-10-25）。

- [BookSource.kt](https://github.com/HapeLee/legado-with-MD3/blob/bba5c64df32bcc9d23ac2b3f2f717b00b0ea01b9/app/src/main/java/io/legado/app/data/entities/BookSource.kt)
- [rule 数据结构](https://github.com/HapeLee/legado-with-MD3/tree/bba5c64df32bcc9d23ac2b3f2f717b00b0ea01b9/app/src/main/java/io/legado/app/data/entities/rule)
- [AnalyzeByJSoup.kt](https://github.com/HapeLee/legado-with-MD3/blob/bba5c64df32bcc9d23ac2b3f2f717b00b0ea01b9/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt)
- [AnalyzeUrl.kt](https://github.com/HapeLee/legado-with-MD3/blob/bba5c64df32bcc9d23ac2b3f2f717b00b0ea01b9/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeUrl.kt)
- [上游 GPL-3.0 许可证](https://github.com/HapeLee/legado-with-MD3/blob/bba5c64df32bcc9d23ac2b3f2f717b00b0ea01b9/LICENSE)

如果后续复制或移植上游实现，必须重新评估 GPLv3 对整合作品及分发的要求，不能把“独立实现”的当前说明用于复制后的代码。正式发布还需对书籍授权、站点服务条款和分发地区版权作独立核查。
