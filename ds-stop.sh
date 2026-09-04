#!/bin/bash

set -euo pipefail

LAUNCHD_LABEL="${DS4_LAUNCHD_LABEL:-com.vonbling.ds-glm53}"
LOCK_FILE="${DS4_LOCK_FILE:-/tmp/ds4-server.lock}"
LOG_FILE="${DS4_LOG_FILE:-/tmp/ds4-start.log}"
SERVICE_NAME="${DS4_SERVICE_NAME:-DS}"

SERVER_PID=""
LAUNCHD_MANAGED=0
if launch_info="$(launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null)"; then
  SERVER_PID="$(awk '/^[[:space:]]*pid = / { print $3; exit}' <<< "$launch_info")"
  if [[ "$SERVER_PID" =~ ^[1-9][0-9]*$ ]]; then
    LAUNCHD_MANAGED=1
  fi
fi
if [ -z "$SERVER_PID" ] && [ -r "$LOCK_FILE" ]; then
  read -r lock_owner < "$LOCK_FILE" || true
  if [[ "${lock_owner:-}" =~ ^[1-9][0-9]*$ ]] &&
     kill -0 "$lock_owner" >/dev/null 2>&1; then
    SERVER_PID="$lock_owner"
  fi
fi

if ! [[ "$SERVER_PID" =~ ^[1-9][0-9]*$ ]]; then
  echo "$SERVICE_NAME is not running."
  exit 0
fi

echo "Stopping $SERVICE_NAME pid $SERVER_PID..."
if (( LAUNCHD_MANAGED )); then
  # Removing a launchd job already sends its process SIGTERM.  A second TERM is
  # not harmless for ds4-server: its signal handler treats a repeated shutdown
  # request as an emergency exit, which skips resident KV persistence.  Only
  # fall back to an explicit signal when launchd could not remove the job.
  if ! launchctl remove "$LAUNCHD_LABEL" >/dev/null 2>&1; then
    kill -TERM "$SERVER_PID" >/dev/null 2>&1 || true
  fi
else
  kill -TERM "$SERVER_PID" >/dev/null 2>&1 || true
fi

for ((i = 1; i <= 120; i++)); do
  if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    rm -f "$LOCK_FILE"
    echo "$SERVICE_NAME stopped."
    exit 0
  fi
  sleep 1
done

echo "$SERVICE_NAME pid $SERVER_PID did not stop within 120 seconds; see $LOG_FILE." >&2
exit 1
