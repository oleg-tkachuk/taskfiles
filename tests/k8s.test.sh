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

# ─── rollout:wait ────────────────────────────────────────────────────────────
# What the cluster holds is read from files: the Deployments a lookup names,
# and per Deployment its images and its chart label. BEHIND counts down the
# looks that still see the old version; sleep is instant.
export STATE="$WORK/state"
mkdir -p "$STATE"
shim sleep ':'
# shellcheck disable=SC2016 # the shim's own variables, written literally
shim kubectl '
case "$*" in
  *" rollout status "*) [ -z "${FAKE_STUCK:-}" ] ;;
  *"-o name"*)
    if [ -n "${FAKE_FORBIDDEN:-}" ]; then echo "Error from server (Forbidden)" >&2; exit 1; fi
    cat "$STATE/names" 2>/dev/null ;;
  *"-o jsonpath="*)
    left=$(cat "$STATE/behind" 2>/dev/null || printf 0)
    if [ "$left" -gt 0 ]; then printf "%s" $((left - 1)) > "$STATE/behind"; kind=old; else kind=new; fi
    case "$*" in *helm*) what=chart ;; *) what=images ;; esac
    for a in "$@"; do case "$a" in deployment.apps/*) name=${a#deployment.apps/} ;; esac; done
    cat "$STATE/$name.$what.$kind" 2>/dev/null ;;
esac'
unset FAKE_NO_DEPLOY FAKE_FORBIDDEN FAKE_UNREACHABLE FAKE_NO_LABELS

# cluster <name> <old|new> <images...> — what a Deployment runs, at one moment.
images() { name=$1 kind=$2; shift 2; printf '%s\n' "$@" > "$STATE/$name.images.$kind"; }
printf 'deployment.apps/web\n' > "$STATE/names"
images web old localhost:5000/web:1.3.0 envoy:v2
images web new localhost:5000/web:1.4.0 envoy:v2
printf 'web-1.3.0' > "$STATE/web.chart.old"
printf 'web-1.4.0_build.7' > "$STATE/web.chart.new"

consumer k8s k8s '{ PROJECT_NAME: web, K8S_NAMESPACE: apps, K8S_CONTEXT: dev }'
reset_calls
run_task k8s:rollout:wait VERSION=1.4.0
expect_status ok "rollout:wait: a Deployment already on VERSION passes"
expect_call "kubectl --context dev -n apps get deploy/web --ignore-not-found -o name" "rollout:wait: looks the component's Deployment up by name, on the pinned context"
expect_call "kubectl --context dev -n apps rollout status deployment.apps/web --timeout=" "rollout:wait: then waits for the roll"
expect_output "1.4.0 rolled out" "rollout:wait: reports the version"

printf 3 > "$STATE/behind"
reset_calls
run_task k8s:rollout:wait VERSION=1.4.0
expect_status ok "rollout:wait: waits while the Deployment still runs the old version"
expect_call "sleep 5" "rollout:wait: looks again after the poll interval"

run_task k8s:rollout:wait VERSION=1.5.0 ROLLOUT_TIMEOUT=0s
expect_status fail "rollout:wait: a version that never arrives fails at the timeout"
expect_output "1.5.0 did not arrive within 0s" "rollout:wait: says the version did not arrive"
expect_output "deployment.apps/web has localhost:5000/web:1.4.0 envoy:v2" "rollout:wait: names what the Deployment runs instead"
refute_output "rolled out" "rollout:wait: does not report a roll that was never waited for"

images web new localhost:5000/web:1.4.0@sha256:abc
run_task k8s:rollout:wait VERSION=1.4.0
expect_status ok "rollout:wait: a tag followed by a digest still matches"
images web new localhost:5000/web:11.4.0
run_task k8s:rollout:wait VERSION=1.4.0 ROLLOUT_TIMEOUT=0s
expect_status fail "rollout:wait: a tag that only ends in VERSION is not VERSION"
images web new localhost:5000/web:1.4.0-rc.1
run_task k8s:rollout:wait VERSION=1.4.0 ROLLOUT_TIMEOUT=0s
expect_status fail "rollout:wait: a longer tag is not VERSION"
images web new localhost:5000/web:1.4.0 envoy:v2

run_task k8s:rollout:wait VERSION=1.4.0+build.7 ROLLOUT_MATCH=chart
expect_status ok "rollout:wait: ROLLOUT_MATCH=chart reads the helm.sh/chart label, + written as _"
run_task k8s:rollout:wait VERSION=1.4.0 ROLLOUT_MATCH=chart ROLLOUT_TIMEOUT=0s
expect_status fail "rollout:wait: a chart label of another version fails"
expect_output "has web-1.4.0_build.7" "rollout:wait: names the chart label it found"
run_task k8s:rollout:wait VERSION=1.4.0 ROLLOUT_MATCH=tag
expect_status fail "rollout:wait: a ROLLOUT_MATCH that is neither image nor chart is refused"

# ROLLOUT_SELECTOR: every Deployment it matches has to arrive.
printf 'deployment.apps/web\ndeployment.apps/worker\n' > "$STATE/names"
images worker new localhost:5000/worker:1.3.0
reset_calls
run_task k8s:rollout:wait VERSION=1.4.0 "ROLLOUT_SELECTOR=app.kubernetes.io/part-of=shop $INJECT" ROLLOUT_TIMEOUT=0s
expect_status fail "rollout:wait: one matched Deployment behind fails the wait"
expect_call "get deploy -l app.kubernetes.io/part-of=shop $INJECT -o name" "rollout:wait: the selector reaches kubectl as one argument"
expect_not_pwned "rollout:wait: selector"
expect_output "deployment.apps/worker has localhost:5000/worker:1.3.0" "rollout:wait: names the Deployment that is behind"
refute_output "deployment.apps/web has" "rollout:wait: does not name the one that arrived"
images worker new localhost:5000/worker:1.4.0
reset_calls
run_task k8s:rollout:wait VERSION=1.4.0 ROLLOUT_SELECTOR=app.kubernetes.io/part-of=shop
expect_status ok "rollout:wait: passes once every matched Deployment is on VERSION"
expect_call "rollout status deployment.apps/worker" "rollout:wait: waits for each matched Deployment's roll"

# Not there yet is waited for; refused, or stuck, is a failure.
: > "$STATE/names"
run_task k8s:rollout:wait VERSION=1.4.0 ROLLOUT_TIMEOUT=0s
expect_status fail "rollout:wait: a Deployment that never appears fails at the timeout"
expect_output "deploy/web is not there yet" "rollout:wait: says the Deployment is not there"
printf 'deployment.apps/web\n' > "$STATE/names"
reset_calls
FAKE_FORBIDDEN=1 run_task k8s:rollout:wait VERSION=1.4.0
expect_status fail "rollout:wait: a lookup the cluster refuses fails"
refute_call "sleep" "rollout:wait: a refused lookup is not waited on"
FAKE_STUCK=1 run_task k8s:rollout:wait VERSION=1.4.0
expect_status fail "rollout:wait: a roll that does not finish fails"

run_task k8s:rollout:wait VERSION=
expect_status fail "rollout:wait: an empty VERSION is refused"
run_task k8s:rollout:wait VERSION=1.4.0 ROLLOUT_TIMEOUT=soon
expect_status fail "rollout:wait: a ROLLOUT_TIMEOUT that is not a duration is refused"
expect_output "ROLLOUT_TIMEOUT must be a whole number with s, m or h, got: soon" "rollout:wait: the refusal names the value"

finish
