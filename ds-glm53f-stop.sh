#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export DS4_LAUNCHD_LABEL="com.vonbling.ds-glm53"
export DS4_LOCK_FILE="/tmp/ds4-glm53f-server.lock"
export DS4_LOG_FILE="/tmp/ds4-glm53f-start.log"
export DS4_SERVICE_NAME="DS GLM-5.3-Flash"
exec "$SCRIPT_DIR/ds-stop.sh" "$@"
