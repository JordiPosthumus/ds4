#!/bin/bash

# M3 Ultra DS4 launcher for official antirez/ds4 main with local production fixes.
# Default mode retains ten independent KV sessions while running one request
# at a time. A measured concurrency-2 run reduced both decode and net throughput.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BIN="$SCRIPT_DIR/ds4-server"
RUNNER="$SCRIPT_DIR/ds4-runner.sh"
DEFAULT_MODEL="/Users/jordiposthumus/ds4/gguf/DeepSeek-V4-Flash-Vision-Exp-MXFP4Experts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out.gguf"
MODEL="${DS4_MODEL:-$DEFAULT_MODEL}"
DEFAULT_VISION_MODEL="/Users/jordiposthumus/ds4/gguf/DeepSeek-V4-Flash-Vision-Encoder.gguf"
VISION_MODEL="${DS4_VISION_MODEL:-$DEFAULT_VISION_MODEL}"

HOST="${DS4_HOST:-127.0.0.1}"
PORT="${DS4_PORT:-8000}"
CTX_DS4="${DS4_CTX:-262144}"
TOKENS_DS4="${DS4_TOKENS:-262144}"
PREFILL_CHUNK="${DS4_PREFILL_CHUNK:-4096}"
SERVER_MIXED_PREFILL_QUANTUM="${DS4_SERVER_MIXED_PREFILL_QUANTUM:-64}"
SAVE_INTERVAL="${DS4_SAVE_INTERVAL:-16384}"
# Pi routinely sends prompts well above DS4's 30K default. Zero disables cold
# anchors entirely, so cover the full configured context instead.
COLD_MAX_TOKENS="${DS4_COLD_MAX_TOKENS:-262144}"
KV_DIR="${DS4_KV_DIR:-/tmp/ds4-kv-deepseek-v4-flash-vision-exp}"
DISK_MB="${DS4_DISK_MB:-349525}"
BATCHED_SESSIONS="${DS4_BATCHED_SESSIONS:-10}"
MAX_ACTIVE_REQUESTS="${DS4_MAX_ACTIVE_REQUESTS:-1}"
# Live-prefix rewind caused confirmed cross-session state bleed on 2026-08-25:
# an unrelated request rewound a 150381-token resident session to the shared
# system-prompt prefix and then generated from the prior conversation. Keep
# this disabled in production until the backend rewind path passes an explicit
# concurrent isolation regression.
KV_REWIND_REUSE="${DS4_KV_REWIND_REUSE:-0}"
KV_REWIND_MIN_TOKENS="${DS4_KV_REWIND_MIN_TOKENS:-256}"
PREFILL_TIMING="${DS4_PREFILL_TIMING:-1}"
LOG_FILE="${DS4_LOG_FILE:-/tmp/ds4-ds4-start.log}"
LOG_MODE="${DS4_LOG_MODE:-cache}"
LOCK_FILE="${DS4_LOCK_FILE:-/tmp/ds4-ds4-server.lock}"
LAUNCHD_LABEL="${DS4_LAUNCHD_LABEL:-com.vonbling.ds4-0731}"
OTHER_LAUNCHD_LABEL="${DS4_OTHER_LAUNCHD_LABEL:-com.vonbling.ds-glm53}"

MODE="batched"
THINK_FLAG=""
SERVER_BATCH_LOG="${DS4_SERVER_BATCH_LOG:-0}"
TAIL_LOG="${DS4_TAIL_LOG:-auto}"

usage() {
  cat <<EOF
Usage: start-ds-ds4 [--batched [N] | --single] [--think|--nothink] [--tail|--no-tail]

Modes:
  --batched [N]  Start one server with N resident sessions. Default: ${BATCHED_SESSIONS}.
  --single       Start one non-batched server.
  --tail         Follow the server log after startup.
  --no-tail      Start in the background and return after readiness.

Compatibility:
  --three        Alias for --batched 3.

Useful environment overrides:
  DS4_MODEL, DS4_VISION_MODEL, DS4_CTX, DS4_TOKENS, DS4_KV_DIR, DS4_DISK_MB,
  DS4_BATCHED_SESSIONS (default 10), DS4_MAX_ACTIVE_REQUESTS (default 1),
  DS4_SAVE_INTERVAL (default 16384),
  DS4_COLD_MAX_TOKENS (default 262144; 0 disables cold anchors),
  DS4_LOG_MODE, DS4_TAIL_LOG, DS4_EXTRA_ARGS,
  DS4_SERVER_MIXED_PREFILL_QUANTUM (default 64),
  DS4_KV_REWIND_REUSE (default 0; enable only for isolation testing),
  DS4_KV_REWIND_MIN_TOKENS (default 256), DS4_PREFILL_TIMING (default 1).
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --batched)
      MODE="batched"
      if [ "${2:-}" != "" ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then
        BATCHED_SESSIONS="$2"
        shift
      fi
      ;;
    --single)
      MODE="single"
      BATCHED_SESSIONS="0"
      ;;
    --three)
      MODE="batched"
      BATCHED_SESSIONS="3"
      ;;
    --nothink)
      THINK_FLAG="--nothink"
      ;;
    --think)
      THINK_FLAG="--think"
      ;;
    --tail)
      TAIL_LOG="1"
      ;;
    --no-tail)
      TAIL_LOG="0"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$TAIL_LOG" = "auto" ]; then
  if [ -t 1 ]; then
    TAIL_LOG="1"
  else
    TAIL_LOG="0"
  fi
fi

validate_positive_int32() {
  local name="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]] ||
     [ "${#value}" -gt 10 ] ||
     { [ "${#value}" -eq 10 ] && [[ "$value" > "2147483647" ]]; }; then
    echo "$name must be an integer from 1 through 2147483647." >&2
    exit 2
  fi
}

validate_nonnegative_int32() {
  local name="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]] ||
     [ "${#value}" -gt 10 ] ||
     { [ "${#value}" -eq 10 ] && [[ "$value" > "2147483647" ]]; }; then
    echo "$name must be an integer from 0 through 2147483647." >&2
    exit 2
  fi
}

validate_boolean() {
  local name="$1"
  local value="$2"
  if [ "$value" != "0" ] && [ "$value" != "1" ]; then
    echo "$name must be 0 or 1." >&2
    exit 2
  fi
}

validate_positive_int32 DS4_CTX "$CTX_DS4"
validate_positive_int32 DS4_TOKENS "$TOKENS_DS4"
validate_positive_int32 DS4_PREFILL_CHUNK "$PREFILL_CHUNK"
validate_nonnegative_int32 DS4_SAVE_INTERVAL "$SAVE_INTERVAL"
validate_nonnegative_int32 DS4_COLD_MAX_TOKENS "$COLD_MAX_TOKENS"
validate_positive_int32 DS4_DISK_MB "$DISK_MB"
validate_positive_int32 DS4_SERVER_MIXED_PREFILL_QUANTUM "$SERVER_MIXED_PREFILL_QUANTUM"
validate_positive_int32 DS4_KV_REWIND_MIN_TOKENS "$KV_REWIND_MIN_TOKENS"
validate_boolean DS4_KV_REWIND_REUSE "$KV_REWIND_REUSE"
validate_boolean DS4_PREFILL_TIMING "$PREFILL_TIMING"
if [ "$MODE" = "batched" ]; then
  validate_positive_int32 DS4_BATCHED_SESSIONS "$BATCHED_SESSIONS"
  validate_positive_int32 DS4_MAX_ACTIVE_REQUESTS "$MAX_ACTIVE_REQUESTS"
  if [ "$MAX_ACTIVE_REQUESTS" -gt "$BATCHED_SESSIONS" ]; then
    echo "DS4_MAX_ACTIVE_REQUESTS cannot exceed DS4_BATCHED_SESSIONS." >&2
    exit 2
  fi
