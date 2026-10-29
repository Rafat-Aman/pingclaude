#!/usr/bin/env bash
# ping_claude.sh — Ultra-lightweight Claude Code pinger
# Sends a single "hi" to Claude Code in print mode every time it's invoked.
# Designed to be triggered by a systemd timer every 5 hours.

set -euo pipefail

LOG_FILE="${HOME}/.local/share/ping_claude/ping.log"
mkdir -p "$(dirname "$LOG_FILE")"

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

echo "[$TIMESTAMP] Pinging Claude Code..." >> "$LOG_FILE"

# --print: non-interactive, prints response and exits
# --max-turns 1: single turn, no follow-ups
# --no-input: don't read from stdin
# Timeout after 120s to avoid hanging
RESPONSE=$(timeout 120 claude -p --max-turns 1 "hi" 2>&1) || true

echo "[$TIMESTAMP] Response: ${RESPONSE:0:200}" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"

# Keep log file from growing forever (keep last 500 lines)
if [ "$(wc -l < "$LOG_FILE")" -gt 500 ]; then
    tail -n 300 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi
