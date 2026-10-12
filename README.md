# agent-audit

**给你的编码 Agent 配一位"外部大模型复核员"。** 小模型干完活总说"完成了、没问题"，但问题往往就在它没发现的地方——本技能把刚完成的工作交给更强的外部模型（本地 Codex 或 Opus 5.5）复核，把漏掉的问题挖出来。

适用于 Claude Code、ZCode 等支持 Agent Skills 的编码工具。

> A skill for Claude Code / ZCode: after your (smaller) coding agent claims a task is done, hand the work to a stronger external model — local Codex CLI or an Opus-compatible endpoint — to find the problems the small model missed. English quick start at the bottom.

## 解决什么问题

主力模型较小时（GLM-Flash、Claude Haiku、GPT 小杯档位等），常见模式是：

- 声称"测试通过"，实际只 `print` 了一下没做断言；
- 说"边界都处理了"，实际 `window=0` 直接崩溃；
- 写完文档没核对，结论材料里根本不支持。

本技能把**你的原始要求、Agent 的完成声明、实际产出**（读真实文件、真实跑命令）一起送给外部大模型，让它逐条对照，输出分级问题清单（P0/P1/P2），每条带证据和修改建议。

## 工作原理

```
你说"审核一下刚才的工作"
        │
        ▼
收集材料 ──► 原始要求(原话) + Agent声明(原话) + 实际产出(读文件/跑命令) + 已知风险点
        │
        ▼
选择复核引擎
├── codex（默认）：本地 Codex CLI，read-only 沙箱内自己读文件、自己跑命令取证
└── opus：llm-chat 端点的 Opus 5.5（或任意 OpenAI 兼容端点），纯文本深度分析
        │
        ▼
外部模型输出报告 ──► 总体结论 + P0/P1/P2 问题(证据+建议) + 确认无误的方面
        │
        ▼
报告归档到 docs/opus-review/，向你汇报与声明矛盾的重点
```

另外还有**配置审核模式**：审核 Agent 自身的配置（全局指令、技能清单、MCP、Hooks），自动收集材料并脱敏。

## 安装

```bash
git clone https://github.com/Linwei-Chen/agent-audit.git
mkdir -p ~/.agents/skills          # ZCode / 通用技能目录
cp -r agent-audit ~/.agents/skills/
# Claude Code 用户改为：mkdir -p ~/.claude/skills && cp -r agent-audit ~/.claude/skills/
```

重启会话后，对 Agent 说"审核一下刚才的工作"即可触发，也可显式输入 `/agent-audit`。

## 引擎配置

### codex 引擎（默认）

需要本地安装并登录 Codex CLI：

```bash
npm install -g @openai/codex
codex login   # 用 ChatGPT 账号登录（Plus/Pro 套餐即可），或配置 API Key
```

模型默认取 `~/.codex/config.toml` 的配置。复核固定在 **read-only 沙箱**中运行——它能读文件、跑命令，但改不了你的文件，也出不了网。

### opus 引擎（可选）

凭证二选一：

```bash
# 方式一：任意 OpenAI 兼容服务
export LLM_API_KEY="sk-..."
export LLM_BASE_URL="https://api.openai.com/v1"   # 默认值，可换成自己的端点
```

方式二：已配置 [llm-chat](https://github.com/) 式 MCP 服务器的，脚本会自动从其注册配置（`~/.zcode/cli/config.json` 或 `~/.claude.json`）读取密钥。默认模型 `claude-opus-5-5`，可用 `--model` 换。

> 为什么走脚本而不是 MCP 工具？会话内 MCP 调用通常有 30 秒超时，而大模型写一份完整报告往往超过它。脚本把超时放宽到 300 秒、max_tokens 16000。

## 用法示例

对话触发：

> 用户：刚才那个脚本你确认没问题了吗？
> Agent：测试通过了。
> 用户：用 Codex 审一下再说。

Agent 会自动：整理要求与声明 → 读实际文件、跑真实命令 → 调外部模型 → 汇报矛盾点 → 归档报告到 `docs/opus-review/`。

也可以直接手动调用脚本：

```bash
# codex 引擎
bash ~/.agents/skills/agent-audit/scripts/codex_call.sh prompt.md report.md /path/to/project

# opus 引擎
python3 ~/.agents/skills/agent-audit/scripts/audit_call.py --prompt-file prompt.md --output report.md
```

报告格式：

```markdown
## 总体结论
不能认可"已完成"的说法：要求②完全未实现……
## 发现的问题
### [P0] 声明的运行输出与代码不符
- 问题：……
- 证据：……（引用材料具体内容）
- 建议：……
## 确认无误的方面
- ……
```

## 实测效果

用一份植入缺陷的代码做过对照测试（Agent 虚构"边界都处理了、自测通过"的声明）：

- **两个引擎都抓出了全部植入缺陷**（`window=0` 除零、负数窗口静默出错、声明输出与代码不符），并各自额外发现了 5-6 个问题（类型校验缺失、`True` 被当窗口 1、O(n²) 复杂度等）；
- Codex 在沙箱里真实执行代码取证，推演与实跑结果一致；
- 测试报告见本仓库 `docs/` 说明附带的仓库发布记录，样例格式如上。

## 安全设计

- **材料去向可控**：只发往你配置的 Codex CLI（自己的 ChatGPT 账号）或你配置的 OpenAI 兼容端点，不经过任何第三方服务；
- **codex 固定 read-only 沙箱**：复核者改不了你的文件（实测中它想自主外呼其他 API 也被沙箱拦截）；
- **自动脱敏**：配置审核模式下，收集脚本把主目录替换为 `~`、常见 API Key 形态打码；
- **不自动改成果**：审核意见未经你确认，Agent 不会按意见直接修改代码；
- **涉密确认**：材料涉及未发表稿件、隐私内容时，要求先征得用户同意再发送。

## 适用范围与限制

- codex 引擎需要本机 Codex CLI 与有效登录；opus 引擎需要任意 OpenAI 兼容端点；
- 长报告可能被 max_tokens 截断，技能内置了截断检查与续写拼接流程；
- 配置审核的收集脚本针对 Claude Code / ZCode 的常见目录布局（`~/.claude`、`~/.zcode`、`~/.agents/skills`），其他环境可自行调整 `collect_context.sh`。

## English quick start

1. `git clone` this repo and copy the folder into `~/.claude/skills/` (Claude Code) or `~/.agents/skills/` (ZCode).
2. Engine **codex** (default): install & `codex login`. Engine **opus**: export `LLM_API_KEY` / `LLM_BASE_URL` (any OpenAI-compatible endpoint).
3. Say *"review what you just did"* / *"audit this work"* in a session — the agent gathers your original request, the agent's own claims, and the real artifacts (reading files, running commands), sends them to the external model, and returns a P0/P1/P2 report with evidence. Reports are archived under `docs/opus-review/`.

## License

[MIT](LICENSE)
