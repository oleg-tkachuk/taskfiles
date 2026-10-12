#!/usr/bin/env bash
# Cases for check-renovate.sh: each silent Renovate failure it must report.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# A git hook runs this with GIT_DIR set; the fixture repository is its own.
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)

failures=0

# A copy of the real setup, in a repository of its own so `git ls-files`
# lists only the fixture.
fixture() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo/.github/workflows"
  cp "$repo/.github/renovate.json" "$repo/.github/release.yml" "$work/repo/.github/"
  cp "$repo/.github/workflows/renovate.yml" "$repo/.github/workflows/ci.yml" "$work/repo/.github/workflows/"
  cp "$repo/lefthook.yml" "$work/repo/"
}

# expect <reported|clean> <name> <shell run inside the fixture before the check>
expect() {
  want=$1 name=$2 change=$3
  fixture
  (cd "$work/repo" && eval "$change" && git init -q && git add -A)
  if bash "$here/check-renovate.sh" "$work/repo" > "$work/out" 2>&1; then got=clean; else got=reported; fi
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want, got $got" >&2
    cat "$work/out" >&2
    failures=$((failures + 1))
  fi
}

expect clean    as-shipped ':'
expect reported root-config-shadows 'printf "{}\n" > renovate.json'
expect reported pin-not-annotated \
  'perl -0pi -e "s/  # renovate: datasource=github-releases[^\n]*\n//" .github/workflows/ci.yml'
expect reported annotation-not-matched \
  'perl -0pi -e "s/run: pipx run zizmor==/run: pipx run --spec zizmor==/" lefthook.yml'
expect reported new-pin-not-annotated \
  'printf "env:\n  HELM_VERSION: 3.19.0\n" > .github/workflows/extra.yml'
expect reported author-check-dropped \
  'perl -0pi -e "s/ &&\n\s+github\.event\.issue\.user\.login == github\.repository_owner//" .github/workflows/renovate.yml'
expect reported command-not-allowed \
  'yq -i -p json -o json ".packageRules[0].postUpgradeTasks.commands = [\"bash regen.sh\"]" .github/renovate.json'
expect clean    command-allowed \
  'yq -i -p json -o json ".packageRules[0].postUpgradeTasks.commands = [\"bash regen.sh\"]" .github/renovate.json &&
   perl -0pi -e "s/RENOVATE_ALLOWED_COMMANDS: \x27\[\]\x27/RENOVATE_ALLOWED_COMMANDS: \x27[\"^bash regen\\\\\\\\.sh\\$\"]\x27/" .github/workflows/renovate.yml'
expect reported label-in-release-notes \
  'yq -i ".changelog.exclude.labels -= [\"dependencies\"]" .github/release.yml'

[ "$failures" = 0 ]
