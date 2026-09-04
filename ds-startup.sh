#!/bin/bash

# M3 Ultra DS launcher for antirez/ds4 (DwarfStar) — GLM-5.3-Flash production.
# One resident GLM-5.3-Flash Q4_K model, one batched KV session by default.
#
# This launcher serves GLM 5.3 Flash exclusively. DeepSeek has a separate
# model-specific launcher and cannot share this model's live service or KV.
# GLM notes:
#   - No --prefill-chunk (unsupported for GLM; the engine computes chunks).
#   - No --think flag (GLM thinking is request-level reasoning_effort; the
#     server defaults to high effort).
#   - Live-prefix rewind reuse is a kill-switched experiment:
#     DS4_KV_REWIND_REUSE=0 is the production default (2026-08-25 incident
#     class). The KV dir below is GLM-owned; it held DeepSeek checkpoints
#     until macOS /tmp cleanup swept them on 2026-08-28.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BIN="$SCRIPT_DIR/ds4-server"
RUNNER="$SCRIPT_DIR/ds4-runner.sh"
DEFAULT_MODEL="/Users/jordiposthumus/ds4/gguf/GLM-5.3-Flash-Q4_K.gguf"
MODEL="${DS4_MODEL:-$DEFAULT_MODEL}"

HOST="${DS4_HOST:-127.0.0.1}"
PORT="${DS4_PORT:-8000}"
CTX_DS4="${DS4_CTX:-384000}"
TOKENS_DS4="${DS4_TOKENS:-384000}"
SERVER_MIXED_PREFILL_QUANTUM="${DS4_SERVER_MIXED_PREFILL_QUANTUM:-64}"
SAVE_INTERVAL="${DS4_SAVE_INTERVAL:-16384}"
# Pi routinely sends prompts well above DS4's 30K default. Zero disables cold
# anchors entirely, so cover the full configured context instead.
COLD_MAX_TOKENS="${DS4_COLD_MAX_TOKENS:-384000}"
KV_DIR="${DS4_KV_DIR:-/tmp/ds4-kv-batched}"
DISK_MB="${DS4_DISK_MB:-349525}"
# Keep the production path in batched-server mode, but use one resident
# session for strict request isolation and predictable operation. Additional
# requests queue. Higher values remain available for deliberate concurrency
# evaluations; six is the previously validated capacity envelope.
BATCHED_SESSIONS="${DS4_BATCHED_SESSIONS:-1}"
# Kill switch for GLM live-prefix rewind reuse. An unrelated request sharing
# a prefix with a resident slot would rewind that slot — the 2026-08-25
# cross-session state-bleed failure class. Disabled until a dedicated
# concurrent isolation regression passes; zero means disabled.
KV_REWIND_REUSE="${DS4_KV_REWIND_REUSE:-0}"
# Model-embedded MTP speculation (GLM 5.3 ships the MTP block in the GGUF).
# Production stays on ordinary decode: the 2026-08-29 Q4 long-context run
# measured 15.3 t/s with MTP versus the established ~20 t/s batched baseline.
# DS4_MTP=1 remains available for explicit evaluation; --mtp-timing then logs
# acceptance and net-saved stats in the configured model-specific log.
MTP="${DS4_MTP:-0}"
# GLM 5.3 vision encoder sidecar (Metal backend required, which is what this
# host uses). Loaded as a separate ~1.1 GiB GGUF; the encoder only runs on
# requests that carry images, so resident text cost is unchanged. Enabled by
# default from 2026-08-29; DS4_VISION=0 starts text-only.
VISION="${DS4_VISION:-1}"
VISION_MODEL="${DS4_VISION_MODEL:-$SCRIPT_DIR/gguf/GLM-5.3-Flash-Vision-Encoder.gguf}"
# Resident Q4 needs the model map (~178 GiB) wired; the guard grants
# wired_limit - 2 GiB. The limit is a runtime sysctl and resets on reboot.
REQUIRED_WIRED_MB=481280
PREFILL_TIMING="${DS4_PREFILL_TIMING:-1}"
LOG_FILE="${DS4_LOG_FILE:-/tmp/ds4-start.log}"
LOG_MODE="${DS4_LOG_MODE:-cache}"
LOCK_FILE="${DS4_LOCK_FILE:-/tmp/ds4-server.lock}"
LAUNCHD_LABEL="${DS4_LAUNCHD_LABEL:-com.vonbling.ds-glm53}"
OTHER_LAUNCHD_LABEL="${DS4_OTHER_LAUNCHD_LABEL:-}"

MODE="batched"
SERVER_BATCH_LOG="${DS4_SERVER_BATCH_LOG:-0}"
TAIL_LOG="${DS4_TAIL_LOG:-auto}"

