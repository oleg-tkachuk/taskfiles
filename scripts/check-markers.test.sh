#!/usr/bin/env bash
# Cases for check-markers.sh: what it must report and what it must let pass.
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
  if bash "$here/check-markers.sh" "$file" > "$work/out" 2>&1; then got=clean; else got=reported; fi
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want, got $got" >&2
    cat "$work/out" >&2
    failures=$((failures + 1))
  fi
}

expect clean every-marker 'version: "3"
vars:
  _X_RUN: '\''{{if .NO_COLOR}}◉ start ·{{else}}{{"\x1b[36m◉ start\x1b[0m ·"}}{{end}}'\''
  _X_OK: '\''{{if .NO_COLOR}}✔ ok    ·{{else}}{{"\x1b[32m✔ ok\x1b[0m    ·"}}{{end}}'\''
  _X_SKIP: '\''{{if .NO_COLOR}}○ skip  ·{{else}}{{"\x1b[90m○ skip\x1b[0m  ·"}}{{end}}'\''
  _X_WARN: '\''{{if .NO_COLOR}}▲ warn  ·{{else}}{{"\x1b[33m▲ warn\x1b[0m  ·"}}{{end}}'\''
  _X_ERR: '\''{{if .NO_COLOR}}✖ fail  ·{{else}}{{"\x1b[31m✖ fail\x1b[0m  ·"}}{{end}}'\''
tasks:
  t:
    cmds:
      - printf "%s\n" "{{._X_OK}} x · done"'

expect clean a-prefix-with-a-digit 'version: "3"
vars:
  _K8S_OK: '\''{{if .NO_COLOR}}✔ ok    ·{{else}}{{"\x1b[32m✔ ok\x1b[0m    ·"}}{{end}}'\'''

expect reported a-glyph-with-no-word 'version: "3"
vars:
  _X_OK: '\''{{if .NO_COLOR}}✔{{else}}{{"\x1b[32m✔\x1b[0m"}}{{end}}'\'''

expect reported another-word 'version: "3"
vars:
  _X_OK: '\''{{if .NO_COLOR}}✔ done  ·{{else}}{{"\x1b[32m✔ done\x1b[0m  ·"}}{{end}}'\'''

expect reported a-word-not-padded 'version: "3"
vars:
  _X_OK: '\''{{if .NO_COLOR}}✔ ok ·{{else}}{{"\x1b[32m✔ ok\x1b[0m ·"}}{{end}}'\'''

expect reported another-colour 'version: "3"
vars:
  _X_ERR: '\''{{if .NO_COLOR}}✖ fail  ·{{else}}{{"\x1b[33m✖ fail\x1b[0m  ·"}}{{end}}'\'''

expect reported the-word-of-another-marker 'version: "3"
vars:
  _X_WARN: '\''{{if .NO_COLOR}}✖ fail  ·{{else}}{{"\x1b[31m✖ fail\x1b[0m  ·"}}{{end}}'\'''

expect reported no-separator 'version: "3"
vars:
  _X_OK: '\''{{if .NO_COLOR}}✔ ok   {{else}}{{"\x1b[32m✔ ok\x1b[0m   "}}{{end}}'\'''

expect reported a-glyph-typed-into-a-line 'version: "3"
tasks:
  t:
    cmds:
      - echo "✖ it failed"'

expect clean a-glyph-in-a-comment 'version: "3"
tasks:
  t:
    # the deliberate ◉/✔/○ marker lines
    cmds:
      - "true"'

[ "$failures" = 0 ]
