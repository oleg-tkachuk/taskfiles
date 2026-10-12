#!/usr/bin/env bash
# Verify: cosign no-ops cleanly with no key and no binary
set -euo pipefail
COSIGN_SIGN=0 task cosign:sign cosign:verify
echo "✔ cosign no-ops without a key, syft or the cosign binary"
