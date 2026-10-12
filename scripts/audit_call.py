#!/usr/bin/env python3
"""直连 OpenAI 兼容 API 发起审核调用，绕过 MCP 工具的会话级超时限制。

用法:
  audit_call.py --prompt-file <prompt.md> [--system <system>] [--output <out.md>]
                [--model <model>] [--max-tokens <n>]

- 默认模型 claude-opus-5-5。
- 凭证来源（按优先级）:
  1. 环境变量 LLM_API_KEY / LLM_BASE_URL（任意 OpenAI 兼容服务均可）；
  2. llm-chat MCP 的注册配置（~/.zcode/cli/config.json 优先，回退 ~/.claude.json，
     取 mcp(s).servers/mcpServers.llm-chat.env）。
  绝不把密钥打印到输出。
- 网络超时 300 秒。成功时若给了 --output 则写入文件并打印 OUT=<路径>，
  否则把回复正文打印到 stdout。
"""

import argparse
import json
import os
import sys

DEFAULT_MODEL = "claude-opus-5-5"
TIMEOUT_SECONDS = 300

CONFIG_CANDIDATES = [
    os.path.expanduser("~/.zcode/cli/config.json"),
    os.path.expanduser("~/.claude.json"),
]


def load_llm_env():
    """取 LLM_API_KEY / LLM_BASE_URL：环境变量优先，其次 llm-chat MCP 注册配置。"""
    env_key = os.environ.get("LLM_API_KEY")
    if env_key:
        return env_key, os.environ.get("LLM_BASE_URL", "https://api.openai.com/v1")
    for path in CONFIG_CANDIDATES:
        if not os.path.exists(path):
            continue
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue
        # 兼容两种结构：mcp.servers.* 与 mcpServers.*
        node = (data.get("mcp") or {}).get("servers", {}).get("llm-chat") \
            or data.get("mcpServers", {}).get("llm-chat")
        if node and node.get("env", {}).get("LLM_API_KEY"):
            env = node["env"]
            return env["LLM_API_KEY"], env.get("LLM_BASE_URL", "https://api.openai.com/v1")
    return None, None


def call_api(api_key, base_url, model, system, prompt, max_tokens):
    url = base_url.rstrip("/") + "/chat/completions"
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    payload = {"model": model, "messages": messages, "max_tokens": max_tokens}
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}

    body = json.dumps(payload).encode("utf-8")

    # 优先用 httpx（llm-chat 服务器本身依赖它，必然已安装），回退 urllib
    try:
        import httpx
        with httpx.Client(timeout=TIMEOUT_SECONDS) as client:
            resp = client.post(url, headers=headers, content=body)
    except ImportError:
        import urllib.request
        req = urllib.request.Request(url, data=body, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
            resp = resp

    if resp.status_code != 200:
        text = getattr(resp, "text", b"")
        if isinstance(text, bytes):
            text = text.decode("utf-8", "replace")
        return None, f"API error {resp.status_code}: {text[:500]}"

    data = json.loads(resp.text if isinstance(resp.text, str) else resp.text.decode("utf-8"))
    return data["choices"][0]["message"]["content"], None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt-file", required=True, help="prompt 正文文件（UTF-8）")
    ap.add_argument("--system", default="你是资深 AI Agent 架构评审员，审阅严谨，只依据材料下结论，每条意见附证据和可执行的改进做法。用简体中文回答。")
    ap.add_argument("--output", default=None)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--max-tokens", type=int, default=16000)
    args = ap.parse_args()

    with open(args.prompt_file, encoding="utf-8") as f:
        prompt = f.read()

    api_key, base_url = load_llm_env()
    if not api_key:
        print("ERROR: 未找到 LLM_API_KEY——请设置环境变量 LLM_API_KEY（及 LLM_BASE_URL），"
              "或在 llm-chat 的 MCP 注册配置（~/.zcode/cli/config.json 或 ~/.claude.json）中提供", file=sys.stderr)
        sys.exit(2)

    content, error = call_api(api_key, base_url, args.model, args.system, prompt, args.max_tokens)
    if error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"OUT={args.output}")
    else:
        print(content)


if __name__ == "__main__":
    main()