fi

# Validate every artifact before stopping a healthy server. A source update may
# leave the binary missing until the next build, and local launcher files are
# intentionally not part of the upstream checkout.
if [ ! -x "$BIN" ]; then
  echo "DS4 server binary is missing or not executable: $BIN" >&2
  echo "Run: make ds4-server" >&2
  exit 1
fi
if [ ! -x "$RUNNER" ]; then
  echo "DS4 launchd runner is missing or not executable: $RUNNER" >&2
  exit 1
fi
if [ ! -f "$MODEL" ]; then
  echo "DS4 model is missing: $MODEL" >&2
  exit 1
fi
if [ ! -f "$VISION_MODEL" ]; then
  echo "DS4 vision encoder is missing: $VISION_MODEL" >&2
  exit 1
fi
if [ "$KV_DIR" = "/tmp/ds4-kv-batched" ]; then
  echo "Refusing to point DeepSeek at the GLM production KV directory: $KV_DIR" >&2
  echo "Use the DeepSeek-specific default or another DeepSeek-only DS4_KV_DIR." >&2
  exit 1
fi

wait_for_server() {
  for ((i = 1; i <= 180; i++)); do
    if curl -fsS --max-time 2 "http://${HOST}:${PORT}/v1/models" >/dev/null 2>&1; then
      echo "   -> DS4 server is ready on ${HOST}:${PORT}."
      return 0
    fi
    sleep 2
  done

  echo "DS4 server did not become ready on ${HOST}:${PORT}. Check ${LOG_FILE}." >&2
  return 1
}

case "$LOG_MODE" in
  full|cache)
    LOG_DEST="$LOG_FILE"
    ;;
  none)
    LOG_DEST="/dev/null"
    ;;
  *)
    echo "Unknown DS4_LOG_MODE: $LOG_MODE" >&2
    echo "Use DS4_LOG_MODE=cache, full, or none." >&2
    exit 2
    ;;
esac

echo "Stopping the previous DS4 service..."
OLD_SERVER_PID=""
if launch_info="$(launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null)"; then
  OLD_SERVER_PID="$(awk '/^[[:space:]]*pid = / { print $3; exit }' <<< "$launch_info")"
fi

if [ -n "$OTHER_LAUNCHD_LABEL" ] &&
   other_info="$(launchctl print "gui/$(id -u)/$OTHER_LAUNCHD_LABEL" 2>/dev/null)"; then
  OTHER_SERVER_PID="$(awk '/^[[:space:]]*pid = / { print $3; exit}' <<< "$other_info")"
  if [[ "$OTHER_SERVER_PID" =~ ^[1-9][0-9]*$ ]] &&
     kill -0 "$OTHER_SERVER_PID" >/dev/null 2>&1; then
    echo "Another DS model is running under $OTHER_LAUNCHD_LABEL (pid $OTHER_SERVER_PID)." >&2
    echo "Stop it with stop-ds-glm53f before starting DeepSeek." >&2
    exit 1
  fi
fi

if command -v lsof >/dev/null 2>&1; then
  while IFS= read -r listener_pid; do
    if [[ "$listener_pid" =~ ^[1-9][0-9]*$ ]] &&
       [ "$listener_pid" != "${OLD_SERVER_PID:-}" ]; then
      echo "Port $PORT is already owned by pid $listener_pid; not starting DeepSeek." >&2
      exit 1
    fi
  done < <(lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | sort -u)
fi

# Refuse to kill an unrelated/manual DS4 process. The instance lock records
# its owner, while this launcher only owns the PID registered under its label.
if [ -z "$OLD_SERVER_PID" ] && [ -r "$LOCK_FILE" ]; then
  read -r lock_owner < "$LOCK_FILE" || true
  if [[ "${lock_owner:-}" =~ ^[1-9][0-9]*$ ]] &&
     kill -0 "$lock_owner" >/dev/null 2>&1; then
    echo "DS4 pid $lock_owner is running outside $LAUNCHD_LABEL; not stopping it." >&2
    exit 1
  fi
