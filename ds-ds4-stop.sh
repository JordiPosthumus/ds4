#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export DS4_LAUNCHD_LABEL="com.vonbling.ds4-0731"
export DS4_LOCK_FILE="/tmp/ds4-ds4-server.lock"
export DS4_LOG_FILE="/tmp/ds4-ds4-start.log"
export DS4_SERVICE_NAME="DS4 DeepSeek V4 Flash Vision-Exp"
exec "$SCRIPT_DIR/ds-stop.sh" "$@"
