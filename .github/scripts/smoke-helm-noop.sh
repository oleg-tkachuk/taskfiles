#!/usr/bin/env bash
# Verify: helm no-ops cleanly with no cluster
set -euo pipefail
task helm:list
echo "✔ helm:list no-ops without a reachable cluster"
