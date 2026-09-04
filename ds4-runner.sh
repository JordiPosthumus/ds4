#!/bin/bash

set -euo pipefail

# The Metal backend resolves its shader sources relative to the repository.
# launchd does not inherit the caller's working directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
exec "$@"
