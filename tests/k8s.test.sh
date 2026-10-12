#!/usr/bin/env bash
# k8s: names and the context reach kubectl and helm as data, never as shell.
source "$(dirname "$0")/lib.sh"

# The deployment exists unless FAKE_NO_DEPLOY is set; its selector is app=web.
shim kubectl '
case "$*" in
  *"-o go-template="*) printf "app=web," ;;
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

finish
