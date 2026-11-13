#!/usr/bin/env bash
# Report every status marker that is not the library's own.
#
# A marker is a glyph, a word and the separator that follows them:
#
#   ◉ start · api · build
#   ✔ ok    · api · build
#   ○ skip  · api · build
#   ▲ warn  · api · build
#   ✖ fail  · api · build
#
# The glyph and the word carry the meaning twice over, so a line reads in a
# log stripped of colour and is found by a search for a plain word. The words
# are padded to one width: every line's first field starts in the same column.
#
# A module cannot import another's variables, so each defines its own, named
# _<PREFIX>_RUN, _OK, _SKIP, _WARN and _ERR. This holds the copies to one
# spelling, and refuses a glyph written anywhere else: a line with a marker
# typed into it has no word, and no way to follow a change made here.
#
# Usage: check-markers.sh <Taskfile>...   (exit 1 when anything is reported)
set -euo pipefail

found=0
for file in "$@"; do
  awk -v file="$file" '
    # canon <glyph> <word> <colour> — the definition of one marker: plain
    # under NO_COLOR, and otherwise the glyph and the word in the colour.
    function canon(glyph, word, colour,    pad) {
      pad = substr("     ", 1, WIDTH - length(word))
      return "\047{{if .NO_COLOR}}" glyph " " word pad " ·{{else}}{{\"\\x1b[" colour "m" glyph " " word "\\x1b[0m" pad " ·\"}}{{end}}\047"
    }
    function report(what) { printf "%s:%d: %s\n", file, NR, what; bad++ }
    BEGIN {
      # The width of the longest word.
      WIDTH = 5
      want["RUN"] = canon("◉", "start", 36)
      want["OK"] = canon("✔", "ok", 32)
      want["SKIP"] = canon("○", "skip", 90)
      want["WARN"] = canon("▲", "warn", 33)
      want["ERR"] = canon("✖", "fail", 31)
      split("◉ ✔ ○ ▲ ✖", glyphs, " ")
    }
    /^[ \t]*#/ { next }
    match($0, /^[ \t]+_[A-Z0-9]+_(RUN|OK|SKIP|WARN|ERR): /) {
      key = substr($0, RSTART, RLENGTH - 2)
      sub(/^[ \t]+/, "", key)
      suffix = key
      sub(/^.*_/, "", suffix)
      if (substr($0, RSTART + RLENGTH) != want[suffix]) report(key " is not the library marker: " want[suffix])
      next
    }
    {
      for (g in glyphs) if (index($0, glyphs[g])) { report("a " glyphs[g] " written into a line — use the marker variable, which carries its word"); break }
    }
    END { exit bad > 0 }' "$file" || found=1
done

exit "$found"
