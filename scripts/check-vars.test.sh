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

# ─── reads across modules ─────────────────────────────────────────────────────
# expect_pair <reported|clean> <name> <declaring module body> <reading module body>
expect_pair() {
  want=$1 name=$2
  mkdir -p "$work/$name/a" "$work/$name/b"
  printf '%s\n' "$3" > "$work/$name/a/Taskfile.yaml"
  printf '%s\n' "$4" > "$work/$name/b/Taskfile.yaml"
  if bash "$here/check-vars.sh" "$work/$name/a/Taskfile.yaml" "$work/$name/b/Taskfile.yaml" > "$work/out" 2>&1; then got=clean; else got=reported; fi
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want, got $got" >&2
    cat "$work/out" >&2
    failures=$((failures + 1))
  fi
}

readonly READER='version: "3"
vars:
  _B_REF: "{{._A_VERSION}}"'

expect_pair clean exported-read '# exports: _A_VERSION
version: "3"
vars:
  _A_VERSION: "1"' "$READER"

expect_pair reported unexported-read 'version: "3"
vars:
  _A_VERSION: "1"' "$READER"

expect_pair reported read-of-a-var-nobody-declares 'version: "3"
vars:
  _A_OTHER: "1"' "$READER"

expect_pair reported read-through-a-ref '# exports: _A_VERSION
version: "3"
vars:
  _A_VERSION: "1"
  _A_LIST:
    ref: "list"' 'version: "3"
vars:
  _B_LIST:
    ref: "._A_LIST"'

expect_pair clean own-read-needs-no-export 'version: "3"
vars:
  _A_VERSION: "1"
  _A_TAG: "{{._A_VERSION}}"' 'version: "3"
vars:
  _B_X: "1"'

expect_pair clean comment-is-not-a-read 'version: "3"
vars:
  _A_VERSION: "1"' 'version: "3"
# reads nothing of _A_VERSION, only names it here
vars:
  _B_X: "1"'

[ "$failures" = 0 ]
