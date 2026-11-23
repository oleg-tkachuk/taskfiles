#!/usr/bin/env bash
# Cases for embed-jq.sh: what --check must report and let pass, and what a
# rewrite must leave behind.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0

pass() { printf '%s\n' "✔ $1"; }
fail() {
  printf '%s\n' "✖ $1" >&2
  cat "$work/out" >&2
  failures=$((failures + 1))
}

# A program with what a copy most easily damages: a backslash escape, an
# interpolation, a dollar, a hash, both quotes, a blank line, closing braces.
PROGRAM='# rows of a listing
def cell($name): "\(.kind)\t\($name)";

def marked: . + " (it'\''s #1)";
{ a: { b: [.items[] | cell(.name) | marked] }}'

# module <name> <Taskfile body> [program] — a module directory with one
# Taskfile, and the program beside it as rows.jq: no file where it is "none",
# and a file of no lines where it is "empty".
module() {
  dir="$work/$1"
  mkdir -p "$dir"
  printf '%s\n' "$2" > "$dir/Taskfile.yaml"
  case "${3-$PROGRAM}" in
    none) ;;
    empty) : > "$dir/rows.jq" ;;
    *) printf '%s\n' "${3-$PROGRAM}" > "$dir/rows.jq" ;;
  esac
}

# expect <reported|clean> <name> <Taskfile body> [program]
expect() {
  want=$1 name=$2
  module "$name" "$3" ${4+"$4"}
  if bash "$here/embed-jq.sh" --check "$work/$name/Taskfile.yaml" > "$work/out" 2>&1; then got=clean; else got=reported; fi
  if [ "$got" = "$want" ]; then pass "$name: $got"; else fail "$name: want $want, got $got"; fi
}

# The block a rewrite must produce of PROGRAM.
EMBEDDED='  # jq-file: rows.jq
  _X_ROWS_JQ: |-
    # rows of a listing
    def cell($name): "\(.kind)\t\($name)";

    def marked: . + " (it'\''s #1)";
    { a: { b: [.items[] | cell(.name) | marked] }}'

expect clean no-marker 'version: "3"
tasks:
  t:
    cmds:
      - jq -r .name file.json'

expect clean a-block-that-is-its-file 'version: "3"
vars:
'"$EMBEDDED"'
  _X_AFTER: kept
tasks: {}'

expect clean a-block-that-ends-the-file 'version: "3"
vars:
'"$EMBEDDED"

# YAML drops the blank lines that end a block, so the file's are not asked for.
expect clean a-file-that-ends-in-blank-lines 'version: "3"
vars:
'"$EMBEDDED"'

tasks: {}' "$PROGRAM"'

'

expect reported a-line-changed 'version: "3"
vars:
  # jq-file: rows.jq
  _X_ROWS_JQ: |-
    # rows of a listing
    def cell($name): "\(.kind) \($name)";

    def marked: . + " (it'\''s #1)";
    { a: { b: [.items[] | cell(.name) | marked] }}
tasks: {}'

expect reported a-line-missing 'version: "3"
vars:
  # jq-file: rows.jq
  _X_ROWS_JQ: |-
    # rows of a listing
    def cell($name): "\(.kind)\t\($name)";
tasks: {}'

expect reported a-line-added 'version: "3"
vars:
'"$EMBEDDED"'
    | length
tasks: {}'

expect reported a-blank-line-dropped 'version: "3"
vars:
  # jq-file: rows.jq
  _X_ROWS_JQ: |-
    # rows of a listing
    def cell($name): "\(.kind)\t\($name)";
    def marked: . + " (it'\''s #1)";
    { a: { b: [.items[] | cell(.name) | marked] }}
tasks: {}'

expect reported a-file-that-is-not-there 'version: "3"
vars:
'"$EMBEDDED" none

# A block of no lines, of a file of none: equal, and still refused.
expect reported an-empty-file 'version: "3"
vars:
  # jq-file: rows.jq
  _X_ROWS_JQ: |-
tasks: {}' empty

expect reported a-file-task-would-template 'version: "3"
vars:
  # jq-file: rows.jq
  _X_ROWS_JQ: |-
    [{{"a": 1}}]
tasks: {}' '[{{"a": 1}}]'

expect reported a-marker-with-no-var 'version: "3"
vars:
  # jq-file: rows.jq
  _X_OTHER: plain
tasks: {}'

