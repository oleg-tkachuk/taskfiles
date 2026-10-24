#!/usr/bin/env bash
# k8s, against a real API server: restart tells "nothing to roll" from "the
# cluster refused". It asks with `kubectl get --ignore-not-found -o name`, and
# relies on kubectl printing nothing and exiting 0 for an absent deployment or
# namespace, and failing for anything the server refuses.
#
# CONTRACTS_KUBE_CONTEXT names the cluster to use; CI points it at a kind
# cluster made for the run. Everything happens in a namespace made here and
# deleted after, through a copy of the kubeconfig — the caller's own is never
# written.
source "$(dirname "$0")/../lib.sh"

ctx=${CONTRACTS_KUBE_CONTEXT:-}
if [ -z "$ctx" ]; then
  # A contract that cannot run must not read as one that passed where it is
  # the gate; on a laptop it is a choice.
  if [ -n "${CI:-}" ]; then fail "CONTRACTS_KUBE_CONTEXT is not set — the k8s contract ran against nothing"; finish; fi
  printf '%s\n' "○ k8s contract skipped — set CONTRACTS_KUBE_CONTEXT to a cluster it may make a namespace in" >&2
  exit 0
fi

# Image the deployment runs: a container that starts and does nothing.
readonly PAUSE_IMAGE=registry.k8s.io/pause:3.10
# How long a deployment may take to come up before the case gives up.
readonly READY_TIMEOUT=120s
# A server nothing listens on: the TCP discard port, refused at once.
readonly NOWHERE=https://127.0.0.1:9

kubectl config view --raw --minify --flatten --context "$ctx" > "$WORK/kubeconfig"
export KUBECONFIG="$WORK/kubeconfig"
cluster=$(kubectl config view -o jsonpath='{.contexts[0].context.cluster}')
ns="taskfiles-contract-$(date +%s)-$$"
kubectl --context "$ctx" create namespace "$ns" >/dev/null
trap 'kubectl --context "$ctx" delete namespace "$ns" --wait=false >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
k() { kubectl --context "$ctx" -n "$ns" "$@"; }

# ─── nothing to roll ──────────────────────────────────────────────────────────
consumer k8s k8s "{ PROJECT_NAME: web, K8S_NAMESPACE: $ns, K8S_CONTEXT: $ctx }"
run_task k8s:restart
expect_status ok "restart: an absent deployment is skipped"
expect_output "deploy/web not found in $ns" "restart: says the deployment is not there"

consumer k8s k8s "{ PROJECT_NAME: web, K8S_NAMESPACE: $ns-absent, K8S_CONTEXT: $ctx }"
run_task k8s:restart
expect_status ok "restart: an absent namespace is skipped"
expect_output "not found in $ns-absent" "restart: says nothing was there to roll"

# ─── a deployment to roll ────────────────────────────────────────────────────
k create deployment web --image="$PAUSE_IMAGE" >/dev/null
k rollout status deploy/web --timeout="$READY_TIMEOUT" >/dev/null
consumer k8s k8s "{ PROJECT_NAME: web, K8S_NAMESPACE: $ns, K8S_CONTEXT: $ctx }"
run_task k8s:restart
expect_status ok "restart: an existing deployment is rolled"
expect_output "rolled web" "restart: reports the roll"

# ─── a cluster that refuses ──────────────────────────────────────────────────
# A service account with no role: the API server answers, and forbids the get.
k create serviceaccount nobody >/dev/null
kubectl config set-credentials contract-nobody --token="$(k create token nobody)" >/dev/null
kubectl config set-context contract-nobody --cluster="$cluster" --user=contract-nobody >/dev/null
consumer k8s k8s "{ PROJECT_NAME: web, K8S_NAMESPACE: $ns, K8S_CONTEXT: contract-nobody }"
run_task k8s:restart
expect_status fail "restart: a lookup the cluster forbids fails"
expect_output "could not look up deploy/web in $ns" "restart: says the lookup failed, not that nothing is there"

# ─── no cluster at all ───────────────────────────────────────────────────────
kubectl config set-cluster contract-nowhere --server="$NOWHERE" >/dev/null
kubectl config set-context contract-nowhere --cluster=contract-nowhere --user=contract-nobody >/dev/null
consumer k8s k8s "{ PROJECT_NAME: web, K8S_NAMESPACE: $ns, K8S_CONTEXT: contract-nowhere }"
run_task k8s:restart
expect_status ok "restart: an unreachable cluster is skipped"
expect_output "cluster unreachable" "restart: says the cluster was unreachable"

finish
