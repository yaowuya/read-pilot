# 书源引擎洁净重实现说明

## 目标

本项目保持 MIT 许可，以 Dart/Flutter 独立实现 Legado 书源公开格式和可观察行为。研究对象固定为 `HapeLee/legado-with-MD3@d5f4bebb8ddc1e84a590cce0ceaf566481c3c0e7`。

## 允许的互操作依据

- JSON 字段名、外部规则语法和 URL options。
- 可观察的输入、输出、错误类别和执行顺序。
- HTTP、CSS、XPath、JSONPath、正则、JavaScript 等公开标准。
- 公开 helper 的接口含义，用原创 DTO、算法和测试重新实现。

## 禁止复制

- 不逐行翻译 Kotlin/Java/Rhino 实现。
- 不复制上游内部控制流、算法、错误文案、测试、fixture、文档或资源后改名。
- 不链接或分发 GPL 引擎却继续声称当前应用是独立 MIT 实现。
- 不复制上游 trust-all TLS、全局 Cookie/header 泄漏或无限制平台 bridge 等不安全行为。

研究材料只转化为非代码行为规格和原创合成测试。若需要法律意义上的严格 clean-room，研究者与实现者还需组织隔离并接受独立法律审查；本说明不构成法律意见。

## 安全偏差

兼容性不包含下列上游行为：

- 跳过证书/主机名验证。
- 任意 Java/JNI/文件系统/设备/UI 访问。
- 源自定义代理、DNS 或跳过限流。
- 无授权的跨域凭据继承或 Cookie 共享。
- 不能中断、不能限制内存的脚本执行。

这些能力即使出现在源中，也应作为字段保留并产生能力诊断，而不是静默执行。

## 独立依赖与平台边界

- `json_path 0.9.0`：MIT，作为 RFC 9535 JSONPath 基线；会触发不可终止正则的 `match/search` 函数在当前安全子集中拒绝。
- `charset 2.0.1`：Apache-2.0，只使用 whole-buffer GBK 编解码并以固定字节 golden test 验证；不使用其 streaming codec。
- `jsf 1.2.1`：MIT，Android 使用 QuickJS worker 的 deadline、heap 与 stack 上限；不注册 Fetch、模块或 host callback。
- Web 上 `jsf` 不提供同等 hard timeout/heap/stack 边界，因此未受信任脚本始终禁用，不降级为浏览器 `eval`。
- 普通 HTML XPath 没有适合当前 Dart 的维护中 permissive adapter；本项目只实现由原创测试覆盖的安全子集。严格 XML/XHTML 可在有真实需求时另行评估 MIT `xml` 包，不为假设需求预装。

用户提供的 `8027.json` 只作为外部验收数据；仓库记录 URL、HTTP 元数据和 SHA-256，不复制其 JSON、规则或正文。

## 原创测试来源

`test/fixtures/source_runtime/` 中的网页、JSON、请求响应与规则必须由本项目原创，覆盖：

- 静态 header 才能访问的完整阅读链。
- GET/POST/HEAD、form/JSON/raw body 与 charset。
- 同域/跨域重定向和敏感头剥离。
- CSS/legacy/XPath/JSONPath/regex/组合规则。
- 目录/正文分页、循环、去重、取消和预算。
- 沙箱脚本的无限循环、内存、权限和状态隔离。

真实第三方书源只作为用户提供、明确授权的端到端目标，不随项目捆绑。
