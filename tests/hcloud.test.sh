#!/usr/bin/env bash
# hcloud: a command input runs as a command whatever quotes it holds, values
# reach hcloud as data, and a prompt names the selector it acts on honestly.
source "$(dirname "$0")/lib.sh"

shim hcloud '
case "$*" in
  "server list -l "*" -o noheader -o columns=name")
    echo "token=${HCLOUD_TOKEN:-} selector=$4" >> "$CALLS"
    printf "web-1\nweb-2\n" ;;
  "server list -l "*" -o columns="*) ;;
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

finish
