#!/usr/bin/env bash
# Report every task that prints a start marker and no ok marker.
#
#   ◉ start · api · build
#   ✔ ok    · api · build
#
# A start line says work began; the ok line is what says it ended well. A task
# with the first and not the second ends in silence on success, and a log of it
# reads the same as one cut short.
#
# Two kinds of task have no ok to print, and are let through:
#
#   interactive: true          it runs until it is interrupted
#   # start-only: <reason>     a comment inside the task, saying why
#
# What is read is the task's own text. A start printed by a snippet a task
# interpolates from `vars:` is not seen here, and neither is a path through a
# task that leaves before its ok line: the tests of a module hold those.
#
# Usage: check-closed.sh <Taskfile>...   (exit 1 when anything is reported)
set -euo pipefail

found=0
for file in "$@"; do
  awk -v file="$file" '
    BEGIN {
      START = "\\{\\{\\._[A-Z0-9]+_RUN\\}\\}"
      OK = "\\{\\{\\._[A-Z0-9]+_OK\\}\\}"
      INTERACTIVE = "^[ \t]+interactive:[ \t]*true[ \t]*$"
      WAIVER = "^[ \t]*# start-only:"
      SECTION = "^tasks:[ \t]*$"
      # A task is a key one level into the section.
      TASK = "^  [^ \t#][^ \t]*:[ \t]*$"
    }
    function report(what) { printf "%s:%d: %s\n", file, started, what; bad++ }
    # close_task — judges the task just read, and forgets it.
    function close_task() {
      if (started && !closed && !interactive && !waived)
        report("task " name " prints a start marker and no ok — end it with the _OK marker, or say why not in a \"# start-only:\" comment")
      name = ""; started = 0; closed = 0; interactive = 0; waived = 0
    }
    $0 ~ SECTION { in_tasks = 1; next }
    in_tasks && /^[^ \t#]/ { close_task(); in_tasks = 0 }
    !in_tasks { next }
    $0 ~ TASK {
      close_task()
      name = $1
      sub(/:$/, "", name)
      next
    }
    name == "" { next }
    $0 ~ WAIVER {
      reason = $0
      sub(WAIVER, "", reason)
      if (reason ~ /[^ \t]/) waived = 1
      next
    }
    /^[ \t]*#/ { next }
    $0 ~ INTERACTIVE { interactive = 1 }
    $0 ~ START && !started { started = NR }
    $0 ~ OK { closed = 1 }
    END { close_task(); exit bad > 0 }' "$file" || found=1
done

exit "$found"
