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
# A default is a public name's other half: the value every consumer who never
# set the input runs with. One that changes reaches them all on the next bump,
# with no line of theirs to point at, so it is reported unless
# API_DEFAULTS_CHANGED names the input, <module>:<INPUT>. A default the base
# did not have is not reported: an input that gains one asks nothing of
# anyone. An entry whose default is the base's again is stale, as above.
#
# Usage: [API_DEFAULTS_CHANGED="<allowlist>"] check-api.sh <base ref> "<allowlist>" <Taskfile>...
#        (exit 1 when anything is reported)
set -euo pipefail

command -v yq >/dev/null || { printf '%s\n' "yq is not installed — https://github.com/mikefarah/yq#install" >&2; exit 2; }

base=$1 allowed=$2
shift 2
defaults_changed=${API_DEFAULTS_CHANGED-}

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

# templates — every template the Taskfile on stdin holds, one string per
# line group: template actions in any string, and `ref:` expressions.
templates() {
  local yaml
  yaml=$(cat)
  [ -n "$yaml" ] || return 0
  printf '%s\n' "$yaml" | yq -r '.. | select(tag == "!!str")'
  printf '%s\n' "$yaml" | yq -r '[.vars // {}, (.tasks // {} | .[] | select(type == "!!map") | .vars // {})] | .[] | .[] | select(type == "!!map") | .ref // ""'
}

# defaults — "<input><TAB><default>" for each default the Taskfile on stdin
# reads an input with, in both forms a template takes: `.NAME | default X`
# and, in a ref, `default X .NAME`. X is a quoted string, a parenthesised
# expression, or one word such as another variable. A default that is one of
# the module's own constants — `default ._GO_TIMEOUT`, a top-level var holding
# a plain string — is read as that string, so naming a literal changes nothing.
defaults() {
  local yaml name value constant
  yaml=$(cat)
  [ -n "$yaml" ] || return 0
  printf '%s\n' "$yaml" | templates | perl -ne '
    my $value = qr/"(?:[^"\\]|\\.)*"|\([^)]*\)|[^\s|})]+/;
    # A lookahead, so the value of one default can be the input of the next:
    # `.NEW | default .OLD | default "d"` reads OLD with a default too.
    while (/(?<![A-Za-z0-9_.])\.([A-Z][A-Z0-9_]*)(?=\s*\|\s*default\s+($value))/g) { print "$1\t$2\n" }
    while (/\bdefault\s+("(?:[^"\\]|\\.)*"|\([^)]*\))\s+\.([A-Z][A-Z0-9_]*)\b/g) { print "$2\t$1\n" }
  ' | while IFS=$'\t' read -r name value; do
    case "$value" in
      ._*)
        constant=$(printf '%s\n' "$yaml" | NAME=${value#.} yq -r '.vars[strenv(NAME)] | select(tag == "!!str")')
        case "$constant" in
          '' | *'{{'*) ;;
          *) value="\"$constant\"" ;;
        esac
        ;;
    esac
    # An empty default is no default: `.X | default ""` reads what `.X` does.
    [ "$value" = '""' ] || printf '%s\t%s\n' "$name" "$value"
  done | sort -u
}

# default_of <defaults> <input> — the defaults one input is read with, joined.
default_of() {
  printf '%s\n' "$1" | awk -F'\t' -v n="$2" '$1 == n { out = out (out == "" ? "" : " | ") $2 } END { print out }'
}

changed_listed() { case " $defaults_changed " in *" $1 "*) return 0 ;; esac; return 1; }

found=0
report() { printf '%s\n' "$*"; found=1; }

listed() { case " $allowed " in *" $1 "*) return 0 ;; esac; return 1; }

for file in "$@"; do
  module=${file%/Taskfile.yaml}
  # A file the base does not have fails git show, which pipefail would turn
  # into this script's own exit: a new module is nothing to compare.
  before=$( { git show "$base:$file" 2>/dev/null || true; } | names | sort -u)
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

  # Inputs both trees have, read with another default now.
  was=$( { git show "$base:$file" 2>/dev/null || true; } | defaults)
  is=$(defaults < "$file")
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    printf '%s\n' "$now" | grep -qxF -- "$name" || continue
    old=$(default_of "$was" "$name") new=$(default_of "$is" "$name")
    if [ "$old" = "$new" ]; then
      if changed_listed "$module:$name"; then
        report "API_DEFAULTS_CHANGED: $module:$name defaults to what $base has — the change has shipped, or was undone; drop the entry"
      fi
      continue
    fi
    changed_listed "$module:$name" && continue
    report "$module: $name defaulted to $old in $base and to ${new:-nothing} now — every consumer who never set it gets the new one; name $module:$name in API_DEFAULTS_CHANGED, say it under Consumer impact, and mark the commit ! if a consumer relying on the old one has to act"
  done < <(printf '%s\n' "$was" | cut -f1 | sort -u)
done

for entry in $allowed; do
  module=${entry%%:*} name=${entry#*:}
  had=$( { git show "$base:$module/Taskfile.yaml" 2>/dev/null || true; } | names | sort -u)
  if [ -z "$had" ] || { [ "$name" != "$WHOLE" ] && ! printf '%s\n' "$had" | grep -qxF -- "$name"; }; then
    report "API_REMOVED: $entry is not in $base — the removal has shipped; drop the entry"
  fi
done

exit "$found"
