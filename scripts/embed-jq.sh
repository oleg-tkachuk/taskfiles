#!/usr/bin/env bash
# Keep the jq programs a module carries equal to the .jq files they are
# written in.
#
# A consumer includes a module as a remote Taskfile, and only the YAML is
# fetched: a .jq file beside it is not there when the task runs. So a program
# is written in a file of its own, where it is read and tested as jq, and its
# text is carried by a module var, behind a marker naming the file:
#
#     # jq-file: images.jq
#     _K8S_IMAGES_JQ: |-
#       def header: ...
#
# The file is beside the Taskfile. The var is on the line after the marker, at
# the marker's indentation, and is a `|-` block; the block is the file, line
# for line. A task passes it on as `jq {{._K8S_IMAGES_JQ | q}}`.
#
# Refused as well:
#   - a file holding `{{`, which Task would read as a template;
#   - `jq -f`, `--from-file` or `-L` in a module, alone or among other short
#     flags (`-rf`), which read a file the consumer does not have.
#
# Usage: embed-jq.sh [--check] <Taskfile>...
#   --check   report every block that is not its file, and change nothing
#             (exit 1 when anything is reported)
#   default   rewrite each block from its file
set -euo pipefail

check=0
if [ "${1:-}" = --check ]; then check=1; shift; fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

found=0
for file in "$@"; do
  dir=${file%/*}
  [ "$dir" != "$file" ] || dir=.
  FILE="$file" DIR="$dir" OUT="$work/next" awk -v check="$check" '
    function report(line, what) { printf "%s:%d: %s\n", file, line, what; bad++ }
    function emit(text) { if (!check) print text > out }
    # Reads the file a marker names into want[1..wanted], indented as the
    # block is; a blank line stays blank, and the blank lines that end the
    # file are left out, as YAML leaves them out of the block.
    function load(path,    text, status, lines) {
      wanted = 0
      while ((status = (getline text < path)) > 0) {
        if (index(text, "{{")) report(marker, path " holds {{, which Task would read as a template")
        want[++lines] = (text == "") ? "" : deeper text
        if (text != "") wanted = lines
      }
      close(path)
      if (status < 0) report(marker, path " cannot be read")
      else if (wanted == 0) report(marker, path " is empty")
    }
    # Ends the block: says whether it was the file, and writes the file.
    function finish(    i, same) {
      same = (have == wanted)
      for (i = 1; same && i <= wanted; i++) same = (got[i] == want[i])
      if (check && !same) report(marker, name " is not " source " — run: task embed")
      for (i = 1; i <= wanted; i++) emit(want[i])
      for (i = 1; i <= blanks; i++) emit("")
      blanks = 0
      state = OUTSIDE
    }
    BEGIN {
      file = ENVIRON["FILE"]; out = ENVIRON["OUT"]
      OUTSIDE = 0; AT_VAR = 1; IN_BLOCK = 2
      state = OUTSIDE
      MARKER = "^[ \t]*# jq-file: "
      READS_A_FILE = "(^|[^A-Za-z0-9_])jq[ \t]([^|;&]*[ \t])?(-[A-Za-z]*[fL][A-Za-z]*|--from-file)([ \t=]|$)"
      if (!check) printf "" > out
    }
    state == IN_BLOCK {
      # A blank line belongs to the block only when a block line follows it.
      if ($0 == "") { blanks++; next }
      if (index($0, deeper) == 1) {
        for (; blanks > 0; blanks--) got[++have] = ""
        got[++have] = $0
        next
      }
      finish()
    }
    state == AT_VAR {
      if ($0 ~ ("^" indent "[A-Z0-9_]+: [|]-$")) {
        name = $0
        sub(/^[ \t]+/, "", name)
        sub(/: [|]-$/, "", name)
        state = IN_BLOCK
        have = 0
        emit($0)
        next
      }
      report(marker, "the line after a jq-file marker is not a `NAME: |-` var at its indentation")
      state = OUTSIDE
    }
    $0 ~ MARKER {
      marker = NR
      indent = $0
      sub(/#.*$/, "", indent)
      deeper = indent "  "
      source = $0
      sub(MARKER, "", source)
      if (source !~ /^[A-Za-z0-9_.-]+[.]jq$/) {
        report(marker, "a jq-file marker names one .jq file beside the Taskfile, and nothing else")
      } else {
        source = ENVIRON["DIR"] "/" source
        load(source)
        state = AT_VAR
      }
      emit($0)
      next
    }
    {
      if ($0 !~ /^[ \t]*#/ && $0 ~ READS_A_FILE) report(NR, "jq reads its program from a file, which a consumer does not have — embed it: # jq-file: <name>.jq")
      emit($0)
    }
    END {
      if (state == IN_BLOCK) finish()
      else if (state == AT_VAR) report(marker, "a jq-file marker is the last line")
      exit bad > 0
    }' "$file" || { found=1; continue; }
  # The same bytes when nothing moved, so a file is not touched for nothing.
  if [ "$check" = 0 ] && [ "$(cat "$work/next")" != "$(cat "$file")" ]; then
    cat "$work/next" > "$file"
    printf '%s\n' "$file: rewritten"
  fi
done

exit "$found"
