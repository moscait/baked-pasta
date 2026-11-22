#!/usr/bin/env bash
# Convenience wrapper so the deployer can also be run from infrastructure/.
# All logic lives in ../deploy-ziti.sh; this file only forwards its arguments.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/deploy-ziti.sh" "$@"
