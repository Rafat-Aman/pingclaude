#!/usr/bin/env bash
# ping_claude.sh — Ultra-lightweight Claude Code pinger
# Reads the real 5h session window from Anthropic's usage endpoint (the same
# one usage-monitor extensions use; costs no tokens). If no window is active it
# sends "hi" to start one, then rewrites its systemd timer to fire right after
# the window resets.

set -uo pipefail

DIR="${HOME}/.local/share/ping_claude"
LOG_FILE="$DIR/ping.log"
CREDS="${HOME}/.claude/.credentials.json"
TIMER="${HOME}/.config/systemd/user/ping-claude.timer"
mkdir -p "$DIR"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"; }

token_valid() {
    jq -e '(.claudeAiOauth.expiresAt // 0) / 1000 > now + 60' "$CREDS" >/dev/null 2>&1
}

# Prints the epoch when the current 5h window resets, 0 if no window is
# active, or nothing if the lookup failed (expired token, rate limit, offline).
window_reset() {
    token_valid || return
    local token resets_at
    token=$(jq -r '.claudeAiOauth.accessToken' "$CREDS")
    resets_at=$(curl -sf -m 20 https://api.anthropic.com/api/oauth/usage \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" | jq -r '.five_hour.resets_at') || return
    if [[ "$resets_at" == "null" ]]; then echo 0; else date -d "$resets_at" +%s; fi
}

ping_claude() {
    log "Pinging Claude Code..."
    # Haiku, no MCP servers: the cheapest message that still opens a window.
    local response
    response=$(timeout 120 claude -p --model haiku --strict-mcp-config --max-turns 1 "hi" 2>&1)
    log "Response: ${response:0:200}"
    echo "---" >> "$LOG_FILE"
    sleep 5
}

schedule() {
    local when
    when=$(date -d "@$1" '+%F %T')
    grep -qF "OnCalendar=$when" "$TIMER" 2>/dev/null && return
    cat > "$TIMER" <<EOF
# Rewritten by ping_claude.sh after every check.
[Unit]
Description=Ping Claude Code when the 5h session window resets

[Timer]
# Next session reset (+1 min)
OnCalendar=$when
# Safety net: re-check usage hourly (no tokens) in case a run failed
OnCalendar=hourly
Persistent=true
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user restart ping-claude.timer
    log "Next check scheduled for $when"
}

NOW=$(date +%s)
RESET=$(window_reset)

if [[ -n "$RESET" ]]; then
    if (( RESET <= NOW )); then
        ping_claude
        RESET=$(window_reset)
    fi
elif ! token_valid; then
    # Expired token means Claude Code hasn't run for hours, so a window is
    # almost certainly not active. The ping also makes Claude Code refresh it.
    log "Token expired; pinging blind"
    ping_claude
    RESET=$(window_reset)
fi

if [[ -n "$RESET" ]] && (( RESET > NOW )); then
    schedule $((RESET + 60))
else
    log "Couldn't read session window; retrying in 10 min"
    schedule $((NOW + 600))
fi

# Keep log file from growing forever (keep last 500 lines)
if [ "$(wc -l < "$LOG_FILE")" -gt 500 ]; then
    tail -n 300 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi
