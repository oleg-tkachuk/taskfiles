#!/usr/bin/env bash
# Cases for renovate-require-token.sh: an empty token fails and says which.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
failures=0

# expect <pass|fail> <name> <token>
expect() {
  want=$1 name=$2
  if out=$(RENOVATE_TOKEN=$3 bash "$here/renovate-require-token.sh" 2>&1); then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want, got $got" >&2
    failures=$((failures + 1))
  fi
  if [ "$want" = fail ] && ! grep -q 'gh secret set RENOVATE_TOKEN --env renovate' <<< "$out"; then
    printf '%s\n' "✖ $name: the failure does not say how to set the secret" >&2
    failures=$((failures + 1))
  fi
}

expect pass token-set   'a-token'
expect fail token-empty ''

[ "$failures" = 0 ]
