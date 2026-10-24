#!/usr/bin/env bash
# Report a module var that is not <_PREFIX_>-scoped, and a module that uses
# two prefixes.
#
# A var declared in an included Taskfile shadows the including file's value of
# the same name, and every include shares one namespace: a module declaring
# PROJECT_NAME would override every consumer's. So every top-level var carries
# the module's own prefix.
#
# A task's own vars are scoped to the task, but a caller's var of the same name
# still overrides them: `task auth:mint-token ALG=x` would bypass JWT_ALG, the
# input ALG was derived from. So a task var is prefixed too, unless it IS the
# input — `PORT: '{{.PORT | default "8080"}}'` — and a caller setting it is
# the point.
#
# Usage: check-vars.sh <Taskfile>...   (exit 1 when anything is reported)
set -euo pipefail

command -v yq >/dev/null || { printf '%s\n' "yq is not installed — https://github.com/mikefarah/yq#install" >&2; exit 2; }

# A prefix: underscore, capitals or digits, underscore.
readonly prefixed='^_[A-Z0-9]+_'

found=0
for file in "$@"; do
  top=$(yq -r '.vars // {} | keys | .[]' "$file")
  # "<task>\t<var>\t<value>", the value empty when it is not a plain string.
  # Joined by hand: @tsv quotes a field holding a double quote.
  tasks=$(yq -r '.tasks // {} | to_entries[] | select(.value | type == "!!map") | .key as $t
                 | .value.vars // {} | to_entries[]
                 | $t + "\t" + .key + "\t" + ((select(.value | type == "!!str") | .value) // "")' "$file")

  bare=$(printf '%s\n' "$top" | grep -vE "$prefixed" | grep . || true)
  if [ -n "$bare" ]; then
    printf '%s: declares vars that are not <_PREFIX_>-scoped:\n' "$file"
    printf '    %s\n' $bare
    found=1
  fi

  task_prefixed=""
  while IFS=$'\t' read -r task name value; do
    [ -n "$task" ] || continue
    if printf '%s' "$name" | grep -qE "$prefixed"; then
      task_prefixed="$task_prefixed$name"$'\n'
      continue
    fi
    # The input itself: its value reads the same name first.
    case "$value" in
      "{{.$name}}" | "{{.$name |"* | "{{.$name|"*) continue ;;
    esac
    printf '%s: task %s declares %s, derived from another input — prefix it\n' "$file" "$task" "$name"
    found=1
  done <<< "$tasks"

  prefixes=$(printf '%s\n%s' "$top" "$task_prefixed" | sed -nE 's/^(_[A-Z0-9]+_).*/\1/p' | sort -u)
  if [ "$(printf '%s\n' "$prefixes" | grep -c .)" -gt 1 ]; then
    printf '%s: mixes prefixes: %s\n' "$file" "$(printf '%s ' $prefixes)"
    found=1
  fi
done

# ─── reads across modules ─────────────────────────────────────────────────────
# Every include shares one namespace, so a module can read what another
# declares — cosign and runtime act on the version release derived. That is a
# contract between two modules, and the module that declares the var names it
# on one comment line, as it does its shell-verbatim inputs:
#   # exports: _REL_VERSION _REL_IMAGE
# A read of another module's var it does not export is refused: renaming it is
# then a change nothing marks as crossing a boundary. So is a read of a
# prefixed var no module declares — it resolves to empty, without a word.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# "<var>\t<file>" for every var a module declares, at the top or in a task.
for file in "$@"; do
  yq -r '(.vars // {} | keys | .[]), (.tasks // {} | .[] | select(type == "!!map") | .vars // {} | keys | .[])' "$file" \
    | sed "s|\$|	$file|"
done | sort -u > "$work/declared"

for file in "$@"; do
  # Prefixed names this module's strings read: templates and ref: expressions.
  reads=$(yq -r '.. | select(tag == "!!str")' "$file" | grep -oE '\._[A-Z0-9]+_[A-Z0-9_]*' | cut -c2- | sort -u || true)
  for name in $reads; do
    owners=$(awk -F'\t' -v n="$name" '$1 == n { print $2 }' "$work/declared")
    if printf '%s\n' "$owners" | grep -qxF -- "$file"; then continue; fi
    if [ -z "$owners" ]; then
      printf '%s: reads %s, which no module declares\n' "$file" "$name"
      found=1
      continue
    fi
    for owner in $owners; do
      exports=$(awk -F': ' '/^# exports: /{print $2}' "$owner" | tr '\n' ' ')
      case " $exports " in
        *" $name "*) ;;
        *) printf '%s: reads %s from %s, which does not export it\n' "$file" "$name" "$owner"; found=1 ;;
      esac
    done
  done
done

exit "$found"
