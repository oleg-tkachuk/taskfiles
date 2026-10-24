# shellcheck shell=bash
# Helpers for the module behaviour tests. Sourced, not run.
#
# Each test builds a throwaway consumer that includes one module from this
# checkout, puts shims for the tools the module calls first on PATH, runs a
# task, and asserts on its exit code, its output and the argv the shims saw.
# No cluster, registry or cloud account is involved: what is under test is
# what the module does with its inputs, not the tool behind it.

set -euo pipefail

# A git hook runs `task lint` with GIT_DIR, GIT_INDEX_FILE and friends pointing
# at this repository. Inherited, they make every git call in a fixture act on
# the real repository instead of the consumer's: a `git init` there rewrites
# its config. So every one of them is cleared before a test touches git.
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# LIB_ROOT may point elsewhere, to run a case against an older module.
LIB_ROOT=${LIB_ROOT:-$(cd "$TESTS_DIR/.." && pwd)}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Where shims append the argv they were called with, one call per line.
CALLS="$WORK/calls.log"
BIN="$WORK/bin"
CONSUMER="$WORK/consumer"
OUT="$WORK/out"
mkdir -p "$BIN" "$CONSUMER"
: > "$CALLS"
export CALLS
export PATH="$BIN:$PATH"
export NO_COLOR=1

failures=0

# consumer <alias> <module> [include vars as a flow mapping]
# Writes a consumer Taskfile that includes one module under <alias>.
consumer() {
  alias=$1 module=$2 vars=${3:-"{}"}
  cat > "$CONSUMER/Taskfile.yaml" <<YAML
version: "3"
silent: true
includes:
  $alias: { taskfile: '$LIB_ROOT/$module', dir: ., vars: $vars }
YAML
}

# shim <name> <body>
# Installs an executable called <name> whose script is <body>. Every call is
# logged to $CALLS as "<name> <argv...>" before the body runs.
shim() {
  name=$1 body=$2
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "printf '%s\n' \"$name \$*\" >> \"\$CALLS\""
    printf '%s\n' "$body"
  } > "$BIN/$name"
  chmod +x "$BIN/$name"
}

# run_task <args...> — runs task in the consumer, capturing output and status.
run_task() {
  status=0
  (cd "$CONSUMER" && task --yes "$@") < /dev/null > "$OUT" 2>&1 || status=$?
  printf '%s' "$status" > "$WORK/last-status"
}

last_status() { cat "$WORK/last-status"; }

pass() { printf '%s\n' "✔ $1"; }

fail() {
  printf '%s\n' "✖ $1" >&2
  sed 's/^/    | /' "$OUT" >&2
  failures=$((failures + 1))
}

# expect_status <ok|fail> <case name>
expect_status() {
  want=$1 name=$2
  if [ "$want" = ok ] && [ "$(last_status)" = 0 ]; then pass "$name"; return; fi
  if [ "$want" = fail ] && [ "$(last_status)" != 0 ]; then pass "$name"; return; fi
  fail "$name: want $want, exit status $(last_status)"
}

# expect_output <fixed string> <case name>
expect_output() {
  if grep -qF -- "$1" "$OUT"; then pass "$2"; else fail "$2: output lacks '$1'"; fi
}

# refute_output <fixed string> <case name>
refute_output() {
  if grep -qF -- "$1" "$OUT"; then fail "$2: output has '$1'"; else pass "$2"; fi
}

# expect_call <fixed string> <case name> — some shim call contains the string.
expect_call() {
  if grep -qF -- "$1" "$CALLS"; then pass "$2"; else fail "$2: no call with '$1'"; sed 's/^/    > /' "$CALLS" >&2; fi
}

# refute_call <fixed string> <case name>
refute_call() {
  if grep -qF -- "$1" "$CALLS"; then fail "$2: a call has '$1'"; sed 's/^/    > /' "$CALLS" >&2; else pass "$2"; fi
}

reset_calls() { : > "$CALLS"; }

# semver_cmp <a> <b> — prints -1, 0 or 1: a's precedence against b's, by
# SemVer 2.0.0 §11. Build metadata is ignored; the core compares numerically;
# a pre-release sorts below its release; pre-release identifiers compare left
# to right, numeric ones numerically and below alphanumeric ones, alphanumeric
# ones in ASCII order; with an equal prefix, more identifiers win.
semver_cmp() {
  local a=${1%%+*} b=${2%%+*} ap="" bp="" i s t n m
  [[ $a == *-* ]] && ap=${a#*-}
  [[ $b == *-* ]] && bp=${b#*-}
  local -a x y p r
  IFS=. read -ra x <<< "${a%%-*}"
  IFS=. read -ra y <<< "${b%%-*}"
  for i in 0 1 2; do
    if ((10#${x[i]} < 10#${y[i]})); then echo -1; return; fi
    if ((10#${x[i]} > 10#${y[i]})); then echo 1; return; fi
  done
  if [[ -z $ap && -z $bp ]]; then echo 0; return; fi
  if [[ -z $ap ]]; then echo 1; return; fi
  if [[ -z $bp ]]; then echo -1; return; fi
  IFS=. read -ra p <<< "$ap"
  IFS=. read -ra r <<< "$bp"
  n=${#p[@]} m=${#r[@]}
  for ((i = 0; i < n && i < m; i++)); do
    s=${p[i]} t=${r[i]}
    [[ $s == "$t" ]] && continue
    if [[ $s =~ ^[0-9]+$ && $t =~ ^[0-9]+$ ]]; then
      if ((10#$s < 10#$t)); then echo -1; else echo 1; fi
    elif [[ $s =~ ^[0-9]+$ ]]; then echo -1
    elif [[ $t =~ ^[0-9]+$ ]]; then echo 1
    elif [[ $(printf '%s\n%s\n' "$s" "$t" | LC_ALL=C sort | head -1) == "$s" ]]; then echo -1
    else echo 1
    fi
    return
  done
  if ((n < m)); then echo -1; elif ((n > m)); then echo 1; else echo 0; fi
}

# expect_before <a> <b> <case name> — a has lower SemVer precedence than b.
expect_before() {
  if [ "$(semver_cmp "$1" "$2")" = -1 ]; then pass "$3"; else fail "$3: $1 does not sort before $2"; fi
}

finish() { [ "$failures" = 0 ]; }
