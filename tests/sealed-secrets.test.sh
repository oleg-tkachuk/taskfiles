#!/usr/bin/env bash
# sealed-secrets: literals reach kubectl as data, kubeseal seals for the pinned
# context, a failed seal leaves the existing manifest alone, and a Secret can
# be given a type and whole files as its values.
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

# The plaintext is a secret var: Task prints ***** for it when it echoes the
# task, and the real value still reaches kubectl.
readonly PLAIN=hunter2-not-in-any-log
shim kubeseal 'cat >/dev/null; printf "kind: SealedSecret\n"'
consumer ss sealed-secrets
reset_calls
run_task -v ss:seal SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_KEY=k "SECRET_VALUE=$PLAIN" SECRET_OUTPUT=out/creds.yaml
expect_status ok "seal: runs under --verbose"
refute_output "$PLAIN" "seal: --verbose does not print the plaintext"
expect_output "*****" "seal: --verbose prints the mask in its place"
expect_call "--from-literal=k=$PLAIN" "seal: the masked plaintext still reaches kubectl"

reset_calls
run_task -v ss:seal:literals SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_OUTPUT=out/creds.yaml "SECRET_LITERALS=a=$PLAIN b=2"
expect_status ok "literals: runs under --verbose"
refute_output "$PLAIN" "literals: --verbose does not print a plaintext"
expect_call "--from-literal=a=$PLAIN --from-literal=b=2" "literals: the masked pairs still reach kubectl"

reset_calls
run_task -v ss:seal:merge SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_KEY=k "SECRET_VALUE=$PLAIN" SECRET_OUTPUT=out/creds.yaml
expect_status ok "merge: runs under --verbose"
refute_output "$PLAIN" "merge: --verbose does not print the plaintext"
expect_call "--from-literal=k=$PLAIN" "merge: the masked plaintext still reaches kubectl"

# ─── SECRET_TYPE ─────────────────────────────────────────────────────────────
# A Secret some controller reads by its type: kubernetes.io/basic-auth.
readonly BASIC_AUTH=kubernetes.io/basic-auth

reset_calls
run_task ss:seal SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_KEY=k SECRET_VALUE=v SECRET_OUTPUT=out/creds.yaml
refute_call "--type" "type: none is passed unless asked for, so the Secret is Opaque"

reset_calls
run_task ss:seal SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_KEY=k SECRET_VALUE=v SECRET_OUTPUT=out/creds.yaml "SECRET_TYPE=$BASIC_AUTH"
expect_status ok "type: seal takes a SECRET_TYPE"
expect_call "create secret generic creds --namespace app --type=$BASIC_AUTH --from-literal=k=v" "type: seal builds the Secret with it"

reset_calls
run_task ss:seal:literals SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_OUTPUT=out/creds.yaml "SECRET_LITERALS=username=u password=p" "SECRET_TYPE=$BASIC_AUTH"
expect_call "--type=$BASIC_AUTH --from-literal=username=u --from-literal=password=p" "type: seal:literals builds the Secret with it"

printf 'A=1\n' > "$CONSUMER/app.env"
reset_calls
run_task ss:seal:file SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_OUTPUT=out/creds.yaml SECRET_FILE=app.env "SECRET_TYPE=$BASIC_AUTH"
expect_call "--type=$BASIC_AUTH --from-env-file=app.env" "type: seal:file builds the Secret with it"

pwned="$WORK/pwned-type"
reset_calls
run_task ss:seal SECRET_NAMESPACE=app SECRET_NAME=creds SECRET_KEY=k SECRET_VALUE=v SECRET_OUTPUT=out/creds.yaml "SECRET_TYPE=\$(touch\${IFS}$pwned)"
if [ -e "$pwned" ]; then fail "type: a \$( ) in SECRET_TYPE ran"; else pass "type: a \$( ) in SECRET_TYPE does not run"; fi

# ─── seal:files ──────────────────────────────────────────────────────────────
# A whole file as one key's value: line breaks and all, which an env file
# cannot hold.
mkdir -p "$CONSUMER/keys"
printf -- '-----BEGIN KEY-----\n%s\n-----END KEY-----\n' "$PLAIN" > "$CONSUMER/keys/tls.key"
printf 'chain\n' > "$CONSUMER/keys/ca.crt"

