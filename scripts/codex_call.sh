#!/usr/bin/env bash
# 用本地 Codex CLI（ChatGPT 套餐）执行复核，是 llm-chat/Opus 之外的第二个引擎。
# 优势：Codex 是能动手的 Agent，会在 read-only 沙箱内自己读文件、自己跑命令
# 做独立验证，不只依赖转述的材料——代码类任务尤其推荐。
#
# 用法: codex_call.sh <prompt文件> <输出文件> [被审工作目录] [模型]
#   工作目录默认当前目录；模型默认取 ~/.codex/config.toml 的配置。
#
# 沙箱固定 read-only：审核者只能读文件和跑代码，改不了你的文件；
# 不要改成 danger-full-access。需要 --skip-git-repo-check，因为工作区常不是 git 仓库。

set -euo pipefail

PROMPT_FILE="$1"
OUT="$2"
WORKDIR="${3:-$PWD}"
MODEL="${4:-}"

[[ -f "$PROMPT_FILE" ]] || { echo "ERROR: prompt 文件不存在: $PROMPT_FILE" >&2; exit 2; }

EXTRA=()
[[ -n "$MODEL" ]] && EXTRA=(-m "$MODEL")

# codex 会把执行过程流式打到 stdout（可达几十 KB），存到日志避免刷屏；
# 最终复核报告由 -o 写入 OUT。
LOG="${OUT}.log"
if ! codex exec --skip-git-repo-check -s read-only -C "$WORKDIR" \
  -o "$OUT" "${EXTRA[@]+"${EXTRA[@]}"}" - < "$PROMPT_FILE" > "$LOG" 2>&1; then
  echo "ERROR: codex 执行失败，日志末尾 30 行：" >&2
  tail -30 "$LOG" >&2
  exit 1
fi
rm -f "$LOG"

[[ -s "$OUT" ]] || { echo "ERROR: 输出文件为空" >&2; exit 1; }
echo "OUT=$OUT"
