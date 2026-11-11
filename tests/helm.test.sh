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

# One release, web in ns1, until it is uninstalled. FAKE_UNINSTALL_FAIL makes
# uninstall fail; FAKE_PAGED puts a second release past the first page, so it
# is listed only once web is gone, and goes on the next uninstall.
# FAKE_NAMED_ALL lists a second release whose name is the word `all`.
shim helm '
gone="$CALLS.gone"
case "$1" in
  list)
    if [ -e "$gone" ]; then
      [ -n "${FAKE_PAGED:-}" ] && [ ! -e "$gone.api" ] || exit 0
      case "$*" in *" -q"*) echo api ;; *) printf "NAME\tNAMESPACE\tREVISION\napi\tns2\t1\n" ;; esac
      exit 0
    fi
    case "$*" in
      *" -q"*) echo web; [ -z "${FAKE_NAMED_ALL:-}" ] || echo all ;;
      *) printf "NAME\tNAMESPACE\tREVISION\nweb\tns1\t1\n" ;;
    esac ;;
  uninstall)
    [ -z "${FAKE_UNINSTALL_FAIL:-}" ] || exit 1
    # FAKE_STUCK: uninstall reports success and the release stays listed.
    [ -n "${FAKE_STUCK:-}" ] || { [ -e "$gone" ] && : > "$gone.api"; : > "$gone"; } ;;
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

# web is listed again, so nothing but the context can refuse this.
consumer helm helm '{ K8S_CONTEXT: missing }'
rm -f "$CALLS.gone"
reset_calls
run_task helm:uninstall RELEASE=web CONFIRM=missing
expect_status fail "a pinned context the kubeconfig does not have is refused"
expect_output "CONFIRM does not name the context this would empty" "a missing context is refused by the context lock"
refute_call "helm uninstall" "nothing is uninstalled on a context the kubeconfig does not have"

consumer helm helm
rm -f "$CALLS.gone"
run_task helm:uninstall RELEASE=web CONFIRM=dev
expect_status ok "unpinned: CONFIRM naming the current context passes"
expect_output "    web" "the release about to go is listed, indented under its heading"

# A named release that is not there is a typo, not a no-op.
rm -f "$CALLS.gone"
reset_calls
run_task helm:uninstall RELEASE=wbe CONFIRM=dev
expect_status fail "a named release that is not listed fails"
expect_output "no release named wbe in scope" "the missing release is named"
refute_call "helm uninstall" "nothing is uninstalled for a release that is not there"

# RELEASE=all means every release, so a release called `all` is refused
# rather than guessed at.
export FAKE_NAMED_ALL=1
reset_calls
run_task helm:uninstall RELEASE=all CONFIRM=dev
expect_status fail "all: a release named all is refused"
expect_output "a release is named 'all'" "all: says a release carries the word"
refute_call "helm uninstall" "all: nothing is uninstalled while it is ambiguous"
unset FAKE_NAMED_ALL

run_task helm:uninstall RELEASE=web CONFIRM=prod
expect_status fail "unpinned: CONFIRM naming a context that is not current is refused"

rm -f "$CALLS.gone"
export FAKE_UNINSTALL_FAIL=1
run_task helm:uninstall RELEASE=all CONFIRM=dev
expect_status fail "a failed uninstall fails the task"
refute_output "nothing left in scope" "a failed uninstall does not claim the scope is empty"
expect_output "could not uninstall ns1/web" "a failed uninstall names the release"
unset FAKE_UNINSTALL_FAIL

rm -f "$CALLS.gone" "$CALLS.gone.api"
run_task helm:uninstall RELEASE=all CONFIRM=dev
expect_status ok "all: a scope emptied in one pass passes"
expect_output "nothing left in scope" "all: an emptied scope says so"

rm -f "$CALLS.gone" "$CALLS.gone.api"
reset_calls
export FAKE_PAGED=1
run_task helm:uninstall RELEASE=all CONFIRM=dev
expect_status ok "all: a release past helm's page goes in a later pass"
expect_output "uninstalled ns2/api" "all: the release past the page is uninstalled"
expect_output "nothing left in scope" "all: every page emptied says so"
unset FAKE_PAGED

rm -f "$CALLS.gone" "$CALLS.gone.api"
export FAKE_STUCK=1
run_task helm:uninstall RELEASE=all CONFIRM=dev
expect_status fail "all: a release that stays listed stops after the last pass"
expect_output "1 release(s) still in scope after 20 passes" "all: says what is left and after how many passes"
refute_output "nothing left in scope" "all: a release still listed is not reported gone"
unset FAKE_STUCK

# helm:list skips without a reachable cluster, and the probe is bounded.
reset_calls
run_task helm:list
expect_call "kubectl version --request-timeout=3s" "list: probes the cluster with a bounded wait"

finish
