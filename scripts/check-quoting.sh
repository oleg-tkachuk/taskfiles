#!/usr/bin/env bash
# Report every template action that reaches a shell unquoted.
#
# A value interpolated into a shell script is code unless it goes through
# `q` (shellQuote): inside double quotes a $(...) in it runs, and bare it is
# word-split and parsed. The library's own glyph constants and the inputs a
# module declares as shell on purpose are exempt; everything else that is not
# a template control action must be quoted.
#
# A module declares its shell-by-contract inputs on one comment line:
#   # shell-verbatim: _ARGO_KUBECTL _CMP_CMD
# A declared variable that the module defines as a script fragment is itself
# checked: being code does not excuse the data interpolated into it.
#
# Usage: check-quoting.sh <Taskfile>...   (exit 1 when anything is reported)
set -euo pipefail

command -v yq >/dev/null || { printf '%s\n' "yq is not installed — https://github.com/mikefarah/yq#install" >&2; exit 2; }

# Glyph constants: status markers built from NO_COLOR, never from input.
readonly glyph='^\._[A-Z0-9]+_(OK|ERR|RUN|SKIP|WARN|INFO)$'

# Every string a module hands to a shell: commands, preconditions, status
# checks, and dynamic (sh:) variables, at task and module level.
readonly shell_texts='
  ([.vars // {} | .[] | select(type == "!!map") | .sh // ""] +
   [.tasks // {} | .[] | (
      (.cmds // [])[] | select(type == "!!str"),
      (.cmds // [])[] | select(type == "!!map") | (.cmd // ""),
      (.preconditions // [])[] | select(type == "!!str"),
      (.preconditions // [])[] | select(type == "!!map") | (.sh // ""),
      (.status // [])[],
      (.vars // {} | .[] | select(type == "!!map") | .sh // "")
   )]) | .[] | select(. != "")'

found=0
for file in "$@"; do
  verbatim=$(awk -F': ' '/^# shell-verbatim: /{print $2}' "$file" | tr '\n' ' ')
  # The bodies of declared variables the module defines as plain strings.
  bodies=$(VERBATIM="$verbatim" yq -r '.vars // {} | to_entries[] | select(.value | type == "!!str") | select(.key as $k | strenv(VERBATIM) | split(" ") | any_c(. == $k)) | .value' "$file")
  { yq -r "$shell_texts" "$file"; printf '%s\n' "$bodies"; } | awk -v file="$file" -v glyph="$glyph" -v verbatim="$verbatim" '
    BEGIN { n = split(verbatim, v, " "); for (i = 1; i <= n; i++) allowed["." v[i]] = 1 }
    {
      line = $0
      while (match(line, /\{\{[^}]*\}\}/)) {
        action = substr(line, RSTART + 2, RLENGTH - 4)
        line = substr(line, RSTART + RLENGTH)
        gsub(/^-? +| +-?$/, "", action)
        # Control actions, comments and literals are not values.
        if (action ~ /^(if|else|end|range|with|define|template|block|\/\*)( |$)/) continue
        if (action ~ /^"/) continue
        # Quoted on the way out.
        if (action ~ /(^q |\| *q$|\| *shellQuote$|^shellQuote )/) continue
        # The variable the action reads first.
        if (!match(action, /\.[A-Za-z_][A-Za-z0-9_]*/)) continue
        name = substr(action, RSTART, RLENGTH)
        if (name ~ glyph || (name in allowed)) continue
        printf "%s: {{%s}}\n", file, action
        bad++
      }
    }
    END { exit bad > 0 }' || found=1
done

exit "$found"
