#!/usr/bin/env bash
# github: force-push lifts protection only on the repository it pushes to, and
# a protection it could not restore fails the task.
source "$(dirname "$0")/lib.sh"

shim gh '
case "$*" in
  "api repos/"*"/enforce_admins --jq .enabled") echo true ;;
  "api -X DELETE "*) ;;
  "api -X POST "*) [ -z "${FAKE_RESTORE_FAIL:-}" ] ;;
  *) exit 1 ;;
esac'
shim git '
case "$*" in
  "remote get-url "*) echo "${FAKE_REMOTE_URL:-git@github.com:acme/app.git}" ;;
  push*) [ -z "${FAKE_PUSH_FAIL:-}" ] ;;
  *) exit 1 ;;
esac'

consumer github github '{ GH_REPO: acme/app }'

run_task github:force-push REASON=test
expect_status ok "force-push: pushes when the remote is the protected repository"
expect_call "git push --force-with-lease origin HEAD:main" "force-push: pushes to origin by default"
expect_call "gh api -X POST repos/acme/app/branches/main/protection/enforce_admins" "force-push: restores protection"

for url in https://github.com/acme/app https://github.com/Acme/App.git git@github.com:acme/app; do
  export FAKE_REMOTE_URL=$url
  run_task github:force-push REASON=test
  expect_status ok "force-push: $url is the protected repository"
done

for url in git@github.com:acme/other.git https://github.com/fork/app.git https://github.com/acme/app-old; do
  export FAKE_REMOTE_URL=$url
  reset_calls
  run_task github:force-push REASON=test
  expect_status fail "force-push: refuses a remote at $url"
  refute_call "gh api -X DELETE" "force-push: lifts nothing when the remote is $url"
done
unset FAKE_REMOTE_URL

reset_calls
consumer github github '{ GH_REPO: acme/app, GH_REMOTE: upstream }'
run_task github:force-push REASON=test
expect_status ok "force-push: GH_REMOTE names the remote"
expect_call "git remote get-url upstream" "force-push: checks the remote it pushes to"
expect_call "git push --force-with-lease upstream HEAD:main" "force-push: pushes to GH_REMOTE"

export FAKE_RESTORE_FAIL=1
run_task github:force-push REASON=test
expect_status fail "force-push: a protection it could not restore fails the task"
expect_output "COULD NOT RESTORE" "force-push: says protection is still off"
unset FAKE_RESTORE_FAIL

export FAKE_PUSH_FAIL=1
reset_calls
run_task github:force-push REASON=test
expect_status fail "force-push: a failed push fails the task"
expect_call "gh api -X POST" "force-push: a failed push still restores protection"
unset FAKE_PUSH_FAIL

finish
