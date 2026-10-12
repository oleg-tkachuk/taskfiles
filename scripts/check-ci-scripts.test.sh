#!/usr/bin/env bash
# Cases for check-ci-scripts.sh: what it must report and what it must let pass.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0

# expect <reported|clean> <name> <workflow body> [script name...]
expect() {
  want=$1 name=$2 body=$3; shift 3
  rm -rf "$work/wf" "$work/scripts"
  mkdir -p "$work/wf" "$work/scripts"
  printf '%s\n' "$body" > "$work/wf/ci.yml"
  for s in "$@"; do printf '#!/usr/bin/env bash\ntrue\n' > "$work/scripts/$s"; done
  if bash "$here/check-ci-scripts.sh" "$work/wf" "$work/scripts" > "$work/out" 2>&1; then got=clean; else got=reported; fi
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want, got $got" >&2
    cat "$work/out" >&2
    failures=$((failures + 1))
  fi
}

expect clean one-command-and-a-script 'jobs:
  a:
    steps:
      - run: task lint
      - run: bash .github/scripts/smoke.sh' smoke.sh

expect clean a-script-under-a-subdirectory-checkout 'jobs:
  a:
    steps:
      - run: bash "$GITHUB_WORKSPACE/ci/.github/scripts/smoke.sh"' smoke.sh

expect reported a-multi-line-run 'jobs:
  a:
    steps:
      - run: |
          set -eu
          echo hi'

expect clean a-block-scalar-holding-one-command 'jobs:
  a:
    steps:
      - run: |
          echo hi'

expect clean an-escaped-newline-inside-one-command 'jobs:
  a:
    steps:
      - run: printf "%s\\n" done'

expect reported a-script-nothing-runs 'jobs:
  a:
    steps:
      - run: task lint' orphan.sh

expect reported a-step-running-a-missing-script 'jobs:
  a:
    steps:
      - run: bash .github/scripts/gone.sh'

expect clean a-test-beside-the-scripts 'jobs:
  a:
    steps:
      - run: task lint' x.test.sh

[ "$failures" = 0 ] || exit 1
