#!/usr/bin/env bash
# runtime/kind and runtime/k3d: the image is loaded into the cluster the chart
# is installed to.
source "$(dirname "$0")/lib.sh"

# Clusters that exist: kind has "kind" and "dev", k3d has "k3s-default" and "dev".
shim kind '
case "$*" in
  "get clusters") printf "kind\ndev\n" ;;
  "load docker-image "*) ;;
  *) exit 1 ;;
esac'
shim k3d '
case "$*" in
  "cluster get k3s-default"|"cluster get dev") ;;
  "cluster get "*) exit 1 ;;
  "image import "*) ;;
  *) exit 1 ;;
esac'
shim helm 'exit 0'

# runtime/* reads what release derived, so the consumer includes both.
# include_runtime <variant> <include vars>
include_runtime() {
  cat > "$CONSUMER/Taskfile.yaml" <<YAML
version: "3"
silent: true
vars:
  PROJECT_NAME: app
  APP_VERSION: 1.2.3
includes:
  release: { taskfile: '$LIB_ROOT/release', dir: . }
  local: { taskfile: '$LIB_ROOT/runtime/$1', dir: ., vars: $2 }
YAML
}

include_runtime kind '{}'
run_task local:install
expect_status ok "kind: installs on the default cluster"
expect_call "kind load docker-image localhost:5000/app:1.2.3 --name kind" "kind: loads into the default cluster"
expect_call "--kube-context kind-kind" "kind: installs to the default cluster's context"

include_runtime kind '{ KIND_CLUSTER: dev }'
reset_calls
run_task local:install
expect_status ok "kind: installs on a named cluster"
expect_call "--name dev" "kind: loads into the named cluster"
expect_call "--kube-context kind-dev" "kind: installs to the named cluster's context"

include_runtime kind '{ KIND_CLUSTER: missing }'
reset_calls
run_task local:install
expect_status fail "kind: a cluster that does not exist is refused"
refute_call "kind load" "kind: nothing is loaded into a cluster that does not exist"

include_runtime k3d '{}'
reset_calls
run_task local:install
expect_status ok "k3d: installs on the default cluster"
expect_call "k3d image import localhost:5000/app:1.2.3 --cluster k3s-default" "k3d: imports into the default cluster"
expect_call "--kube-context k3d-k3s-default" "k3d: installs to the default cluster's context"

include_runtime k3d '{ K3D_CLUSTER: dev }'
reset_calls
run_task local:install
expect_status ok "k3d: installs on a named cluster"
expect_call "--cluster dev" "k3d: imports into the named cluster"
expect_call "--kube-context k3d-dev" "k3d: installs to the named cluster's context"

include_runtime k3d '{ K3D_CLUSTER: missing }'
reset_calls
run_task local:install
expect_status fail "k3d: a cluster that does not exist is refused"
refute_call "k3d image import" "k3d: nothing is imported into a cluster that does not exist"

finish
