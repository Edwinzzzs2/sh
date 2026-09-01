#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_DIR/kejilion.sh"
WORKDIR="${TMPDIR:-/tmp}/openclaw-weixin-bind-test-$$"
mkdir -p "$WORKDIR/bin" "$WORKDIR/home/.openclaw/openclaw-weixin"
trap 'rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/harness.sh" <<'EOF'
#!/usr/bin/env bash
install() { return 0; }
send_stats() { :; }
EOF

# 只提取本功能的函数，避免执行主脚本的交互式菜单。
awk '
/^[[:space:]]*openclaw_weixin_account_ids\(\) \{/ { capture = 1 }
capture && /^[[:space:]]*change_tg_bot_code\(\) \{/ { exit }
capture { print }
' "$SCRIPT" >> "$WORKDIR/harness.sh"

cat > "$WORKDIR/bin/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true
echo "openclaw $cmd $*" >> "$HOME/.openclaw/mock_openclaw.log"

case "$cmd" in
  agents)
    sub="${1:-}"
    shift || true
    if [ "$sub" = "list" ]; then
      cat <<JSON
[{"id":"main","identityName":"主助手","workspace":"$HOME/.openclaw/workspace"},{"id":"mmm","identityName":"小爪","workspace":"$HOME/.openclaw/workspace-mmm"}]
JSON
    elif [ "$sub" = "bind" ]; then
      echo '{"added":["openclaw-weixin accountId=newwx-im-bot"]}'
    fi
    ;;
  plugins)
    [ "${1:-}" = "inspect" ] && echo 'Status: loaded'
    ;;
  channels)
    if [ "${1:-}" = "login" ]; then
      printf '["oldwx-im-bot","newwx-im-bot"]\n' > "$HOME/.openclaw/openclaw-weixin/accounts.json"
      echo '扫码登录成功'
    fi
    ;;
esac
EOF
chmod +x "$WORKDIR/bin/openclaw"

cat > "$WORKDIR/bin/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args="$*"
case "$args" in
  *'select(type == "string" and length > 0)'*)
    file="${!#}"
    tr -d '[]" ' < "$file" | tr ',' '\n' | sed '/^$/d' | sort -u
    ;;
  *'type == "array" and length > 0'*)
    cat >/dev/null
    ;;
  *'identityName // .name'*)
    cat >/dev/null
    printf '%s\n' '- main\t主助手\t/mock/workspace' '- mmm\t小爪\t/mock/workspace-mmm'
    ;;
  *'select(.id == $id)'*)
    cat >/dev/null
    case "$args" in
      *'--arg id main'*|*'--arg id mmm'*) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  *)
    echo "unexpected jq invocation: $args" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$WORKDIR/bin/jq"

printf '["oldwx-im-bot"]\n' > "$WORKDIR/home/.openclaw/openclaw-weixin/accounts.json"
export HOME="$WORKDIR/home"
export PATH="$WORKDIR/bin:$PATH"

source "$WORKDIR/harness.sh"
printf 'mmm\n' | openclaw_weixin_connect_agent > "$WORKDIR/output.log"

grep -Fq 'openclaw channels login --channel openclaw-weixin' "$HOME/.openclaw/mock_openclaw.log"
grep -Fq 'openclaw agents bind --agent mmm --bind openclaw-weixin:newwx-im-bot --json' "$HOME/.openclaw/mock_openclaw.log"
grep -Fq '微信账号 newwx-im-bot 已接入工作区 mmm' "$WORKDIR/output.log"

echo 'OPENCLAW_WEIXIN_BIND_SMOKE_OK'
