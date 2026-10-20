#!/usr/bin/env bash
# Cases for check-scope.sh: what it must report and what it must let pass.
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
  if bash "$here/check-scope.sh" "$file" > "$work/out" 2>&1; then got=clean; else got=reported; fi
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want, got $got" >&2
    cat "$work/out" >&2
    failures=$((failures + 1))
  fi
}

expect reported template-reads-a-flow-required-input 'version: "3"
vars:
  _A_PREFIX: "{{.APP_PREFIX | default \"x\"}}"
tasks:
  t:
    requires: { vars: [APP_PREFIX] }'

expect reported block-list-requires 'version: "3"
vars:
  _A_PREFIX: "{{.APP_PREFIX}}"
tasks:
  t:
    requires:
      vars:
        - APP_PREFIX'

expect reported enum-requires 'version: "3"
vars:
  _A_MODE: "{{.MODE}}"
tasks:
  t:
    requires:
      vars:
        - name: MODE
          enum: [a, b]'

expect reported sh-reads-a-required-input 'version: "3"
vars:
  _A_X:
    sh: echo {{.TARGET | q}}
tasks:
  t:
    requires: { vars: [TARGET] }'

expect reported ref-reads-a-required-input 'version: "3"
vars:
  _A_LIST:
    ref: default (list) .TARGETS
tasks:
  t:
    requires: { vars: [TARGETS] }'

expect clean read-where-it-is-used 'version: "3"
vars:
  _A_NS: "{{.NAMESPACE | default \"default\"}}"
tasks:
  t:
    requires: { vars: [APP_PREFIX] }
    cmds:
      - echo {{.APP_PREFIX | q}}'

expect clean a-longer-name-is-another-input 'version: "3"
vars:
  _A_X: "{{.TARGET_PORT}}"
tasks:
  t:
    requires: { vars: [TARGET] }'

[ "$failures" = 0 ]
