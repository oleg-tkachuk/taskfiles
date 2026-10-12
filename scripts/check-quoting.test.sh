#!/usr/bin/env bash
# Cases for check-quoting.sh: what it must report and what it must let pass.
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
  if bash "$here/check-quoting.sh" "$file" > "$work/out" 2>&1; then got=clean; else got=reported; fi
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want, got $got" >&2
    cat "$work/out" >&2
    failures=$((failures + 1))
  fi
}

expect reported unquoted-in-cmd 'version: "3"
tasks:
  t:
    cmds:
      - echo "{{.NAME}}"'

expect clean quoted-in-cmd 'version: "3"
tasks:
  t:
    cmds:
      - echo {{.NAME | q}}'

expect clean quoted-in-range 'version: "3"
tasks:
  t:
    cmds:
      - echo {{range .LIST}}{{q .}} {{end}}'

expect clean glyph-constant 'version: "3"
tasks:
  t:
    cmds:
      - printf "%s\n" "{{._LIB_OK}} done"'

expect clean control-actions 'version: "3"
tasks:
  t:
    cmds:
      - "{{if .X}}true{{else}}false{{end}}"'

expect clean declared-verbatim '# shell-verbatim: _KUBECTL FLAGS
version: "3"
tasks:
  t:
    cmds:
      - "{{._KUBECTL}} get pods {{.FLAGS}}"'

expect reported only-declared-verbatim-is-exempt '# shell-verbatim: _KUBECTL
version: "3"
tasks:
  t:
    cmds:
      - "{{._KUBECTL}} get pods -n {{.NS}}"'

expect reported unquoted-in-cmd-map 'version: "3"
tasks:
  t:
    cmds:
      - cmd: test -n "{{.NAME}}"'

expect reported unquoted-in-precondition 'version: "3"
tasks:
  t:
    preconditions:
      - sh: test -f {{.FILE}}
        msg: missing'

expect reported unquoted-in-status 'version: "3"
tasks:
  t:
    status:
      - test -f {{.FILE}}'

expect reported unquoted-in-module-sh-var 'version: "3"
vars:
  OUT:
    sh: git describe {{.REF}}
tasks: {}'

expect reported unquoted-in-task-sh-var 'version: "3"
tasks:
  t:
    vars:
      OUT:
        sh: cat {{.FILE}}
    cmds:
      - echo ok'

expect clean messages-are-not-shell 'version: "3"
tasks:
  t:
    desc: "about {{.NAME}}"
    preconditions:
      - sh: "true"
        msg: "{{.NAME}} is missing"
    cmds:
      - echo ok'

[ "$failures" = 0 ] || exit 1
