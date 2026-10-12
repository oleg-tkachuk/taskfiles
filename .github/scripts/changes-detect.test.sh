#!/usr/bin/env bash
# Cases for changes-detect.sh: which changes let consumer-smoke skip.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# A git hook runs this with GIT_DIR set; the fixture repository is its own.
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)

git -C "$work" init -q
git -C "$work" config user.email test@example.invalid
git -C "$work" config user.name test
mkdir -p "$work/.github/workflows" "$work/.github/scripts" "$work/go"
touch "$work/README.md" "$work/.github/workflows/ci.yml" "$work/.github/scripts/smoke.sh" "$work/go/Taskfile.yaml"
git -C "$work" add -A && git -C "$work" commit -qm base
base=$(git -C "$work" rev-parse HEAD)

failures=0

# expect <true|false> <name> <file to change>...
expect() {
  want=$1 name=$2; shift 2
  git -C "$work" reset -q --hard "$base"
  for f in "$@"; do printf 'x\n' >> "$work/$f"; done
  git -C "$work" commit -qam "$name"
  : > "$work/out"
  (cd "$work" && BASE=$base HEAD=$(git rev-parse HEAD) EVENT=test GITHUB_OUTPUT="$work/out" \
    bash "$here/changes-detect.sh" >/dev/null)
  got=$(sed -n 's/^smoke_skippable=//p' "$work/out")
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: skippable=$got"
  else
    printf '%s\n' "✖ $name: want skippable=$want, got $got" >&2
    failures=$((failures + 1))
  fi
}

expect true docs-only README.md
expect true workflow-only .github/workflows/ci.yml
expect false a-smoke-script .github/scripts/smoke.sh
expect false a-smoke-script-beside-docs .github/scripts/smoke.sh README.md
expect false a-module go/Taskfile.yaml
expect false a-module-beside-a-workflow go/Taskfile.yaml .github/workflows/ci.yml

[ "$failures" = 0 ]
