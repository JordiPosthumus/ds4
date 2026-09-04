#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

export DS4_MODEL="${DS4_GLM53F_MODEL:-$SCRIPT_DIR/gguf/GLM-5.3-Flash-Q4_K.gguf}"
export DS4_KV_DIR="${DS4_GLM53F_KV_DIR:-/tmp/ds4-kv-batched}"
export DS4_LAUNCHD_LABEL="com.vonbling.ds-glm53"
export DS4_OTHER_LAUNCHD_LABEL="com.vonbling.ds4-0731"
export DS4_LOCK_FILE="/tmp/ds4-glm53f-server.lock"
export DS4_LOG_FILE="/tmp/ds4-glm53f-start.log"

exec "$SCRIPT_DIR/ds-startup.sh" "$@"
