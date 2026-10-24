#!/usr/bin/env bash
# Report every template action that reaches a shell unquoted.
#
# A value interpolated into a shell script is code unless it goes through
# `q` (shellQuote): inside double quotes a $(...) in it runs, and bare it is
# word-split and parsed. The library's own glyph constants and the inputs a
# module declares as shell on purpose are exempt; everything else that is not
# a template control action must be quoted — by `q` outside any quotes,
# since the quotes `q` adds mean nothing inside someone else's.
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

# Ends each shell text: ASCII record separator, which no Taskfile contains.
readonly SEP=$'\036'
export SEP

# Every string a module hands to a shell: commands, deferred commands,
# preconditions, status checks, and dynamic (sh:) variables, at task and
# module level.
readonly shell_texts='
  ([.vars // {} | .[] | select(type == "!!map") | .sh // ""] +
   [.tasks // {} | .[] | (
      (.cmds // [])[] | select(type == "!!str"),
      (.cmds // [])[] | select(type == "!!map") | (.cmd // ""),
      (.cmds // [])[] | select(type == "!!map") | (.defer // "") | select(type == "!!str"),
      (.preconditions // [])[] | select(type == "!!str"),
      (.preconditions // [])[] | select(type == "!!map") | (.sh // ""),
      (.status // [])[],
      (.vars // {} | .[] | select(type == "!!map") | .sh // "")
   )]) | .[] | select(. != "")'

found=0
for file in "$@"; do
  verbatim=$(awk -F': ' '/^# shell-verbatim: /{print $2}' "$file" | tr '\n' ' ')
  # The bodies of declared variables the module defines as plain strings.
  # One record per shell text, so a quote opened on one line of a script is
  # still open on the next.
  { yq -r "$shell_texts | . + strenv(SEP)" "$file"
    VERBATIM="$verbatim" yq -r '.vars // {} | to_entries[] | select(.value | type == "!!str") | select(.key as $k | strenv(VERBATIM) | split(" ") | any_c(. == $k)) | .value + strenv(SEP)' "$file"
  } | awk -v RS="$SEP" -v file="$file" -v glyph="$glyph" -v verbatim="$verbatim" '
    BEGIN { n = split(verbatim, v, " "); for (i = 1; i <= n; i++) allowed["." v[i]] = 1 }
    # The shell quote context the next action lands in: a stack of s (single
    # quotes), d (double quotes) and c (a $( ) or ( ), which starts unquoted
    # again). Literal text only: an action itself is never scanned for quotes.
    # A comment runs to the end of its line, so an apostrophe in it opens
    # nothing. Its actions are still checked: a newline in a value ends the
    # comment, and what follows it runs.
    function scan(text,    i, ch, top) {
      for (i = 1; i <= length(text); i++) {
        ch = substr(text, i, 1)
        if (comment) { if (ch == "\n") comment = 0; last = ch; continue }
        top = depth ? stack[depth] : ""
        if (top == "s") { if (ch == "\047") depth--; last = ch; continue }
        if (ch == "\\") { i++; last = "x"; continue }
        if (top == "d") {
          if (ch == "\"") depth--
          else if (ch == "$" && substr(text, i + 1, 1) == "(") { stack[++depth] = "c"; i++ }
          last = ch
          continue
        }
        if (ch == "\047") stack[++depth] = "s"
        else if (ch == "\"") stack[++depth] = "d"
        else if (ch == "(") stack[++depth] = "c"
        else if (ch == ")" && depth) depth--
        else if (ch == "#" && last ~ /^$|[ \t\n;]/) comment = 1
        last = ch
      }
    }
    function report(action) { printf "%s: {{%s}}\n", file, action; bad++ }
    {
      line = $0; depth = 0; comment = 0; last = ""
      while (match(line, /\{\{[^}]*\}\}/)) {
        action = substr(line, RSTART + 2, RLENGTH - 4)
        scan(substr(line, 1, RSTART - 1))
        line = substr(line, RSTART + RLENGTH)
        last = "x"
        gsub(/^-? +| +-?$/, "", action)
        # Control actions, comments and literals are not values.
        if (action ~ /^(if|else|end|range|with|define|template|block|\/\*)( |$)/) continue
        if (action ~ /^"/) continue
        # Quoted on the way out — but only outside quotes. q emits its own
        # single quotes: inside double quotes they are literal and a $(…) in
        # the value still runs, and inside single quotes they close the quote
        # around the value instead.
        if (action ~ /(^q |\| *q$|\| *shellQuote$|^shellQuote )/) {
          if (depth && stack[depth] != "c") report(action " inside quotes")
          continue
        }
        # Binding a variable (`$x := ...`) prints nothing; its uses are checked.
        if (action ~ /^\$[A-Za-z_][A-Za-z0-9_]* *:?= /) continue
        # A template variable — a range element, a $x bound earlier — or the
        # dot itself is data from a list, and nothing exempts it.
        if (action ~ /^(\$[A-Za-z_][A-Za-z0-9_]*|\.)( |$)/) { report(action); continue }
        # Every value the action reads, not only the first: one exempt name
        # does not excuse the next. String literals are not names.
        rest = action
        gsub(/"([^"\\]|\\.)*"/, "", rest)
        while (match(rest, /(^|[^A-Za-z0-9_.])[.$][A-Za-z_][A-Za-z0-9_]*/)) {
          name = substr(rest, RSTART, RLENGTH)
          rest = substr(rest, RSTART + RLENGTH)
          sub(/^[^.$]/, "", name)
          if (name ~ /^\$/ || !(name ~ glyph || (name in allowed))) { report(action); break }
        }
      }
    }
    END { exit bad > 0 }' || found=1
done

exit "$found"
