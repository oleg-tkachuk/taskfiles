#!/usr/bin/env bash
# Cases for check-closed.sh: what it must report and what it must let pass.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0

# expect <reported|clean> <name> <taskfile body> [text the report must hold]
expect() {
  want=$1 name=$2 body=$3 text=${4:-}
  file="$work/$name.yaml"
  printf '%s\n' "$body" > "$file"
  if bash "$here/check-closed.sh" "$file" > "$work/out" 2>&1; then got=clean; else got=reported; fi
  if [ "$got" = "$want" ] && TEXT=$text awk 'ENVIRON["TEXT"] == "" || index($0, ENVIRON["TEXT"]) { found = 1 } END { exit !found && ENVIRON["TEXT"] != "" }' "$work/out"; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want${text:+ naming '$text'}, got $got" >&2
    cat "$work/out" >&2
    failures=$((failures + 1))
  fi
}

expect clean a-start-and-its-ok 'version: "3"
tasks:
  build:
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · build"
      - make
      - printf "%s\n" "{{._X_OK}} x · built"'

expect clean no-start-at-all 'version: "3"
tasks:
  build:
    cmds:
      - printf "%s\n" "{{._X_OK}} x · built"'

expect reported a-start-with-no-ok 'version: "3"
tasks:
  build:
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · build"
      - make' ':5: task build prints a start marker and no ok'

expect reported the-last-task-of-the-section 'version: "3"
tasks:
  build:
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · build"
vars:
  _X_NOTE: "{{._X_OK}}"' 'task build'

# An ok closes the task it is in, and no other.
expect reported an-ok-in-the-next-task 'version: "3"
tasks:
  build:
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · build"
  test:
    cmds:
      - printf "%s\n" "{{._X_OK}} x · tests pass"' 'task build'

expect reported an-ok-in-the-task-before 'version: "3"
tasks:
  test:
    cmds:
      - printf "%s\n" "{{._X_OK}} x · tests pass"
  build:
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · build"' 'task build'

expect reported a-prefix-with-a-digit 'version: "3"
tasks:
  roll:
    cmds:
      - printf "%s\n" "{{._K8S_RUN}} x · roll"' 'task roll'

expect clean an-interactive-task 'version: "3"
tasks:
  dev:
    interactive: true
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · dev server"
      - serve'

expect reported interactive-false 'version: "3"
tasks:
  dev:
    interactive: false
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · dev server"' 'task dev'

expect clean a-waiver-with-a-reason 'version: "3"
tasks:
  _matched:
    # start-only: a listing before a prompt
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · matches:"'

expect reported a-waiver-with-no-reason 'version: "3"
tasks:
  _matched:
    # start-only:
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · matches:"' 'task _matched'

# A waiver covers the task it is written in.
expect reported a-waiver-in-another-task 'version: "3"
tasks:
  _matched:
    # start-only: a listing before a prompt
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · matches:"
  build:
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · build"' 'task build'

expect clean a-start-in-a-comment 'version: "3"
tasks:
  build:
    cmds:
      # printf "%s\n" "{{._X_RUN}} x · build"
      - make'

expect reported an-ok-in-a-comment 'version: "3"
tasks:
  build:
    cmds:
      - printf "%s\n" "{{._X_RUN}} x · build"
      # printf "%s\n" "{{._X_OK}} x · built"' 'task build'

# A snippet in vars is not a task: the task that interpolates it is not read
# through it.
expect clean a-start-in-a-vars-snippet 'version: "3"
vars:
  _X_EACH: |
    printf "%s\n" "{{._X_RUN}} x · each"
tasks:
  build:
    cmds:
      - make'

[ "$failures" = 0 ]