fi

if [[ "$OLD_SERVER_PID" =~ ^[1-9][0-9]*$ ]]; then
  # launchctl removal already sends SIGTERM. Sending a second TERM makes
  # ds4-server take its emergency-exit path and skip resident KV persistence.
  if ! launchctl remove "$LAUNCHD_LABEL" >/dev/null 2>&1; then
    kill -TERM "$OLD_SERVER_PID" >/dev/null 2>&1 || true
  fi
  for ((i = 1; i <= 120; i++)); do
    if ! kill -0 "$OLD_SERVER_PID" >/dev/null 2>&1; then
      OLD_SERVER_PID=""
      break
    fi
    sleep 1
  done
  if [ -n "$OLD_SERVER_PID" ]; then
    echo "DS4 pid $OLD_SERVER_PID did not stop cleanly; refusing to start a second model." >&2
    exit 1
  fi
else
  launchctl remove "$LAUNCHD_LABEL" >/dev/null 2>&1 || true
fi

rm -f /tmp/ds4-main.lock /tmp/ds4-turbo.lock \
  /tmp/ds4-delegate.lock /tmp/ds4-aux.lock \
  /tmp/ds4-one.lock /tmp/ds4-two.lock /tmp/ds4-three.lock \
  "$LOCK_FILE" "$LOG_FILE"
sleep 1

args=(
  --model "$MODEL"
  --vision "$VISION_MODEL"
  --host "$HOST"
  --port "$PORT"
  --ctx "$CTX_DS4"
  --tokens "$TOKENS_DS4"
  --prefill-chunk "$PREFILL_CHUNK"
  --kv-disk-dir "$KV_DIR"
  --kv-disk-space-mb "$DISK_MB"
  --kv-cache-cold-max-tokens "$COLD_MAX_TOKENS"
  --kv-cache-continued-interval-tokens "$SAVE_INTERVAL"
  --warm-weights
)

if [ -n "$THINK_FLAG" ]; then
  args+=("$THINK_FLAG")
fi

case "$MODE" in
  batched)
    if [ "$BATCHED_SESSIONS" -le 0 ]; then
      echo "--batched requires a positive resident session count." >&2
      exit 2
    fi
    args+=(
      --batched-session "$BATCHED_SESSIONS"
      --max-active-requests "$MAX_ACTIVE_REQUESTS"
      --mixed-prefill-quantum "$SERVER_MIXED_PREFILL_QUANTUM"
    )
    ;;
  single)
    ;;
esac

if [ -n "${DS4_EXTRA_ARGS:-}" ]; then
  # Split on shell whitespace without pathname expansion. For arguments that
  # themselves contain spaces, invoke ds4-server directly or add a dedicated
  # launcher option instead of relying on this convenience override.
  read -r -a extra_args <<< "$DS4_EXTRA_ARGS"
  args+=("${extra_args[@]}")
fi

echo "Starting DS4 Vision-Exp MXFP4 on ${HOST}:${PORT}..."
echo "   Mode:        $MODE"
echo "   Model:       $MODEL"
echo "   Vision:      $VISION_MODEL"
echo "   Context:     $CTX_DS4"
echo "   Tokens:      $TOKENS_DS4"
echo "   Prefill:     $PREFILL_CHUNK-token chunks"
echo "   Prefill q:   2048 tokens (official scheduler default)"
echo "   Mixed q:     $SERVER_MIXED_PREFILL_QUANTUM tokens (while decoding)"
echo "   KV dir:      $KV_DIR"
echo "   KV budget:   $DISK_MB MiB"
echo "   Checkpoints: every $SAVE_INTERVAL tokens"
echo "   Cold anchors: prompts up to $COLD_MAX_TOKENS tokens"
echo "   KV rewind:   $KV_REWIND_REUSE (1 reuses a matching live prefix)"
echo "   KV rewind min: $KV_REWIND_MIN_TOKENS shared tokens"
echo "   Timing logs: $PREFILL_TIMING"
echo "   Thinking:    ${THINK_FLAG:---think}"
if [ "$MODE" = "batched" ]; then
  echo "   Sessions:    $BATCHED_SESSIONS resident KV sessions"
  echo "   Active:      $MAX_ACTIVE_REQUESTS request(s) at a time"
