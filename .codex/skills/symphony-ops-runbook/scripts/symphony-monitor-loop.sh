#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="symphony-monitor-loop"
STATE_URL="${SYMPHONY_MONITOR_STATE_URL:-http://127.0.0.1:4000/api/v1/state}"
PROCESS_PATTERN="${SYMPHONY_MONITOR_PROCESS_PATTERN:-bin/symphony ./WORKFLOW.linear.edict-codex.local.md}"
PORT_PATTERN="${SYMPHONY_MONITOR_PORT_PATTERN:-:4000 }"
LOG_FILE="${SYMPHONY_MONITOR_LOG_FILE:-/tmp/symphony-edict-monitor.log}"
PID_FILE="${SYMPHONY_MONITOR_PID_FILE:-/tmp/symphony-edict-monitor.pid}"
INTERVAL_SECONDS="${SYMPHONY_MONITOR_INTERVAL_SECONDS:-5}"

write_snapshot() {
  local ts process_line port_line payload
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  process_line="$(pgrep -af "$PROCESS_PATTERN" | grep -v '/bin/bash -c' || true)"
  port_line="$(ss -ltnp | grep "$PORT_PATTERN" || true)"
  payload="$(curl --max-time 5 -sS "$STATE_URL" 2>/dev/null || printf '{"error":"state_fetch_failed"}')"

  python3 - "$ts" "$process_line" "$port_line" "$payload" >>"$LOG_FILE" <<'PY'
import json
import sys

ts, process_line, port_line, payload = sys.argv[1:5]
try:
    data = json.loads(payload)
except Exception:
    data = {"raw": payload}

running = data.get("running", []) if isinstance(data, dict) else []
retrying = data.get("retrying", []) if isinstance(data, dict) else []
issues = []
for item in running if isinstance(running, list) else []:
    if isinstance(item, dict):
        issues.append(item.get("issue_identifier") or item.get("identifier"))

print(json.dumps({
    "ts": ts,
    "process": process_line,
    "port_open": bool(port_line),
    "running_count": len(running) if isinstance(running, list) else None,
    "retrying_count": len(retrying) if isinstance(retrying, list) else None,
    "running_issues": issues,
    "state_error": data.get("error") if isinstance(data, dict) else None
}, ensure_ascii=False))
PY
}

start_loop() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "already-running pid=$(cat "$PID_FILE")"
    exit 0
  fi

  nohup bash -c '
    while true; do
      "'"$0"'" run-once || true
      sleep "'"$INTERVAL_SECONDS"'"
    done
  ' >/dev/null 2>&1 &

  echo "$!" >"$PID_FILE"
  echo "started pid=$(cat "$PID_FILE")"
}

stop_loop() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    kill "$(cat "$PID_FILE")"
    rm -f "$PID_FILE"
    echo "stopped"
  else
    rm -f "$PID_FILE"
    echo "not-running"
  fi
}

status_loop() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "running pid=$(cat "$PID_FILE")"
  else
    echo "not-running"
  fi
  echo "log=$LOG_FILE"
}

tail_log() {
  touch "$LOG_FILE"
  tail -n 20 "$LOG_FILE"
}

case "${1:-}" in
  start) start_loop ;;
  stop) stop_loop ;;
  status) status_loop ;;
  tail) tail_log ;;
  run-once) write_snapshot ;;
  *)
    echo "usage: $SCRIPT_NAME {start|stop|status|tail|run-once}"
    exit 1
    ;;
esac
