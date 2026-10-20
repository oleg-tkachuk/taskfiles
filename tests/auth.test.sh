#!/usr/bin/env bash
# auth: the JWT_* inputs reach step as one argument each, STEP_FLAGS splits
# into flags, the key never appears in argv, and a TTL that is not a number is
# refused before it reaches $(( )).
source "$(dirname "$0")/lib.sh"

# step logs its argv one bracket per argument, the claims it read on stdin,
# and the key it was handed through the --key file.
shim step '
printf "[%s]" "$@" >> "$CALLS"; printf "\n" >> "$CALLS"
while [ $# -gt 0 ]; do
  case "$1" in --key) printf "key=%s\n" "$(cat "$2")" >> "$CALLS"; shift ;; esac
  shift
done
printf "claims=%s\n" "$(cat)" >> "$CALLS"'

consumer auth auth
run_task auth:mint-token "JWT_SUB=dev user" JWT_ALG=HS512 "JWT_CLAIMS={\"role\":\"admin\"}" JWT_SECRET=s3cret "STEP_FLAGS=--no-password --insecure"
expect_status ok "mint-token: runs"
expect_call "[crypto][jwt][sign][--no-password][--insecure][--alg][HS512]" "mint-token: STEP_FLAGS split into flags ahead of the alg"
expect_call "[--sub][dev user]" "mint-token: JWT_SUB reaches step as one argument"
expect_call 'claims={"role":"admin"}' "mint-token: JWT_CLAIMS arrive on stdin"
expect_call "key=s3cret" "mint-token: the key arrives through the --key file"
refute_call "[s3cret]" "mint-token: the key is never an argument"

pwned="$WORK/pwned"
reset_calls
run_task auth:mint-token "JWT_TTL_SECONDS=0 + \$(touch $pwned)"
expect_status fail "mint-token: a TTL that is not a number is refused"
expect_output "JWT_TTL_SECONDS must be a whole number" "mint-token: the refusal names JWT_TTL_SECONDS"
if [ -e "$pwned" ]; then fail "mint-token: a \$( ) in the TTL ran"; else pass "mint-token: a \$( ) in the TTL does not run"; fi
refute_call "[crypto]" "mint-token: step is not called on a refused TTL"

finish