fi
if [ "$LOG_DEST" = "/dev/null" ]; then
  echo "   Log:         disabled"
else
  echo "   Log:         $LOG_FILE"
fi

# The launcher returns after readiness.  launchd must therefore own the
# server; a plain background job (even under nohup) can be reaped with the
# terminal session after it has already reported ready.
launch_args=(
  /usr/bin/env
  "DS4_LOCK_FILE=$LOCK_FILE"
  "DS4_KV_REWIND_REUSE=$KV_REWIND_REUSE"
  "DS4_KV_REWIND_MIN_TOKENS=$KV_REWIND_MIN_TOKENS"
)
if [ "$PREFILL_TIMING" = "1" ]; then
  launch_args+=("DS4_PREFILL_TIMING=1")
fi
if [ "$SERVER_BATCH_LOG" = "1" ]; then
  launch_args+=("DS4_SERVER_BATCH_LOG=1")
fi
launch_args+=("$RUNNER" "$BIN" "${args[@]}")

# `submit` imposes a five-second exit deadline, which can interrupt resident
# KV saves. Request a 120-second grace period (launchd may clamp the value).
# RunAtLoad/KeepAlive preserve submit's lifecycle; no login item is installed.
launch_dir="$(mktemp -d "${TMPDIR:-/tmp/}ds4-launchd.XXXXXX")"
launch_plist="$launch_dir/service.plist"
trap 'rm -f "$launch_plist"; rmdir "$launch_dir"' EXIT
/usr/bin/plutil -create xml1 "$launch_plist"
/usr/bin/plutil -insert Label -string "$LAUNCHD_LABEL" "$launch_plist"
/usr/bin/plutil -insert ProgramArguments -array "$launch_plist"
for arg_index in "${!launch_args[@]}"; do
  /usr/bin/plutil -insert "ProgramArguments.$arg_index" \
    -string "${launch_args[$arg_index]}" "$launch_plist"
done
/usr/bin/plutil -insert RunAtLoad -bool YES "$launch_plist"
/usr/bin/plutil -insert KeepAlive -bool YES "$launch_plist"
/usr/bin/plutil -insert ExitTimeOut -integer 120 "$launch_plist"
/usr/bin/plutil -insert StandardOutPath -string "$LOG_DEST" "$launch_plist"
/usr/bin/plutil -insert StandardErrorPath -string "$LOG_DEST" "$launch_plist"
launchctl bootstrap "gui/$(id -u)" "$launch_plist"
rm -f "$launch_plist"
rmdir "$launch_dir"
trap - EXIT

wait_for_server

SERVER_PID="$(launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null \
  | awk '/^[[:space:]]*pid = / { print $3; exit }')"
SERVER_PID="${SERVER_PID:-unknown}"

echo ""
echo "DS4 Vision-Exp is live."
echo "   PID:      $SERVER_PID"
echo "   Service:  $LAUNCHD_LABEL"
echo "   Endpoint: http://${HOST}:${PORT}/v1"
echo "   Models:   http://${HOST}:${PORT}/v1/models"
if [ "$TAIL_LOG" = "1" ] && [ "$LOG_DEST" != "/dev/null" ]; then
  echo ""
  echo "Following $LOG_FILE. Press Ctrl+C to stop watching; ds4-server keeps running."
  tail -n 80 -f "$LOG_FILE"
elif [ "$LOG_DEST" != "/dev/null" ]; then
  echo "   Logs:     tail -f $LOG_FILE"
fi
