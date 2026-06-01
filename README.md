**中文** | [English](README.en.md)

# specpowers-flow

## 这是什么

`specpowers-flow` 是一个自包含、跨平台的 skill 插件，提供一条端到端的、规格驱动（spec-driven）的工程工作流——从最初的想法一直到归档进活规格（living spec）。它把 **流程纪律**（显式阶段、强制闸门、对抗式评审、subagent 驱动的 TDD）与 **规格驱动的产物管理**（OpenSpec 的 `proposal/design/tasks/spec-delta` 生命周期，以及"活跃变更 → 归档"模式）融合成一条可审计、可按规模伸缩的闭环。插件以纯 markdown skill 运行——没有运行时代码——并且在 Claude Code 和 Codex 上都能用，不依赖任何外部工具。

```
brainstorm → generate-spec → harden-spec → plan-from-spec → check-coverage → execute-plan → verify-compliance → archive
```

每个箭头都是一道强制闸门。阶段由磁盘上的产物推断得出，没有任何隐藏状态是权威的。闸门证据记录每个被验证产物的内容摘要（digest），因此在某个闸门通过之后再改动任何东西，都会在 resume 时让该闸门及其所有下游闸门失效。

---

## 为什么需要它

有纪律的规格驱动开发需要记住一大堆事：设计前先写 proposal、规划前先对规格做对抗式 harden、写代码前先建覆盖矩阵、每个任务内部都 test-first、归档前跑一次独立的合规评审、再把 spec delta 原子地合并进活规格。一旦全靠脑子记，这些纪律在时间压力下就会被跳过、或在变更中途被遗忘。结果就是：行为没文档、覆盖有缺口、活规格过期、变更"做完了"却从未对照一份书面契约验证过。

`specpowers-flow` 把每一项纪律都编码成一个带闸门、无法绕过的显式阶段：当前闸门不通过，下一阶段就不会开始；resume 的流程会在继续之前重新校验所有既有证据。该到哪个阶段、过哪道闸门、需要哪个产物——始终是明确的，工作流不再是需要用户去"记住"的东西。

---

## Skills 与 references

### 6 个 skill

| Skill | 职责 |
|---|---|
| `specpowers-flow` | 编排器——档位选择、阶段检测、闸门强制、路由、resume |
| `specpowers-brainstorm` | 阶段 1——把原始想法变成获批方向和 `proposal.md` 草稿 |
| `specpowers-spec` | 阶段 2–3——生成 OpenSpec 产物，再通过对抗式 spec review 做 harden |
| `specpowers-plan` | 阶段 4–5——把计划写进 `tasks.md`，再建需求覆盖矩阵 |
| `specpowers-build` | 阶段 6–7——subagent 驱动的 TDD 执行（每任务一个全新 subagent）+ 合规验证 |
| `specpowers-archive` | 阶段 8——归档就绪闸门、更新活规格、最终总结 |

### 10 个 reference 模板

| Reference | 用途 |
|---|---|
| `references/stage-protocol.md` | 主表：8 阶段 × 输入 / 输出 / 闸门 / 下一步 / 失败路由 |
| `references/openspec-artifact-format.md` | 所有变更产物采纳的目录与文件格式 |
| `references/tiering-rules.md` | quick / standard / full 档位选择规则与不可降级的强制升级 |
| `references/independent-review.md` | Claude Code 与 Codex 下的对抗式 subagent 派发模式 |
| `references/subagent-execution.md` | 逐任务 subagent 执行协议，含两段式评审 |
| `references/test-driven-development.md` | RED → GREEN → REFACTOR 纪律与 test-first 子闸门 |
| `references/adversarial-spec-review.md` | harden-spec 阶段使用的 spec 评审清单 |
| `references/plan-coverage-matrix.md` | 需求 → 计划步骤 → 测试 的覆盖表与通过/失败规则 |
| `references/compliance-verification.md` | 实现对照规格的验证，含变更集证据绑定 |
| `references/archive-checklist.md` | 归档就绪清单、保守回退、必需总结 |

---

## 分级（Tiering）

编排器估算变更规模（涉及文件数、可逆性、影响半径）并选择一个档位；用户可在下述限制内向下覆盖。

| 阶段 | quick（小改 / bugfix） | standard（多数功能） | full（高风险 / 大改） |
|---|---|---|---|
| brainstorm | 跳过，内联一句话 | 轻量 | 完整 |
| generate-spec | proposal + tasks；任何行为性变更都要 spec delta | 完整产物 | 完整 |
| harden-spec | 自查 | 1 个独立对抗 subagent | 并行对抗 subagent |
| plan | 内联进 tasks.md | tasks.md | 独立 plan + tasks |
| check-coverage | 快速 checklist | 覆盖矩阵 | 矩阵 + 复核 |
| execute（TDD） | 必须 | 必须 | 必须 |
| verify-compliance | 轻量自查 | 1 个独立对抗 subagent | 并行对抗 subagent |
| archive | 闸门 | 闸门 | 闸门 + 用户确认 |

