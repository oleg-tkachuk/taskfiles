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
  if (cd "$repo" && bash "$here/check-api.sh" v1.0.0 "$allowed" m/Taskfile.yaml) > "$work/out" 2>&1; then got=clean; else got=reported; fi
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

expect clean input-moved-into-a-list-ref '' "${BASE/.PORT | default \"80\" | q/._PORTS | join \" \" | q}
vars:
  _PORTS:
    ref: 'default (list \"80\") .PORT'"

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

[ "$failures" = 0 ] || exit 1
