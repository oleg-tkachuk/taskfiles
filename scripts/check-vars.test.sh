#!/usr/bin/env bash
# Cases for check-vars.sh: what it must report and what it must let pass.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0

# expect <reported|clean> <name> <taskfile body>
expect() {
  want=$1 name=$2 body=$3
  file="$work/$name.yaml"
  printf '%s\n' "$body" > "$file"
  if bash "$here/check-vars.sh" "$file" > "$work/out" 2>&1; then got=clean; else got=reported; fi
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want, got $got" >&2
    cat "$work/out" >&2
    failures=$((failures + 1))
  fi
}

expect clean prefixed-module-vars 'version: "3"
vars:
  _GO_PKG: x
  _GO_OK: y'

expect reported bare-module-var 'version: "3"
vars:
  PROJECT_NAME: x'

expect reported two-prefixes 'version: "3"
vars:
  _GO_PKG: x
  _REL_IMAGE: y'

expect clean prefixed-task-var 'version: "3"
vars:
  _AUTH_OK: x
tasks:
  t:
    vars:
      _AUTH_ALG: "{{.JWT_ALG | default \"HS256\"}}"'

expect clean task-var-that-is-its-own-input 'version: "3"
tasks:
  t:
    vars:
      PORT: "{{.PORT | default \"8080\"}}"
      REF: "{{.REF}}"'

expect reported task-var-derived-from-another-input 'version: "3"
tasks:
  t:
    vars:
      ALG: "{{.JWT_ALG | default \"HS256\"}}"'

expect reported task-var-from-a-command 'version: "3"
tasks:
  t:
    vars:
      REPO:
        sh: gh repo view'

expect reported task-var-prefix-differs-from-the-module 'version: "3"
vars:
  _GO_OK: x
tasks:
  t:
    vars:
      _REL_X: y'

[ "$failures" = 0 ]
