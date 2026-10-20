#!/usr/bin/env bash
# hcloud: a command input runs as a command whatever quotes it holds, values
# reach hcloud as data, and a prompt names the selector it acts on honestly.
source "$(dirname "$0")/lib.sh"

# FAKE_NO_MATCH makes the selector match nothing; FAKE_REFUSE names a server
# whose power action fails.
shim hcloud '
case "$*" in
  "server list -l "*" -o noheader -o columns=name")
    echo "token=${HCLOUD_TOKEN:-} selector=$4" >> "$CALLS"
    [ -n "${FAKE_NO_MATCH:-}" ] || printf "web-1\nweb-2\n" ;;
  "server list -l "*" -o columns="*) ;;
  "server "*" ${FAKE_REFUSE:-none}") exit 1 ;;
  "server "*) ;;
  *) exit 1 ;;
esac'

consumer hcloud hcloud
unset HCLOUD_TOKEN
printf 'x"secret"\n' > "$CONSUMER/token.txt"
printf 'x"role=web"\n' > "$CONSUMER/selector.txt"

# An odd number of double quotes in a command broke the script it sat in.
run_task hcloud:poweron HCLOUD_SELECTOR=role=web "HCLOUD_TOKEN_CMD=awk -F'\"' '{print \$2}' token.txt"
expect_status ok "token cmd: a command with an odd number of quotes runs"
expect_call "token=secret" "token cmd: its output becomes HCLOUD_TOKEN"

# The rest read the token from the environment, as the CLI itself does.
export HCLOUD_TOKEN=t
reset_calls
run_task hcloud:poweron "HCLOUD_SELECTOR_CMD=awk -F'\"' '{print \$2}' selector.txt"
expect_status ok "selector cmd: a command with an odd number of quotes runs"
expect_call "selector=role=web" "selector cmd: its output becomes the selector"

pwned="$WORK/pwned"
reset_calls
run_task hcloud:poweron "HCLOUD_SELECTOR=role=\$(touch $pwned)" "PROJECT_NAME=\$(touch $pwned)"
if [ -e "$pwned" ]; then fail "values: a \$( ) in the selector or project name ran"; else pass "values: a \$( ) in the selector or project name does not run"; fi
expect_call "selector=role=\$(touch $pwned)" "values: the selector reaches hcloud as data"

reset_calls
run_task hcloud:protect HCLOUD_SELECTOR=role=web
expect_status ok "protect: protects every matched server"
expect_call "hcloud server enable-protection web-1 delete rebuild" "protect: each protection level is its own argument"

run_task hcloud:shutdown "HCLOUD_SELECTOR_CMD=cat sel.txt"
expect_output "every server matching the selector that \`cat sel.txt\` prints" "prompt: a looked-up selector is named as the command that prints it"

run_task hcloud:unprotect HCLOUD_SELECTOR=role=web HCLOUD_PROTECTION=delete
expect_output "Lift delete protection on every server matching role=web" "prompt: unprotect names the protection it lifts"

reset_calls
run_task hcloud:ssh HCLOUD_SELECTOR=role=web HCLOUD_SERVER=web-2
expect_status ok "ssh: reaches a matched server"
expect_call "hcloud server ssh -u root -p 22 web-2" "ssh: passes the user, port and server"

run_task hcloud:ssh HCLOUD_SELECTOR=role=web HCLOUD_SERVER=db-1
expect_status fail "ssh: refuses a server the selector does not match"

reset_calls
run_task hcloud:servers HCLOUD_SELECTOR=role=web HCLOUD_STATUS=off
expect_call "hcloud server list -l role=web -o columns=name,status,type,location,ipv4,private_net --status off" "servers: narrows by status"

# ─── the fan-out: every server is tried, and the ones that refused are named ─
reset_calls
FAKE_REFUSE=web-1 run_task hcloud:poweron HCLOUD_SELECTOR=role=web
expect_status fail "each: a server that refuses fails the task"
expect_call "hcloud server poweron web-2" "each: the servers after a refusal are still tried"
expect_output "poweron did not take on: web-1" "each: names the server that refused"
refute_output "powered on" "each: a partial failure is not reported as done"

reset_calls
run_task hcloud:poweron
expect_status fail "selector: an empty one is refused"
expect_output "an empty one matches every server in the project" "selector: says why an empty one is refused"
refute_call "hcloud server poweron" "selector: nothing is powered on without one"

reset_calls
FAKE_NO_MATCH=1 run_task hcloud:poweron HCLOUD_SELECTOR=role=none
expect_status fail "selector: one that matches nothing fails"
expect_output "no server matches role=none" "selector: says it matched nothing"
refute_call "hcloud server poweron" "selector: nothing is powered on when nothing matches"

finish