usage() {
  cat <<EOF
Usage: start-ds-glm53f (or start-ds) [--batched [N] | --single] [--tail|--no-tail]

Modes:
  --batched [N]  Start one server with N resident sessions. Default: ${BATCHED_SESSIONS}.
  --single       Start one non-batched server (debug).
  --tail         Follow the server log after startup.
  --no-tail      Start in the background and return after readiness.

Useful environment overrides:
  DS4_MODEL, DS4_CTX, DS4_TOKENS, DS4_KV_DIR, DS4_DISK_MB,
  DS4_BATCHED_SESSIONS (default 1; 6 is the validated capacity envelope), DS4_SAVE_INTERVAL (default 16384),
  DS4_COLD_MAX_TOKENS (default 384000; 0 disables cold anchors),
  DS4_MTP (0/1, default 0; 1 enables model-embedded MTP evaluation with timing),
  DS4_VISION (0/1, default 1; loads the GLM 5.3 vision encoder sidecar),
  DS4_VISION_MODEL (default gguf/GLM-5.3-Flash-Vision-Encoder.gguf),
  DS4_KV_REWIND_REUSE (0/1, default 0; enable only for isolation testing),
  DS4_SERVER_MIXED_PREFILL_QUANTUM (default 64),
  DS4_LOG_MODE, DS4_TAIL_LOG, DS4_EXTRA_ARGS, DS4_PREFILL_TIMING (default 1).
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
validate_nonnegative_int32 DS4_SAVE_INTERVAL "$SAVE_INTERVAL"
validate_nonnegative_int32 DS4_COLD_MAX_TOKENS "$COLD_MAX_TOKENS"
validate_positive_int32 DS4_DISK_MB "$DISK_MB"
validate_positive_int32 DS4_SERVER_MIXED_PREFILL_QUANTUM "$SERVER_MIXED_PREFILL_QUANTUM"
validate_boolean DS4_KV_REWIND_REUSE "$KV_REWIND_REUSE"
validate_boolean DS4_MTP "$MTP"
validate_boolean DS4_VISION "$VISION"
validate_boolean DS4_PREFILL_TIMING "$PREFILL_TIMING"
if [ "$MODE" = "batched" ]; then
  validate_positive_int32 DS4_BATCHED_SESSIONS "$BATCHED_SESSIONS"
fi

# Validate every artifact before stopping a healthy server. A source update may
# leave the binary missing until the next build, and local launcher files are
# intentionally not part of the upstream checkout.
if [ ! -x "$BIN" ]; then
  echo "DS server binary is missing or not executable: $BIN" >&2
  echo "Run: make ds4-server" >&2
  exit 1
fi
if [ ! -x "$RUNNER" ]; then
  echo "DS launchd runner is missing or not executable: $RUNNER" >&2
  exit 1
fi
if [ ! -f "$MODEL" ]; then
  echo "DS model is missing: $MODEL" >&2
  exit 1
fi
if [ "$VISION" = "1" ] && [ ! -f "$VISION_MODEL" ]; then
  echo "DS vision encoder is missing: $VISION_MODEL" >&2
  echo "Download it with: ./download_model.sh glm53-vision (or start with DS4_VISION=0)" >&2
  exit 1
fi

WIRED_LIMIT_MB="$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || true)"
if ! [[ "${WIRED_LIMIT_MB:-}" =~ ^[0-9]+$ ]] ||
   [ "$WIRED_LIMIT_MB" -lt "$REQUIRED_WIRED_MB" ]; then
  echo "The Metal wired-memory limit is ${WIRED_LIMIT_MB:-unreadable} MiB; the GLM-5.3 resident Q4 profile needs at least ${REQUIRED_WIRED_MB} MiB." >&2
  echo "It resets on reboot. Run this first:" >&2
  echo "  sudo sysctl -w iogpu.wired_limit_mb=498073" >&2
  exit 1
fi

wait_for_server() {
  for ((i = 1; i <= 180; i++)); do
    if curl -fsS --max-time 2 "http://${HOST}:${PORT}/v1/models" >/dev/null 2>&1; then
      echo "   -> DS server is ready on ${HOST}:${PORT}."
      return 0
    fi
    sleep 2
  done

  echo "DS server did not become ready on ${HOST}:${PORT}. Check ${LOG_FILE}." >&2
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

echo "Stopping the previous DS service..."
OLD_SERVER_PID=""
if launch_info="$(launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null)"; then
  OLD_SERVER_PID="$(awk '/^[[:space:]]*pid = / { print $3; exit}' <<< "$launch_info")"
fi

# Model-specific launchers share port 8000 but have distinct launchd labels.
# Never stop or replace the other model implicitly: require its named stop
# command first so switching a 150+ GiB resident model is always deliberate.
if [ -n "$OTHER_LAUNCHD_LABEL" ] &&
   other_info="$(launchctl print "gui/$(id -u)/$OTHER_LAUNCHD_LABEL" 2>/dev/null)"; then
  OTHER_SERVER_PID="$(awk '/^[[:space:]]*pid = / { print $3; exit}' <<< "$other_info")"
  if [[ "$OTHER_SERVER_PID" =~ ^[1-9][0-9]*$ ]] &&
     kill -0 "$OTHER_SERVER_PID" >/dev/null 2>&1; then
    echo "Another DS model is running under $OTHER_LAUNCHD_LABEL (pid $OTHER_SERVER_PID)." >&2
    echo "Stop it with its matching stop alias before starting GLM-5.3-Flash." >&2
    exit 1
  fi
fi

# Also reject an unrelated/manual listener. The only listener this launcher
# may replace is the PID already registered under its own launchd label.
if command -v lsof >/dev/null 2>&1; then
  while IFS= read -r listener_pid; do
    if [[ "$listener_pid" =~ ^[1-9][0-9]*$ ]] &&
       [ "$listener_pid" != "${OLD_SERVER_PID:-}" ]; then
      echo "Port $PORT is already owned by pid $listener_pid; not starting GLM-5.3-Flash." >&2
      exit 1
    fi
  done < <(lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | sort -u)
fi

# Refuse to kill an unrelated/manual DS process. The instance lock records
# its owner, while this launcher only owns the PID registered under its label.
if [ -z "$OLD_SERVER_PID" ] && [ -r "$LOCK_FILE" ]; then
  read -r lock_owner < "$LOCK_FILE" || true
  if [[ "${lock_owner:-}" =~ ^[1-9][0-9]*$ ]] &&
     kill -0 "$lock_owner" >/dev/null 2>&1; then
    echo "DS pid $lock_owner is running outside $LAUNCHD_LABEL; not stopping it." >&2
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
    echo "DS pid $OLD_SERVER_PID did not stop cleanly; refusing to start a second model." >&2
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
  --host "$HOST"
  --port "$PORT"
  --ctx "$CTX_DS4"
  --tokens "$TOKENS_DS4"
  --kv-disk-dir "$KV_DIR"
  --kv-disk-space-mb "$DISK_MB"
  --kv-cache-cold-max-tokens "$COLD_MAX_TOKENS"
  --kv-cache-continued-interval-tokens "$SAVE_INTERVAL"
  --warm-weights
)

if [ "$MTP" = "1" ]; then
  args+=(--mtp --mtp-timing)
fi

if [ "$VISION" = "1" ]; then
  args+=(--vision "$VISION_MODEL")
fi

case "$MODE" in
  batched)
    if [ "$BATCHED_SESSIONS" -le 0 ]; then
      echo "--batched requires a positive resident session count." >&2
      exit 2
    fi
    args+=(
      --batched-session "$BATCHED_SESSIONS"
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

if [ "$MTP" = "1" ]; then
  MTP_DESC="on (model-embedded, timing)"
else
  MTP_DESC="off"
fi

echo "Starting DS GLM-5.3-Flash Q4_K on ${HOST}:${PORT}..."
echo "   Mode:        $MODE"
echo "   Model:       $MODEL"
echo "   Context:     $CTX_DS4"
echo "   Tokens:      $TOKENS_DS4"
echo "   Mixed q:     $SERVER_MIXED_PREFILL_QUANTUM tokens (while decoding)"
echo "   KV dir:      $KV_DIR"
echo "   KV budget:   $DISK_MB MiB"
echo "   Checkpoints: every $SAVE_INTERVAL tokens"
echo "   Cold anchors: prompts up to $COLD_MAX_TOKENS tokens"
echo "   KV rewind:   $KV_REWIND_REUSE (GLM live-prefix reuse; 0 = disabled)"
echo "   MTP:         $MTP_DESC"
echo "   Vision:      $VISION ($VISION_MODEL)"
echo "   Timing logs: $PREFILL_TIMING"
if [ "$MODE" = "batched" ]; then
  echo "   Sessions:    $BATCHED_SESSIONS resident batched sessions"
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
  env
  "DS4_LOCK_FILE=$LOCK_FILE"
  "DS4_KV_REWIND_REUSE=$KV_REWIND_REUSE"
)
if [ "$PREFILL_TIMING" = "1" ]; then
  launch_args+=("DS4_PREFILL_TIMING=1")
fi
if [ "$SERVER_BATCH_LOG" = "1" ]; then
  launch_args+=("DS4_SERVER_BATCH_LOG=1")
fi
launch_args+=("$RUNNER" "$BIN" "${args[@]}")

launchctl submit -l "$LAUNCHD_LABEL" -o "$LOG_DEST" -e "$LOG_DEST" -- \
  "${launch_args[@]}"

wait_for_server

SERVER_PID="$(launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null \
  | awk '/^[[:space:]]*pid = / { print $3; exit}')"
SERVER_PID="${SERVER_PID:-unknown}"

echo ""
echo "DS GLM-5.3-Flash is live."
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
