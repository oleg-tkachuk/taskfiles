#!/usr/bin/env bash
# sealed-secrets: literals reach kubectl as data, kubeseal seals for the pinned
# context, and a failed seal leaves the existing manifest alone.
source "$(dirname "$0")/lib.sh"

shim kubectl 'printf "kind: Secret\n"'
shim kubeseal '
case "$*" in *--fetch-cert*) echo CERT; exit 0 ;; esac
cat >/dev/null
[ -z "${FAKE_SEAL_FAIL:-}" ] || exit 1
echo "kind: SealedSecret"'

consumer ss sealed-secrets '{ K8S_CONTEXT: prod }'

pwned="$WORK/pwned"
run_task ss:seal:literals SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_OUTPUT=out/creds.yaml \
  "SECRET_LITERALS=a=\$(touch\${IFS}$pwned) b=* c=plain"
expect_status ok "literals: seals"
if [ -e "$pwned" ]; then fail "literals: a \$( ) in a value ran"; else pass "literals: a \$( ) in a value does not run"; fi
expect_call "--from-literal=a=\$(touch\${IFS}$pwned)" "literals: a \$( ) reaches kubectl as data"
expect_call "--from-literal=b=* " "literals: a glob reaches kubectl unexpanded"
expect_call "--from-literal=c=plain" "literals: every pair is passed"
expect_call "kubeseal --context prod" "seal: kubeseal seals for the pinned context"
expect_call "kubectl --context prod create secret" "seal: kubectl builds for the pinned context"

printf 'committed\n' > "$CONSUMER/out/creds.yaml"
export FAKE_SEAL_FAIL=1
run_task ss:seal SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_KEY=k SECRET_VALUE=v SECRET_OUTPUT=out/creds.yaml
expect_status fail "seal: a failed kubeseal fails the task"
if [ "$(cat "$CONSUMER/out/creds.yaml")" = committed ]; then
  pass "seal: a failed kubeseal leaves the existing manifest untouched"
else
  fail "seal: a failed kubeseal rewrote the existing manifest"
fi
if ls "$CONSUMER"/out/creds.yaml.* >/dev/null 2>&1; then fail "seal: a temporary file was left behind"; else pass "seal: no temporary file is left behind"; fi
unset FAKE_SEAL_FAIL

run_task ss:seal SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_KEY=k SECRET_VALUE=v SECRET_OUTPUT=out/creds.yaml
expect_status ok "seal: seals"
if [ "$(cat "$CONSUMER/out/creds.yaml")" = "kind: SealedSecret" ]; then
  pass "seal: the output holds the sealed manifest"
else
  fail "seal: the output does not hold the sealed manifest"
fi

reset_calls
run_task ss:pubkey
expect_call "kubeseal --context prod --controller-namespace sealed-secrets --controller-name sealed-secrets-controller --fetch-cert" \
  "pubkey: fetches the certificate from the pinned context"

consumer ss sealed-secrets
reset_calls
run_task ss:seal SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_KEY=k SECRET_VALUE=v SECRET_OUTPUT=out/creds.yaml
refute_call "--context" "unpinned: no context flag is passed"

# The lowercase inputs are gone: a call still using them names what is missing.
reset_calls
run_task ss:seal namespace=app name=creds key=k value=v output=out/creds.yaml
expect_status fail "renamed: the old lowercase inputs are refused"
expect_output "SECRET_NAMESPACE" "renamed: the refusal names the new inputs"
refute_call "kubeseal" "renamed: nothing is sealed on the old inputs"

finish
