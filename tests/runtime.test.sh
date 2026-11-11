#!/usr/bin/env bash
# runtime/kind, runtime/k3d and runtime/minikube: the image is loaded into the cluster the chart
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
# Profiles that run: "minikube" and "dev".
shim minikube '
case "$*" in
  "status -p minikube "*|"status -p dev "*) echo Running ;;
  "status "*) exit 7 ;;
  "image load "*) ;;
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

# The release is the name k8s addresses: K8S_DEPLOYMENT_NAME, else PROJECT_NAME.
include_runtime kind '{}'
reset_calls
run_task local:install
expect_call "helm upgrade --install app " "release: named after PROJECT_NAME by default"
include_runtime kind '{ K8S_DEPLOYMENT_NAME: app-api }'
reset_calls
run_task local:install
expect_call "helm upgrade --install app-api " "release: named after K8S_DEPLOYMENT_NAME when set"

include_runtime minikube '{}'
reset_calls
run_task local:install
expect_status ok "minikube: installs on the default profile"
expect_call "minikube image load -p minikube localhost:5000/app:1.2.3" "minikube: loads into the default profile"
expect_call "--kube-context minikube" "minikube: installs to the default profile's context"

include_runtime minikube '{ MINIKUBE_PROFILE: dev }'
reset_calls
run_task local:install
expect_status ok "minikube: installs on a named profile"
expect_call "minikube image load -p dev " "minikube: loads into the named profile"
expect_call "--kube-context dev" "minikube: installs to the named profile's context"

include_runtime minikube '{ MINIKUBE_PROFILE: missing }'
reset_calls
run_task local:install
expect_status fail "minikube: a profile that is not running is refused"
refute_call "minikube image load" "minikube: nothing is loaded into a profile that is not running"

# runtime/docker and runtime/orbstack: `check` passes only on a context the
# kubeconfig has, by its exact name.
shim docker 'exit 0'
shim kubectl '
case "$*" in
  "config get-contexts -o name") printf "docker-desktop\norbstack\n" ;;
  *) exit 1 ;;
esac'
for variant in docker orbstack; do
  case "$variant" in docker) ctx=docker-desktop ready="Docker Desktop ready" ;; orbstack) ctx=orbstack ready="OrbStack ready" ;; esac
  include_runtime "$variant" '{}'
  run_task local:check
  expect_status ok "$variant: check passes on its default context"
  expect_output "$ready ($ctx)" "$variant: check names the context it found"

  include_runtime "$variant" '{ K8S_CONTEXT: missing }'
  run_task local:check
  expect_status fail "$variant: a context the kubeconfig does not have is refused"
  expect_output "there is no 'missing' kube context" "$variant: the missing context is named"

  # A name is compared as written: a dot in it is a dot, not any character.
  include_runtime "$variant" '{ K8S_CONTEXT: docker.desktop }'
  run_task local:check
  expect_status fail "$variant: a context is matched by its exact name"
done

finish