reset_calls
rm -f "$CONSUMER/out/tls.yaml"
run_task ss:seal:files SECRET_NAMESPACE=app SECRET_NAME=tls SECRET_OUTPUT=out/tls.yaml "SECRET_FILES=tls.key=keys/tls.key ca.crt=keys/ca.crt"
expect_status ok "files: seals"
expect_call "create secret generic tls --namespace app --from-file=tls.key=keys/tls.key --from-file=ca.crt=keys/ca.crt --dry-run=client" "files: each key=path is a --from-file of its own"
refute_call "$PLAIN" "files: no value is in an argument list"
if [ "$(cat "$CONSUMER/out/tls.yaml")" = "kind: SealedSecret" ]; then pass "files: the output holds the sealed manifest"; else fail "files: the output does not hold the sealed manifest"; fi
# The file the consumer gave is the only place the plaintext is.
copies=$(find "$WORK" -type f ! -path "$CONSUMER/keys/tls.key" -exec awk -v plain="$PLAIN" 'index($0, plain) { print FILENAME; exit }' {} \;)
if [ -z "$copies" ]; then pass "files: the plaintext is written nowhere"; else fail "files: the plaintext was written to $copies"; fi

reset_calls
run_task ss:seal:files SECRET_NAMESPACE=app SECRET_NAME=tls SECRET_OUTPUT=out/tls.yaml SECRET_FILES=tls.key=keys/tls.key "SECRET_TYPE=kubernetes.io/tls"
expect_call "--type=kubernetes.io/tls --from-file=tls.key=keys/tls.key" "files: takes a SECRET_TYPE"

reset_calls
run_task ss:seal:files SECRET_NAMESPACE=app SECRET_NAME=tls SECRET_OUTPUT=out/tls.yaml SECRET_FILES=keys/tls.key
expect_call "--from-file=keys/tls.key" "files: a path alone is passed as kubectl takes it, keyed by its file name"

printf 'committed\n' > "$CONSUMER/out/tls.yaml"
reset_calls
run_task ss:seal:files SECRET_NAMESPACE=app SECRET_NAME=tls SECRET_OUTPUT=out/tls.yaml "SECRET_FILES=tls.key=keys/tls.key ca.crt=keys/absent.crt"
expect_status fail "files: a file that is not there is refused"
expect_output "SECRET_FILES names a file that is not there" "files: says so"
refute_call "kubectl" "files: nothing is built from the files that are"
if [ "$(cat "$CONSUMER/out/tls.yaml")" = committed ]; then pass "files: a refusal leaves the existing manifest untouched"; else fail "files: a refusal rewrote the existing manifest"; fi

shim kubeseal 'cat >/dev/null; exit 1'
run_task ss:seal:files SECRET_NAMESPACE=app SECRET_NAME=tls SECRET_OUTPUT=out/tls.yaml SECRET_FILES=tls.key=keys/tls.key
expect_status fail "files: a failed kubeseal fails the task"
if [ "$(cat "$CONSUMER/out/tls.yaml")" = committed ]; then pass "files: a failed kubeseal leaves the existing manifest untouched"; else fail "files: a failed kubeseal rewrote the existing manifest"; fi
if ls "$CONSUMER"/out/tls.yaml.* >/dev/null 2>&1; then fail "files: a temporary file was left behind"; else pass "files: no temporary file is left behind"; fi
shim kubeseal 'cat >/dev/null; printf "kind: SealedSecret\n"'

shim kubectl 'exit 1'
run_task ss:seal:files SECRET_NAMESPACE=app SECRET_NAME=tls SECRET_OUTPUT=out/tls.yaml SECRET_FILES=tls.key=keys/tls.key
expect_status fail "files: a failed kubectl fails the task"
if [ "$(cat "$CONSUMER/out/tls.yaml")" = committed ]; then pass "files: a failed kubectl leaves the existing manifest untouched"; else fail "files: a failed kubectl rewrote the existing manifest"; fi
shim kubectl 'printf "kind: Secret\n"'

pwned="$WORK/pwned-files"
run_task ss:seal:files SECRET_NAMESPACE=app SECRET_NAME=tls SECRET_OUTPUT=out/tls.yaml "SECRET_FILES=k=\$(touch\${IFS}$pwned)"
if [ -e "$pwned" ]; then fail "files: a \$( ) in a path ran"; else pass "files: a \$( ) in a path does not run"; fi

finish
