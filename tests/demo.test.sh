#!/usr/bin/env bash
# demo: the registry's ports come from the kind config alone, the chart is
# installed against the registry the image went to, and deploy loads the image
# into kind once.
source "$(dirname "$0")/lib.sh"

# A copy of the demo beside links to every module, so its TASKLIB ('../%s')
# resolves and nothing it writes lands in this checkout.
LIB="$WORK/lib"
mkdir -p "$LIB"
for m in "$LIB_ROOT"/*/; do
  m=${m%/}
  case "${m##*/}" in demo) ;; *) ln -s "$m" "$LIB/${m##*/}" ;; esac
done
cp -R "$LIB_ROOT/demo" "$LIB/demo"
rm -rf "$LIB/demo/.task"
DEMO="$LIB/demo"

# demo_task <args...> — runs a task in the demo copy.
demo_task() {
  status=0
  (cd "$DEMO" && task --yes "$@") < /dev/null > "$OUT" 2>&1 || status=$?
  printf '%s' "$status" > "$WORK/last-status"
}

# kind: no cluster yet until one is created. FAKE_REGISTRY_DOWN fails curl.
shim kind '
case "$1 $2" in
  "get clusters") [ -f "$CALLS.cluster" ] && echo demo ;;
  "create cluster") touch "$CALLS.cluster" ;;
esac
exit 0'
# release renders the chart and refuses an empty render, so template prints one
# resource.
shim helm '
case "$1" in
  template) printf "apiVersion: v1\nkind: Service\nmetadata:\n  name: demo\n" ;;
esac
exit 0'
shim curl '[ -z "${FAKE_REGISTRY_DOWN:-}" ]'
# The local image store holds an image once something has built it.
shim docker '
case "$*" in
  "image inspect"*) [ -f "$CALLS.built" ] ;;
  *build*) touch "$CALLS.built" ;;
esac'
shim kubectl 'exit 1'

demo_task registry:up
expect_status ok "registry:up: creates the cluster and installs the registry"
expect_call "kind create cluster --name demo --config ./deploy/kind-config.yaml" "registry:up: the cluster reads the kind config"
expect_call "helm upgrade --install registry ./deploy/registry --kube-context kind-demo" "registry:up: installs the registry on the demo cluster"
expect_call "--set nodePort=30500" "registry:up: the node port comes from the kind config"

reset_calls
demo_task registry:check
expect_status ok "registry:check: a registry that answers passes"
expect_call "curl -fsS -o /dev/null --retry 10 --retry-delay 1 --retry-all-errors --max-time 2 http://localhost:5050/v2/" \
  "registry:check: probes the mapped host port, with curl's own retries"

export FAKE_REGISTRY_DOWN=1
demo_task deploy APP_VERSION=1.0.0
expect_status fail "deploy: refuses when the registry does not answer"
expect_output "localhost:5050 is not answering" "deploy: says which registry did not answer"
unset FAKE_REGISTRY_DOWN

reset_calls
demo_task deploy APP_VERSION=1.0.0
expect_status ok "deploy: builds, pushes and installs"
loads=$(grep -c '^kind load docker-image' "$CALLS" || true)
if [ "$loads" = 1 ]; then pass "deploy: loads the image into kind once"; else fail "deploy: loaded the image $loads times"; fi
expect_call "--set image.repository=localhost:5050/taskfiles-demo" "deploy: installs the chart against the registry the image went to"

# One port, one place: moving the kind config's host port moves the registry.
yq -i '.nodes[0].extraPortMappings[0].hostPort = 5151 | .nodes[0].extraPortMappings[0].containerPort = 30515' "$DEMO/deploy/kind-config.yaml"
reset_calls
demo_task deploy APP_VERSION=1.0.0
expect_status ok "moved ports: deploy still runs"
expect_call "http://localhost:5151/v2/" "moved ports: the registry check follows the host port"
expect_call "--set image.repository=localhost:5151/taskfiles-demo" "moved ports: the chart follows the host port"
reset_calls
demo_task registry:up
expect_call "--set nodePort=30515" "moved ports: the registry's node port follows the kind config"

finish
