#!/usr/bin/env bash
# helm: uninstall's context lock and its failure reporting.
source "$(dirname "$0")/lib.sh"

# Two contexts, dev current. K8S_CONTEXT pins prod.
shim kubectl '
case "$*" in
  *"config current-context"*) echo dev ;;
  *"config get-contexts -o name"*) printf "dev\nprod\n" ;;
  *) exit 1 ;;
esac'

# One release, web in ns1. FAKE_UNINSTALL_FAIL makes uninstall fail.
shim helm '
case "$1" in
  list)
    case "$*" in
      *" -q"*) echo web ;;
      *) printf "NAME\tNAMESPACE\tREVISION\nweb\tns1\t1\n" ;;
    esac ;;
  uninstall) [ -z "${FAKE_UNINSTALL_FAIL:-}" ] ;;
esac'

consumer helm helm '{ K8S_CONTEXT: prod }'

run_task helm:uninstall RELEASE=web CONFIRM=dev
expect_status fail "pinned context: CONFIRM naming the current context is refused"
refute_call "helm uninstall" "pinned context: nothing is uninstalled on a refused CONFIRM"

reset_calls
run_task helm:uninstall RELEASE=web CONFIRM=prod
expect_status ok "pinned context: CONFIRM naming the pinned context passes"
expect_call "helm uninstall --kube-context prod" "pinned context: uninstall targets the pinned context"
expect_call "helm list --kube-context prod --all-namespaces -a" "listing includes releases in every state"

run_task helm:uninstall RELEASE=web CONFIRM=staging
expect_status fail "pinned context: CONFIRM naming another context is refused"

consumer helm helm '{ K8S_CONTEXT: missing }'
run_task helm:uninstall RELEASE=web CONFIRM=missing
expect_status fail "a pinned context the kubeconfig does not have is refused"

consumer helm helm
run_task helm:uninstall RELEASE=web CONFIRM=dev
expect_status ok "unpinned: CONFIRM naming the current context passes"

run_task helm:uninstall RELEASE=web CONFIRM=prod
expect_status fail "unpinned: CONFIRM naming a context that is not current is refused"

export FAKE_UNINSTALL_FAIL=1
run_task helm:uninstall RELEASE=all CONFIRM=dev
expect_status fail "a failed uninstall fails the task"
refute_output "nothing left in scope" "a failed uninstall does not claim the scope is empty"
expect_output "could not uninstall ns1/web" "a failed uninstall names the release"
unset FAKE_UNINSTALL_FAIL

finish