expect reported a-var-that-is-not-a-block 'version: "3"
vars:
  # jq-file: rows.jq
  _X_ROWS_JQ: >-
    .
tasks: {}'

expect reported a-marker-on-the-last-line 'version: "3"
vars:
  # jq-file: rows.jq'

# The file is there, and the block is it: the name alone is what is refused.
printf '%s\n' . > "$work/rows.jq"
expect reported a-file-outside-the-module 'version: "3"
vars:
  # jq-file: ../rows.jq
  _X_ROWS_JQ: |-
    .
tasks: {}'

expect reported jq-reading-a-file 'version: "3"
tasks:
  t:
    cmds:
      - jq -r -f rows.jq file.json'

expect reported jq-reading-a-file-among-short-flags 'version: "3"
tasks:
  t:
    cmds:
      - jq -rf rows.jq file.json'

expect reported jq-reading-a-library 'version: "3"
tasks:
  t:
    cmds:
      - kubectl get pods -o json | jq -L . "include \"rows\"; rows"'

expect clean a-flag-of-another-tool 'version: "3"
tasks:
  t:
    cmds:
      - jq -r .name file.json | xargs kubectl apply -f'

expect clean jq-reading-a-file-in-a-comment 'version: "3"
tasks:
  t:
    # not `jq -f rows.jq`: a consumer has no such file
    cmds:
      - "true"'

# A Taskfile named with no directory is read beside the file it names.
if (cd "$work/a-block-that-is-its-file" && bash "$here/embed-jq.sh" --check Taskfile.yaml) > "$work/out" 2>&1; then
  pass "a-taskfile-named-with-no-directory: clean"
else
  fail "a-taskfile-named-with-no-directory: want clean, got reported"
fi

# ─── a rewrite ───────────────────────────────────────────────────────────────
WANT='version: "3"
vars:
  _X_BEFORE: kept
'"$EMBEDDED"'

  _X_AFTER: kept
tasks: {}'

module rewrite 'version: "3"
vars:
  _X_BEFORE: kept
  # jq-file: rows.jq
  _X_ROWS_JQ: |-
    stale

    older

  _X_AFTER: kept
tasks: {}'
if bash "$here/embed-jq.sh" "$work/rewrite/Taskfile.yaml" > "$work/out" 2>&1 && [ "$(cat "$work/rewrite/Taskfile.yaml")" = "$WANT" ]; then
  pass "rewrite: the block becomes the file, and nothing else moves"
else
  cat "$work/rewrite/Taskfile.yaml" >> "$work/out"
  fail "rewrite: the block is not the file, or something else moved"
fi
if bash "$here/embed-jq.sh" --check "$work/rewrite/Taskfile.yaml" > "$work/out" 2>&1; then
  pass "rewrite: and --check then finds nothing"
else
  fail "rewrite: --check still reports the block"
fi
if [ -z "$(bash "$here/embed-jq.sh" "$work/rewrite/Taskfile.yaml" 2>&1)" ]; then
  pass "rewrite: a second run changes nothing"
else
  fail "rewrite: a second run rewrote the file again"
fi

module trailing 'version: "3"
vars:
  # jq-file: rows.jq
  _X_ROWS_JQ: |-
    stale

tasks: {}' "$PROGRAM"'

'
if bash "$here/embed-jq.sh" "$work/trailing/Taskfile.yaml" > "$work/out" 2>&1 \
   && [ -z "$(bash "$here/embed-jq.sh" "$work/trailing/Taskfile.yaml" 2>&1)" ] \
   && bash "$here/embed-jq.sh" --check "$work/trailing/Taskfile.yaml" > "$work/out" 2>&1; then
  pass "rewrite: a file that ends in blank lines settles in one run"
else
  fail "rewrite: a file that ends in blank lines is rewritten again, or still reported"
fi

module refused 'version: "3"
vars:
  # jq-file: rows.jq
  _X_ROWS_JQ: |-
    stale
tasks: {}' none
kept=$(cat "$work/refused/Taskfile.yaml")
if ! bash "$here/embed-jq.sh" "$work/refused/Taskfile.yaml" > "$work/out" 2>&1 && [ "$(cat "$work/refused/Taskfile.yaml")" = "$kept" ]; then
  pass "rewrite: a Taskfile whose file is missing is reported and left alone"
else
  fail "rewrite: a Taskfile whose file is missing was passed or rewritten"
fi

[ "$failures" = 0 ]
