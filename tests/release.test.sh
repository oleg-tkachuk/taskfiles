#!/usr/bin/env bash
# release: a value that names the image, the chart or a path reaches docker and
# helm as one argument of data, never as shell; the *_FLAGS inputs are shell
# by contract and still word-split.
source "$(dirname "$0")/lib.sh"

readonly VERSION=1.2.3

# Besides the "<name> <argv>" line lib.sh logs, each shim logs its argv one
# bracket per argument, so a test can tell one argument from several.
# shellcheck disable=SC2016 # the shim's own $@, written literally
readonly ARGV='printf "[%s]" "$@" >> "$CALLS"; printf "\n" >> "$CALLS"'
# Nothing is in the local image store, so image:build always builds.
# shellcheck disable=SC2016 # the shim's own $1 and $2, written literally
shim docker "$ARGV"'
case "$1 $2" in "image inspect") exit 1 ;; esac'
shim helm "$ARGV"
# doctor probes the registry; a payload host must not reach DNS.
shim curl 'printf 000'

# payload <marker> — a command substitution that creates $WORK/<marker> if a
# shell ever evaluates it. ${IFS} stands in for the space a YAML key would trim.
payload() { printf '%s' "\$(touch\${IFS}$WORK/$1)"; }

# expect_inert <marker> <case name> — the payload did not run.
expect_inert() {
  if [ -e "$WORK/$1" ]; then fail "$2: the payload ran"; else pass "$2"; fi
}

# A chart and a Dockerfile at the default paths, for the cases that do not
# move them.
mkdir -p "$CONSUMER/deploy/chart"
printf 'name: app\n' > "$CONSUMER/deploy/chart/Chart.yaml"
printf 'FROM scratch\n' > "$CONSUMER/Dockerfile"

# ─── image:build ──────────────────────────────────────────────────────────────
# build_with <input> <marker> <expected --tag> — builds with <input> set to the
# payload and checks the tag reached docker as a single argument.
build_with() {
  input=$1 marker=$2 tag=$3
  name="PROJECT_NAME: app, "
  [ "$input" = PROJECT_NAME ] && name=
  consumer release release "{ ${name}APP_VERSION: $VERSION, $input: '$(payload "$marker")' }"
  reset_calls
  run_task release:image:build
  expect_status ok "image:build: $input with a command substitution builds"
  expect_inert "$marker" "image:build: $input is not run as shell"
  expect_call "[--tag][$tag]" "image:build: $input reaches docker as one argument"
}

p=$(payload pwned-project)
build_with PROJECT_NAME pwned-project "localhost:5000/$p:$VERSION"
p=$(payload pwned-ns)
build_with IMAGE_NAMESPACE pwned-ns "localhost:5000/$p/app:$VERSION"
p=$(payload pwned-registry)
build_with REGISTRY pwned-registry "$p/app:$VERSION"

p=$(payload pwned-dockerfile)
mkdir -p "$(dirname "$CONSUMER/$p")"
printf 'FROM scratch\n' > "$CONSUMER/$p"
consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION, DOCKERFILE: '$p' }"
reset_calls
run_task release:image:build
expect_status ok "image:build: DOCKERFILE with a command substitution builds"
expect_inert pwned-dockerfile "image:build: DOCKERFILE is not run as shell"
expect_call "[--file][$p]" "image:build: DOCKERFILE reaches docker as one argument"

consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION, DOCKER_BUILD_FLAGS: '--pull --build-arg X=1' }"
reset_calls
run_task release:image:build
expect_status ok "image:build: DOCKER_BUILD_FLAGS builds"
expect_call "[--pull][--build-arg][X=1][.]" "image:build: DOCKER_BUILD_FLAGS is word-split"

# ─── chart ────────────────────────────────────────────────────────────────────
p=$(payload pwned-chart)
mkdir -p "$CONSUMER/$p"
printf 'name: app\n' > "$CONSUMER/$p/Chart.yaml"

consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION, CHART_DIR: '$p', HELM_LINT_FLAGS: '--strict --quiet' }"
reset_calls
run_task release:chart:lint
expect_status ok "chart:lint: CHART_DIR with a command substitution lints"
expect_inert pwned-chart "chart:lint: CHART_DIR is not run as shell"
expect_call "[lint][--strict][--quiet][$p]" "chart:lint: CHART_DIR is one argument, HELM_LINT_FLAGS is word-split"

reset_calls
run_task release:chart:package
expect_status ok "chart:package: CHART_DIR with a command substitution packages"
expect_inert pwned-chart "chart:package: CHART_DIR is not run as shell"
expect_call "[package][$p][--version][$VERSION]" "chart:package: CHART_DIR reaches helm as one argument"

p=$(payload pwned-chart-name)
consumer release release "{ PROJECT_NAME: '$p', APP_VERSION: $VERSION }"
reset_calls
run_task release:chart:package
expect_status ok "chart:package: PROJECT_NAME with a command substitution packages"
expect_inert pwned-chart-name "chart:package: PROJECT_NAME is not run as shell"
expect_output "packaged $p-$VERSION.tgz" "chart:package: PROJECT_NAME is printed as text"

# ─── doctor ───────────────────────────────────────────────────────────────────
# Its exit status is not the point here: the payload registry never answers.
p=$(payload pwned-chart)
r=$(payload pwned-doctor-registry)
consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION, CHART_DIR: '$p', REGISTRY: '$r' }"
reset_calls
run_task release:doctor
expect_inert pwned-chart "doctor: CHART_DIR is not run as shell"
expect_inert pwned-doctor-registry "doctor: REGISTRY is not run as shell"
expect_output "chart $p → oci://$r/charts/app" "doctor: CHART_DIR and REGISTRY are printed as text"

finish
