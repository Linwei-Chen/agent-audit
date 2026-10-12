#!/usr/bin/env bash
# 收集当前 Agent 的配置上下文，生成一份 Markdown 审核材料文件。
# 用法: collect_context.sh [输出路径] [工作区目录]
# 默认输出 /tmp/agent-audit-context.md，工作区为当前目录。
# 单个文件超过 LIMIT 字符自动截断并标注。

set -euo pipefail

OUT="${1:-/tmp/agent-audit-context.md}"
WORKSPACE="${2:-$PWD}"
LIMIT=8000

: > "$OUT"

sanitize() {
  # 脱敏：主目录替换为 ~，常见 API Key 形态打码
  sed -e "s|$HOME|~|g" -E -e 's/(sk-[A-Za-z0-9_-]{6})[A-Za-z0-9_-]+/\1***/g'
}

emit_file() {
  # emit_file <标签> <文件路径> —— 文件存在才输出，超长截断
  local label="$1" path="$2"
  [[ -f "$path" ]] || return 0
  local size
  size=$(wc -c < "$path" | tr -d ' ')
  {
    echo ""
    echo "## $label"
    echo '```'
    if (( size > LIMIT )); then
      head -c "$LIMIT" "$path" | sanitize
      echo ""
      echo "...(已截断，原文共 ${size} 字符)"
    else
      cat "$path" | sanitize
    fi
    echo '```'
  } >> "$OUT"
}

emit_skills() {
  # emit_skills <标签> <技能目录> —— 提取每个 SKILL.md 的 name/description
  local label="$1" dir="$2"
  [[ -d "$dir" ]] || return 0
  local found=0
  {
    echo ""
    echo "## $label"
  } >> "$OUT"
  local skill_md
  for skill_md in "$dir"/*/SKILL.md; do
    [[ -f "$skill_md" ]] || continue
    found=1
    local sname
    sname=$(basename "$(dirname "$skill_md")")
    {
      echo ""
      echo "### 技能: $sname"
      # 提取 frontmatter 的 name 与 description；description 为 >- 或 | 的多行块时续读缩进行
      awk '
        /^---$/ { n++; next }
        n != 1 { next }
        /^name:/ { print; pend=0; next }
        /^description:/ {
          print
          rest = $0
          sub(/^description:/, "", rest)
          gsub(/[[:space:]]/, "", rest)
          pend = (rest == "" || rest ~ /^(>[+-]?|\|[+-]?)$/)
          next
        }
        pend && /^[[:space:]]+/ { print; next }
        { pend=0 }
      ' "$skill_md" | head -30
    } >> "$OUT"
  done
  if (( found == 0 )); then
    echo "（无技能）" >> "$OUT"
  fi
}

echo "# Agent 审核材料（自动收集）" >> "$OUT"
echo "" >> "$OUT"
echo "- 收集时间：$(date '+%Y-%m-%d %H:%M:%S')" >> "$OUT"
echo "- 平台：$(uname -s) $(uname -m)" >> "$OUT"
echo "- 工作区：$(echo "$WORKSPACE" | sanitize)" >> "$OUT"
echo "- 默认 Shell：$SHELL" >> "$OUT"

echo "" >> "$OUT"
echo "---" >> "$OUT"
echo "# 一、全局指令文件" >> "$OUT"
emit_file "~/.claude/CLAUDE.md（全局指令）" "$HOME/.claude/CLAUDE.md"
emit_file "~/AGENTS.md（用户主目录指令）" "$HOME/AGENTS.md"
if [[ "$WORKSPACE" != "$HOME" ]]; then
  emit_file "工作区 AGENTS.md" "$WORKSPACE/AGENTS.md"
  emit_file "工作区 CLAUDE.md" "$WORKSPACE/CLAUDE.md"
fi

echo "" >> "$OUT"
echo "---" >> "$OUT"
echo "# 二、设置与 Hooks" >> "$OUT"
emit_file "~/.claude/settings.json" "$HOME/.claude/settings.json"
emit_file "工作区 .zcode/settings.json" "$WORKSPACE/.zcode/settings.json"
emit_file "工作区 .claude/settings.json" "$WORKSPACE/.claude/settings.json"
emit_file "工作区 .mcp.json" "$WORKSPACE/.mcp.json"

echo "" >> "$OUT"
echo "---" >> "$OUT"
echo "# 三、MCP 服务器配置" >> "$OUT"
if compgen -G "$HOME/.claude/mcp-servers/*" > /dev/null 2>&1; then
  echo "" >> "$OUT"
  echo "服务器目录：\`$(ls "$HOME/.claude/mcp-servers" 2>/dev/null | tr '\n' ' ')\`" >> "$OUT"
  for mcp_cfg in "$HOME/.claude/mcp-servers"/*/; do
    [[ -d "$mcp_cfg" ]] || continue
    for f in "$mcp_cfg"*.json; do
      [[ -f "$f" ]] || continue
      emit_file "MCP: $(basename "$mcp_cfg") / $(basename "$f")" "$f"
    done
  done
else
  echo "" >> "$OUT"
  echo "（无 MCP 配置）" >> "$OUT"
fi

echo "" >> "$OUT"
echo "---" >> "$OUT"
echo "# 四、已安装技能" >> "$OUT"
emit_skills "用户技能（~/.agents/skills）" "$HOME/.agents/skills"
emit_skills "用户技能（~/.zcode/skills）" "$HOME/.zcode/skills"
emit_skills "项目技能（工作区 .zcode/skills）" "$WORKSPACE/.zcode/skills"
emit_skills "项目技能（工作区 .agents/skills）" "$WORKSPACE/.agents/skills"

echo "" >> "$OUT"
echo "---" >> "$OUT"
echo "# 五、插件" >> "$OUT"
echo "" >> "$OUT"
echo "官方插件缓存：\`$(ls "$HOME/.zcode/cli/plugins/cache" 2>/dev/null | tr '\n' ' ')\`" >> "$OUT"
echo "已装插件目录：\`$(ls "$HOME/.claude/plugins" 2>/dev/null | tr '\n' ' ')\`" >> "$OUT"

echo "" >> "$OUT"
echo "---" >> "$OUT"
echo "# 六、工作区文档目录概览" >> "$OUT"
if [[ -d "$WORKSPACE/docs" ]]; then
  echo "" >> "$OUT"
  echo "\`docs/\` 顶层内容：\`$(ls "$WORKSPACE/docs" 2>/dev/null | head -20 | tr '\n' ' ')\`" >> "$OUT"
else
  echo "" >> "$OUT"
  echo "（工作区无 docs/ 目录）" >> "$OUT"
fi

echo "CONTEXT_FILE=$OUT"
