#!/usr/bin/env bash
# Report a public name the latest release had and this tree has lost.
#
# A consumer calls a module's tasks and aliases and sets its inputs by name.
# One that vanishes reaches consumers as whatever release the commits make it,
# and without a `!` that is a minor — which breaks them. A rename keeps the old
# name, as an alias or as `default .OLD`, for a major (RELEASE.md), so only a
# deliberate removal loses one, and that is named in the allowlist.
#
# Names compared, per module:
#   tasks and their aliases, less internal ones;
#   inputs — every unprefixed upper-case name a template reads, less Task's own
#   variables and the parameters a module passes between its own tasks.
#
# An allowlist entry is <module>:<name>, or <module>:* for a whole module. One
# whose name the base no longer has is stale — the major that removed it has
# shipped — and is reported, so the list empties itself.
#
# Usage: check-api.sh <base ref> "<allowlist>" <Taskfile>...   (exit 1 when anything is reported)
set -euo pipefail

command -v yq >/dev/null || { printf '%s\n' "yq is not installed — https://github.com/mikefarah/yq#install" >&2; exit 2; }

base=$1 allowed=$2
shift 2

# Variables Task itself provides: no consumer sets them.
readonly BUILTINS='ITEM KEY TASK ALIAS ROOT_DIR ROOT_TASKFILE TASKFILE TASKFILE_DIR TASK_DIR USER_WORKING_DIR CHECKSUM TIMESTAMP MATCH EXIT_CODE CLI_ARGS CLI_ARGS_LIST CLI_FORCE CLI_SILENT CLI_VERBOSE CLI_OFFLINE CLI_ASSUME_YES TASK_VERSION TASK_EXE'
# Marks an allowlist entry that covers a whole module.
readonly WHOLE='*'

# names — the public names in the Taskfile on stdin, one per line.
names() {
  local yaml params
  yaml=$(cat)
  [ -n "$yaml" ] || return 0
  printf '%s\n' "$yaml" | yq -r '.tasks // {} | to_entries[] | select((.value | select(type == "!!map") | .internal) != true) | [.key] + ((.value | select(type == "!!map") | .aliases) // []) | .[]'
  params=$(printf '%s\n' "$yaml" | yq -r '.tasks // {} | .[] | select(type == "!!map") | ((.cmds // []) + (.deps // []))[] | select(type == "!!map") | .vars // {} | keys | .[]')
  # Template actions in any string, and `ref:` expressions, which are a
  # template without the braces — a list input is read only there.
  {
    printf '%s\n' "$yaml" | yq -r '.. | select(tag == "!!str")' | grep -oE '\{\{[^}]*\}\}' || true
    printf '%s\n' "$yaml" | yq -r '[.vars // {}, (.tasks // {} | .[] | select(type == "!!map") | .vars // {})] | .[] | .[] | select(type == "!!map") | .ref // ""'
  } | grep -oE '(^|[^A-Za-z0-9_.])\.[A-Z][A-Z0-9_]*' | sed 's/^[^.]*\.//' \
    | grep -vxF -f <(printf '%s\n' $BUILTINS $params) || true
}

found=0
report() { printf '%s\n' "$*"; found=1; }

listed() { case " $allowed " in *" $1 "*) return 0 ;; esac; return 1; }

for file in "$@"; do
  module=${file%/Taskfile.yaml}
  before=$(git show "$base:$file" 2>/dev/null | names | sort -u)
  [ -n "$before" ] || continue
  now=$( { if [ -f "$file" ]; then names < "$file"; fi; } | sort -u)
  if [ -z "$now" ]; then
    listed "$module:$WHOLE" || report "$module: in $base and gone now — name $module:$WHOLE in API_REMOVED if that is deliberate"
    continue
  fi
  while IFS= read -r name; do
    listed "$module:$name" || listed "$module:$WHOLE" && continue
    case "$name" in
      [A-Z]*) keep="read it after the new name, {{.NEW | default .$name}}" ;;
      *) keep="keep it in the renamed task's aliases:" ;;
    esac
    report "$module: $name is in $base and gone now — $keep, or name $module:$name in API_REMOVED"
  done < <(comm -23 <(printf '%s\n' "$before") <(printf '%s\n' "$now"))
done

for entry in $allowed; do
  module=${entry%%:*} name=${entry#*:}
  had=$(git show "$base:$module/Taskfile.yaml" 2>/dev/null | names | sort -u)
  if [ -z "$had" ] || { [ "$name" != "$WHOLE" ] && ! printf '%s\n' "$had" | grep -qxF -- "$name"; }; then
    report "API_REMOVED: $entry is not in $base — the removal has shipped; drop the entry"
  fi
done

exit "$found"
