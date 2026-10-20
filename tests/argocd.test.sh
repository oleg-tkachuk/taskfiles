#!/usr/bin/env bash
# argocd: the prefix, namespace, context and password reach kubectl and argocd
# as data, and the prefix is matched literally rather than as a pattern.
source "$(dirname "$0")/lib.sh"

shim kubectl '
case "$*" in
  *" version "*) exit 0 ;;
  *"-o jsonpath="*) printf "svc-api\nsvc-web\nsvcXother\ninfra-db\n" ;;
  *"-o custom-columns="*)
    printf "NAME SYNC HEALTH\nsvc-api Synced Healthy\nsvcXother Synced Healthy\ninfra-db Synced Healthy\n" ;;
esac'
shim argocd 'echo "\$2a\$10\$hash"'

pwned="$WORK/pwned"
inject="\$(touch $pwned)"

consumer argocd argocd
run_task argocd:refresh APP_PREFIX=svc-
expect_status ok "refresh: hard-refreshes"
expect_call "kubectl -n argocd patch application.argoproj.io svc-api --type merge" "refresh: patches a matching application"
expect_call "kubectl -n argocd patch application.argoproj.io svc-web --type merge" "refresh: patches every matching application"
refute_call "patch application.argoproj.io infra-db" "refresh: leaves an application outside the prefix alone"
expect_output "✔ argocd · hard-refreshed svc-api" "refresh: reports each application"
expect_call "kubectl version --request-timeout=3s" "refresh: probes the cluster with a bounded wait"

reset_calls
run_task argocd:refresh APP_PREFIX=svc.
expect_status ok "refresh: a prefix with a regex metacharacter runs"
refute_call "patch application.argoproj.io svcXother" "refresh: the prefix is literal, not a pattern"
expect_output "no application matches svc.* in argocd" "refresh: says when nothing matches"

rm -f "$pwned"
reset_calls
run_task argocd:refresh "APP_PREFIX=$inject"
if [ -e "$pwned" ]; then fail "refresh: a \$( ) in APP_PREFIX ran"; else pass "refresh: a \$( ) in APP_PREFIX does not run"; fi
expect_output "no application matches $inject* in argocd" "refresh: APP_PREFIX is reported as data"

reset_calls
run_task argocd:list APP_PREFIX=svc.
expect_output "NAME SYNC HEALTH" "list: keeps the header"
refute_output "svcXother" "list: the prefix is literal, not a pattern"

rm -f "$pwned"
run_task argocd:list "APP_PREFIX=$inject"
if [ -e "$pwned" ]; then fail "list: a \$( ) in APP_PREFIX ran"; else pass "list: a \$( ) in APP_PREFIX does not run"; fi

rm -f "$pwned"
reset_calls
run_task argocd:server:status "ARGOCD_NS=$inject"
if [ -e "$pwned" ]; then fail "namespace: a \$( ) in ARGOCD_NS ran"; else pass "namespace: a \$( ) in ARGOCD_NS does not run"; fi
expect_call "kubectl -n $inject get pods" "namespace: ARGOCD_NS reaches kubectl as data"

rm -f "$pwned"
reset_calls
run_task argocd:server:set-password "ARGOCD_ADMIN_PASSWORD=pw$inject"
expect_status ok "set-password: sets the password"
if [ -e "$pwned" ]; then fail "set-password: a \$( ) in the password ran"; else pass "set-password: a \$( ) in the password does not run"; fi
expect_call "argocd account bcrypt --password pw$inject" "set-password: the password reaches argocd as data"
expect_call "kubectl -n argocd patch secret argocd-secret" "set-password: writes the hash"
expect_call "kubectl -n argocd rollout restart deploy/argocd-server" "set-password: rolls the server"

consumer argocd argocd "{ K8S_CONTEXT: '$inject' }"
rm -f "$pwned"
reset_calls
run_task argocd:server:status
if [ -e "$pwned" ]; then fail "context: a \$( ) in K8S_CONTEXT ran"; else pass "context: a \$( ) in K8S_CONTEXT does not run"; fi
expect_call "kubectl --context $inject -n argocd get pods" "context: K8S_CONTEXT reaches kubectl as data"

consumer argocd argocd "{ K8S_CONTEXT: prod }"
reset_calls
run_task argocd:server:logs ARGOCD_SERVER_LABEL=argo-server LOG_TAIL=5
expect_call "kubectl --context prod -n argocd logs -l app.kubernetes.io/name=argo-server -f --tail=5" "logs: passes the context, label and tail"

finish
