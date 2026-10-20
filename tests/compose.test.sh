#!/usr/bin/env bash
# compose: COMPOSE_ENGINE splits into a command, COMPOSE_FILE stays one
# argument, a missing file is refused before the engine runs, and down keeps
# volumes while reset drops them.
source "$(dirname "$0")/lib.sh"

# argv one bracket per argument, so one argument and two read differently.
argv='printf "[%s]" "$@" >> "$CALLS"; printf "\n" >> "$CALLS"'
shim docker "$argv"
shim podman "$argv"

consumer cmp compose
touch "$CONSUMER/docker-compose.yaml"
run_task cmp:down
expect_status ok "down: runs with the default file"
expect_call "[compose][-f][docker-compose.yaml][down]" "down: docker compose on the default file, volumes kept"

reset_calls
run_task cmp:reset
expect_call "[compose][-f][docker-compose.yaml][down][-v]" "reset: drops the volumes"

touch "$CONSUMER/my stack.yaml"
consumer cmp compose "{ COMPOSE_ENGINE: 'podman compose', COMPOSE_FILE: 'my stack.yaml' }"
reset_calls
run_task cmp:logs SERVICE=web LOG_TAIL=50
expect_status ok "logs: runs with another engine and file"
expect_call "[compose][-f][my stack.yaml][logs][-f][--tail=50][web]" "logs: the engine splits, the file and service stay whole"
refute_call "docker " "logs: the default engine is not used"

reset_calls
run_task cmp:logs TAIL=50
expect_status fail "logs: the old TAIL is refused"
expect_output "TAIL is now LOG_TAIL" "logs: the refusal names the new input"
refute_call "[logs]" "logs: nothing runs on the old TAIL"

consumer cmp compose "{ COMPOSE_FILE: missing.yaml }"
reset_calls
run_task cmp:up
expect_status fail "up: a missing compose file is refused"
expect_output "missing.yaml not found" "up: the refusal names the file"
refute_call "[compose]" "up: the engine does not run without its file"

finish
