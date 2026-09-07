#!/bin/bash
# Human and agent entry point. Signing/packaging remains in release.sh for CI.
set -euo pipefail
cd "$(dirname "$0")"
exec python3 scripts/publish-release.py "$@"
