#!/usr/bin/env bash
# k8s: names and the context reach kubectl and helm as data, never as shell.
source "$(dirname "$0")/lib.sh"

# The deployment exists unless FAKE_NO_DEPLOY is set; its selector is app=web.
# FAKE_UNREACHABLE takes the API server away; FAKE_FORBIDDEN answers a lookup
# with an error other than "not found", as RBAC or an expired login does.
shim kubectl '
case "$*" in
  *" version "*) [ -z "${FAKE_UNREACHABLE:-}" ] ;;
  *"-o go-template="*) [ -n "${FAKE_NO_LABELS:-}" ] || printf "app=web," ;;
  *" get deploy/"*"--ignore-not-found"*)
    if [ -n "${FAKE_FORBIDDEN:-}" ]; then echo "Error from server (Forbidden)" >&2; exit 1; fi
    [ -n "${FAKE_NO_DEPLOY:-}" ] || echo deployment.apps/web ;;
  *" get deploy/"*) [ -z "${FAKE_NO_DEPLOY:-}" ] ;;
  *) exit 0 ;;
esac'
shim helm 'exit 0'

# A value that runs a command if any shell ever parses it.
INJECT="\$(touch $WORK/pwned)"

expect_not_pwned() {
  if [ -e "$WORK/pwned" ]; then fail "$1: a command substitution ran"; rm -f "$WORK/pwned"; else pass "$1"; fi
}

# ─── happy paths ─────────────────────────────────────────────────────────────
consumer k8s k8s '{ PROJECT_NAME: web, K8S_NAMESPACE: apps, K8S_CONTEXT: dev }'

run_task k8s:restart
expect_status ok "restart: rolls an existing deployment"
expect_call "kubectl --context dev -n apps rollout restart deploy/web" "restart: rolls deploy/web in apps on dev"
expect_call "kubectl --context dev -n apps rollout status deploy/web --timeout=2m" "restart: waits with the default timeout"
expect_output "rolled web" "restart: reports the roll"

reset_calls
export FAKE_NO_DEPLOY=1
run_task k8s:restart
expect_status ok "restart: an absent deployment is skipped, not failed"
refute_call "rollout restart" "restart: nothing is rolled when the deployment is absent"
expect_output "deploy/web not found in apps" "restart: says why it skipped"
unset FAKE_NO_DEPLOY

# No cluster at all is a skip too — this task sits in chains that stay green
# on a laptop with nothing running — but it says that, not "not found".
reset_calls
export FAKE_UNREACHABLE=1
run_task k8s:restart
expect_status ok "restart: an unreachable cluster is skipped, not failed"
refute_call "rollout restart" "restart: nothing is rolled when the cluster is unreachable"
expect_output "cluster unreachable" "restart: says the cluster was unreachable"
refute_output "not found" "restart: an unreachable cluster is not reported as an absent deployment"
unset FAKE_UNREACHABLE

# A cluster that answers with anything but "not found" is a failure: the old
# pods would keep running behind a green step.
reset_calls
export FAKE_FORBIDDEN=1
run_task k8s:restart
expect_status fail "restart: a lookup the cluster refused fails"
refute_call "rollout restart" "restart: nothing is rolled when the lookup failed"
expect_output "could not look up deploy/web in apps" "restart: says the lookup failed"
unset FAKE_FORBIDDEN

reset_calls
run_task k8s:status
expect_status ok "status: shows the deployment and its pods"
expect_call "kubectl --context dev -n apps get deploy/web -o wide" "status: gets the deployment"
expect_call "kubectl --context dev -n apps get pods -l app=web -o wide" "status: lists pods by the deployment's own selector"

reset_calls
run_task k8s:upgrade VALUES=values.yaml
expect_status ok "upgrade: installs the chart"
expect_call "helm upgrade --install web ./deploy/chart --namespace apps --create-namespace --kube-context dev --values values.yaml" "upgrade: passes release, chart, namespace, context and values"

# ─── injection ───────────────────────────────────────────────────────────────
consumer k8s k8s "{ PROJECT_NAME: 'web$INJECT', K8S_NAMESPACE: 'ns$INJECT', K8S_CONTEXT: 'ctx$INJECT' }"

reset_calls
run_task k8s:restart
expect_status ok "restart: hostile names still run"
expect_not_pwned "restart: names and context are not run as shell"
expect_call "kubectl --context ctx$INJECT -n ns$INJECT rollout restart deploy/web$INJECT" "restart: hostile values reach kubectl verbatim"

reset_calls
run_task k8s:status
expect_not_pwned "status: names and context are not run as shell"
expect_call "kubectl --context ctx$INJECT -n ns$INJECT get deploy/web$INJECT -o wide" "status: hostile values reach kubectl verbatim"

reset_calls
run_task k8s:upgrade
expect_not_pwned "upgrade: names and context are not run as shell"
expect_call "helm upgrade --install web$INJECT ./deploy/chart --namespace ns$INJECT --create-namespace --kube-context ctx$INJECT" "upgrade: hostile values reach helm verbatim"

reset_calls
run_task k8s:doctor
expect_not_pwned "doctor: names and context are not run as shell"

consumer k8s k8s "{ PROJECT_NAME: web, K8S_DEPLOYMENT_NAME: 'dep$INJECT' }"
reset_calls
run_task k8s:restart
expect_not_pwned "restart: a hostile deployment name is not run as shell"
expect_call "rollout restart deploy/dep$INJECT" "restart: a hostile deployment name reaches kubectl verbatim"

# ─── status: a selector with no matchLabels lists no one else's pods ────────
reset_calls
run_task k8s:status
expect_call "get pods -l app=web -o wide" "status: lists the pods the deployment selects"
reset_calls
FAKE_NO_LABELS=1 run_task k8s:status
expect_status ok "status: a matchExpressions-only selector still reports"
refute_call "get pods" "status: no pod list from an empty selector"
expect_output "selects by matchExpressions only" "status: says why the pods are not listed"

# ─── logs: LOG_TAIL, and the old TAIL refused ───────────────────────────────
consumer k8s k8s '{ PROJECT_NAME: web, K8S_NAMESPACE: apps, K8S_CONTEXT: dev }'
reset_calls
run_task k8s:logs LOG_TAIL=500
expect_status ok "logs: runs with LOG_TAIL"
expect_call "logs deploy/web -f --tail=500" "logs: LOG_TAIL sets the backlog"
reset_calls
run_task k8s:logs TAIL=500
expect_status fail "logs: the old TAIL is refused"
expect_output "TAIL is now LOG_TAIL" "logs: the refusal names the new input"
refute_call "logs deploy/" "logs: nothing runs on the old TAIL"

finish