### 不可降级的强制升级

任何触及 鉴权 / 授权 / 权限、数据迁移或 schema 变更、破坏性或不可逆的状态变更、租户 / 安全边界、或资金 / 计费 的变更，**无论规模估算或用户选的档位如何，都被强制升级到 `standard` 或 `full`**。编排器从 brainstorm 范围检测这些信号。该升级不能被档位选择或覆盖绕过。

高风险面在 coverage 或 compliance 能通过之前，**还**必须有一份真实的 spec delta。`no-spec-delta` 豁免仅允许用于经独立评审、确属非行为性的变更（纯文档或格式）；且必须范围狭窄并记录在案。

### 行为性变更的 delta 规则

任何改变行为的变更，在每个档位（包括 `quick`）都需要一份真实的 spec delta。没有活规格契约，覆盖与合规闸门就没有可对照验证的对象。`quick` 的"spec delta 可选"仅适用于确属非行为性的变更（文档 / 格式 / 注释）。

---

## 安装

### Claude Code

1. 把仓库克隆进你的 Claude Code 插件目录：

   ```bash
   git clone https://github.com/ujffdi/specpowers-flow \
     ~/.claude/plugins/specpowers-flow
   ```

   如果它已上架，也可以通过 Claude Code 插件市场安装。

2. 插件清单在 `.claude-plugin/plugin.json`。Claude Code 读取它来注册插件的名称、版本和描述。

3. Skill 位于 `skills/<name>/SKILL.md`——例如 `skills/specpowers-flow/SKILL.md` 是编排器。

4. Reference 模板位于仓库根目录的 `references/<name>.md`——它们被所有 skill 共享，无需单独安装。

### Codex

Skill 正文用形如 `references/<file>.md` 的相对路径来加载它们的协议，**相对于插件根目录**解析。所以 `skills/` 与 `references/` 必须共处在同一个根目录下——**不要**把 skill 散到一个扁平的 `~/.codex/skills/` 同时把 `references/` 移到别处，否则 stage、compliance、archive 等强制协议将无法解析。

1. 把插件作为单一目录安装，保持其布局不变：

   ```bash
   git clone https://github.com/ujffdi/specpowers-flow \
     ~/.codex/plugins/specpowers-flow
   ```

   这样 `~/.codex/plugins/specpowers-flow/skills/` 和 `~/.codex/plugins/specpowers-flow/references/` 处于同一根目录下，每个从 `SKILL.md` 引用的 `references/<file>.md` 都能正确解析。

2. 把你的 Codex skill 配置指向 `~/.codex/plugins/specpowers-flow/skills/`（如果它必须放在别处，请用 symlink 链接整个插件目录、而不是单个 skill，这样 `references/` 这个同级目录会一起带过去）。

3. Codex 直接读取每个 `skills/<name>/SKILL.md`。frontmatter 的 `name` 字段与目录名一致；`description` 包含 Codex 用来选择该 skill 的触发短语。当某个 skill 说"read `references/<file>.md`"时，从上述插件根目录解析它。

---

## 使用

### 触发短语

用以下任意一句触发编排器 skill：

- `"run the full specpowers flow"`
- `"start a complete spec-driven change"`
- `"go from brainstorm to archive"`
- `"use specpowers for this feature"`

当需要从某个具体阶段 resume 时，也可以直接触发单个阶段 skill——例如 `"use specpowers-build"` 从 execute-plan 阶段继续。

### 新变更 vs resume

**新变更：** 当还不存在 `openspec/changes/<change-name>/` 目录时，或用户要求重新开始时。编排器从阶段 1（brainstorm）起步，按顺序走完全部 8 个阶段，在推进前强制每道闸门。

**Resume：** 当 `openspec/changes/<change-name>/` 目录已存在时，编排器扫描磁盘产物与 `.specpowers/gates/` 旁挂记录来推断当前阶段。它会为每个先前通过的闸门重新计算内容摘要；若某个被验证的产物在闸门通过后被改动，则该闸门及其所有下游闸门失效，流程路由回正确的阶段。用户会看到当前阶段和下一步必需动作。

---

## 与 Superpowers 和 OpenSpec 的关系

`specpowers-flow` **借鉴自** Superpowers（流程纪律类 skill）与 OpenSpec（规格驱动的产物生命周期）。它**不是**对二者的薄封装——它自包含地重新实现了核心逻辑，并且**不要求**安装其中任何一个。

当环境中检测到 Superpowers skill 或 `openspec` CLI 时，插件会用真的：编排器可以把 brainstorm、execute-plan、test-driven 等阶段交给真实的 Superpowers skill，`specpowers-archive` 会优先用 `openspec archive` 而非内置的保守回退。这是 **渐进增强**——插件哪里都能跑，而在真实工具存在时能力更强。

本项目没有从任何一方逐字复制文本；这里的所有内容均为原创。完整的致谢声明与许可证引用见 `NOTICE`。
