# FeaturePilot Manifest

本文件是“阅读”项目的信息层入口。它只登记规则与资料位置，不替代当前源码、实际验证或用户批准。

Schema: fp-manifest/v2
Generated: 2026-10-29
Project root: `D:/01-code/read-pilot`
FP docs root: `fp-docs/`
Git SHA: 1d928b54a0ea8e49dc282733c749d36c547d750b（初始化基线）
Working tree: dirty（初始化时）

## Precedence

- 当前状态以当前源码和实际命令输出为准，优先于 settings 和 intel 中的历史记录。
- 目标要求以当前用户指令和已批准的变更文档为准。

## Settings Files

| File | Role | Authoritative For | When To Read | Status |
| --- | --- | --- | --- | --- |
| `settings/agent.md` | 轻量工作流适配 | 通用约束与工作流 | 仅通用工作流问题 | missing |
| `settings/frontend.md` | Flutter 前端配置 | UI 实现、规范登记和视觉验收 | 前端技术工作与 UI 改动 | created，2026-10-29 逐文件批准 |
| `settings/backend.md` | 后端配置 | 后端/API 约定 | 实际引入后端后 | not-applicable，当前无生产后端 |
| `settings/code-standards.md` | 项目专属规范 | appRoot 范围内的已证实约定 | 仅由适用应用的 Project rule sources 登记后读取 | created，已由 frontend.md 登记 |
| `settings/prototype-style.md` | 原型风格 | 原型视觉一致性 | 仅原型工作 | missing |

## Code Map

| Provider | Status | Version | Index Path | Last Checked | Use As |
| --- | --- | --- | --- | --- | --- |
| CodeGraph | ready | 1.6.2 | `.codegraph/` | 2026-10-29 | navigation-hint-only |

本轮按用户选择仅建图。首次索引和一次健康检查均成功，检查时没有待同步变化。未安装或升级 CLI，未修改用户级 MCP/instructions，无需因本轮操作重启 Agent。

## Intel Artifacts

| File | Purpose | When To Read | Freshness | Sources |
| --- | --- | --- | --- | --- |
| `intel/project-facts.md` | 可选事实缓存 | 验证门禁或非显然边界 | missing | 仅单独批准 discovery 后创建 |
| `intel/.freshness.json` | 事实缓存 metadata | 实时计算 freshness | missing | 与 project-facts 配套创建 |
| `intel/unknowns.md` | 人工维护的项目未知项 | 有实际登记内容时 | missing | human-owned，按需单独批准 |
| `intel/decisions.md` | 人工维护的项目决定 | 有实际登记内容时 | missing | human-owned，按需单独批准 |

## External Project Docs

| File | Priority | Notes |
| --- | --- | --- |
| N/A | N/A | 初始化时未检测到项目级 CLAUDE.md、AGENTS.md、GEMINI.md 或 Cursor 指令文件；不复制用户级指令 |

## Critical Unknowns

- Android、iOS 和 Windows 安装包尚未验证；Web 验证不代表原生端验证。
- 原型基座未初始化，未批准 discovery；不存在相应产物，不将其作为生产功能的前置条件。

## Consumption Rules

- 首先读取本 manifest 作为索引，不批量读取全部 settings 或 intel。
- 根据 When To Read 只拉取当前问题所需的最小资料集。
- generated intel 和 Code Map 仅作导航提示，不作当前行为或完成证明。
- 修改前读取当前源码；验证通过的声明必须来自重新执行的命令。
- 引用路径缺失时，依赖该路径的历史结论失效。
- freshness/conflict 必须由当前源码、正文和 metadata 实时计算，不信任存储的结论。
- 前端工作读取已存在的 `settings/frontend.md`；原型工作另读已存在的 `settings/prototype-style.md`。
- 后端工作仅在确有后端和相应登记时读取 `settings/backend.md`。
- 技术规范的选用和登记由 fp-init 管理；不存在的可选文件不自动补建。
