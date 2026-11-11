#!/usr/bin/env bash
# Cases for check-api.sh: what it must report and what it must let pass.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A git hook runs this with GIT_DIR and friends pointing at the real
# repository; inherited, they would turn the fixture's git calls on it.
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)

failures=0

# The release every case compares against: a task with an alias, an internal
# task, an input read through default, a parameter passed between tasks, and
# a loop over ITEM.
readonly BASE='version: "3"
tasks:
  build:
    desc: build
    aliases: [compile]
    cmds:
      - echo {{.PORT | default "80" | q}}
      - task: _run
        vars: { REF: x }
      - for: [a]
        cmd: echo {{.ITEM | q}}
  _run:
    internal: true
    cmds:
      - echo {{.REF | q}}'

repo="$work/repo"
git init -q --initial-branch=main "$repo"
mkdir -p "$repo/m"
printf '%s\n' "$BASE" > "$repo/m/Taskfile.yaml"
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -qm base
git -C "$repo" tag v1.0.0

# expect <reported|clean> <name> <allowlist> <taskfile body, or - for none>
expect() {
  want=$1 name=$2 allowed=$3 body=$4
  if [ "$body" = - ]; then rm -f "$repo/m/Taskfile.yaml"; else printf '%s\n' "$body" > "$repo/m/Taskfile.yaml"; fi
  if (cd "$repo" && API_DEFAULTS_CHANGED=${defaults_changed-} bash "$here/check-api.sh" v1.0.0 "$allowed" m/Taskfile.yaml) > "$work/out" 2>&1; then got=clean; else got=reported; fi
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want, got $got" >&2
    cat "$work/out" >&2
    failures=$((failures + 1))
  fi
}

expect clean unchanged '' "$BASE"

expect clean task-renamed-keeping-its-old-name-as-an-alias '' "${BASE/  build:
    desc: build
    aliases: \[compile\]/  make:
    desc: build
    aliases: [build, compile]}"

expect reported task-renamed-without-an-alias '' "${BASE/  build:/  make:}"

expect reported alias-dropped '' "${BASE/    aliases: \[compile\]
/}"

expect clean removal-named-in-the-allowlist 'm:compile' "${BASE/    aliases: \[compile\]
/}"

expect reported stale-allowlist-entry 'm:nothing' "$BASE"

expect clean input-renamed-keeping-its-old-name '' "${BASE/.PORT | default \"80\"/.LISTEN_PORT | default .PORT | default \"80\"}"

expect reported input-dropped '' "${BASE/.PORT | default \"80\" | q/\"80\"}"

expect clean internal-task-renamed '' "${BASE//_run/_go}"

expect clean parameter-between-tasks-renamed '' "${BASE//REF/TARGET}"

loop='      - for: [a]
        cmd: echo {{.ITEM | q}}
'
expect clean loop-removed '' "${BASE/"$loop"/}"

# A string that becomes a list keeps its name and changes what a consumer has
# to pass: the default says so, and the change has to be named.
moved="${BASE/.PORT | default \"80\" | q/._PORTS | join \" \" | q}
vars:
  _PORTS:
    ref: 'default (list \"80\") .PORT'"
expect reported input-moved-into-a-list-ref '' "$moved"
defaults_changed='m:PORT' expect clean input-moved-into-a-list-ref-and-named '' "$moved"

expect reported default-changed '' "${BASE/default \"80\"/default \"8080\"}"
if grep -qF 'PORT defaulted to "80" in v1.0.0 and to "8080" now' "$work/out"; then
  printf '%s\n' "✔ default-changed: names both defaults"
else
  printf '%s\n' "✖ default-changed: the report does not name both defaults" >&2; cat "$work/out" >&2; failures=$((failures + 1))
fi
defaults_changed='m:PORT' expect clean default-changed-and-named '' "${BASE/default \"80\"/default \"8080\"}"
defaults_changed='m:PORT' expect reported stale-default-entry '' "$BASE"
# An input that gains a default asks nothing of anyone; one that loses its
# default now has to be set.
expect clean default-added '' "${BASE/.REF | q/.REF | q}
      - echo {{.EXTRA | default \"x\" | q}}"
# Naming the literal as one of the module's own constants changes nothing, and
# neither does an empty default, which is no default at all.
expect clean default-moved-into-a-constant '' "${BASE/default \"80\"/default ._M_PORT}
vars:
  _M_PORT: \"80\""
expect reported default-changed-through-a-constant '' "${BASE/default \"80\"/default ._M_PORT}
vars:
  _M_PORT: \"8080\""
expect clean empty-default-added '' "${BASE/.REF | q/.REF | default \"\" | q}"
expect reported default-removed '' "${BASE/.PORT | default \"80\" | q/.PORT | q}"

expect reported input-dropped-from-a-list-ref '' "${BASE/.PORT | default \"80\" | q/._PORTS | join \" \" | q}
vars:
  _PORTS:
    ref: 'list \"80\"'"

expect clean task-added '' "$BASE
  test:
    desc: test
    cmds: [echo]"

expect reported module-removed '' -

expect clean module-removed-and-named 'm:*' -

# A module the release never had is new, not lost: nothing to compare.
printf '%s\n' "$BASE" > "$repo/m/Taskfile.yaml"
mkdir -p "$repo/n"
printf '%s\n' "$BASE" > "$repo/n/Taskfile.yaml"
if (cd "$repo" && bash "$here/check-api.sh" v1.0.0 '' m/Taskfile.yaml n/Taskfile.yaml) > "$work/out" 2>&1; then
  printf '%s\n' "✔ module-added: clean"
else
  printf '%s\n' "✖ module-added: want clean, got reported" >&2
  cat "$work/out" >&2
  failures=$((failures + 1))
fi

# An API_REMOVED entry for a module the release never had is stale, and is
# said to be: git show failing on it must not be the script's own exit.
if (cd "$repo" && bash "$here/check-api.sh" v1.0.0 'gone:*' m/Taskfile.yaml) > "$work/out" 2>&1; then
  printf '%s\n' "✖ stale-entry-for-a-module-never-released: want reported, got clean" >&2
  failures=$((failures + 1))
elif grep -qF 'API_REMOVED: gone:* is not in v1.0.0' "$work/out"; then
  printf '%s\n' "✔ stale-entry-for-a-module-never-released: reported"
else
  printf '%s\n' "✖ stale-entry-for-a-module-never-released: failed without naming the entry" >&2
  cat "$work/out" >&2
  failures=$((failures + 1))
fi

# api-base.sh: which release a tree is compared against. On a commit after a
# tag it is that tag; on the tag itself it is the release before, or a release
# would be compared with itself and every allowlist entry it carries would
# read as shipped.
tags="$work/tags"
git init -q --initial-branch=main "$tags"
commit() { git -C "$tags" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "$1"; }

# base_is <want, or - for a failure> <name>
base_is() {
  want=$1 name=$2
  got=$(cd "$tags" && bash "$here/api-base.sh" 2>/dev/null) || got=-
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want, got $got" >&2
    failures=$((failures + 1))
  fi
}

commit first
base_is - base-with-no-release-tag
git -C "$tags" tag v1.0.0
base_is v1.0.0 base-on-the-first-release-is-itself
commit second
base_is v1.0.0 base-after-a-release-is-that-release
git -C "$tags" tag not-a-release
base_is v1.0.0 base-ignores-a-tag-that-is-not-a-release
git -C "$tags" tag v1.1.0
base_is v1.0.0 base-on-a-release-tag-is-the-release-before
commit third
base_is v1.1.0 base-after-the-next-release-is-that-release

[ "$failures" = 0 ] || exit 1
