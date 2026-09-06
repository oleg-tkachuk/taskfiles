# release — commit to artifact

Everything between a commit and an artifact in a registry: the version this tree
publishes as, the container image, the Helm chart, and the one task that does all
three in the right order.

Nothing here talks to a cluster. A repository that only publishes — a CI job with
no kubeconfig anywhere near it — needs this module and not `k8s`.

```yaml
includes:
  release: { taskfile: '{{.TASKLIB}}release?ref={{.TASKLIB_TAG}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `release:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `deploy` | Verify the chart, then publish image + chart to the registry |
| `metadata` | Write APP_VERSION / GIT_COMMIT_HASH / BUILD_TIME into the deploy info file — alias `info` |
| `version` | Print the version this working tree publishes as |
| `chart` | clean:             Remove packaged chart tarballs from the component directory |
| `chart` | lint:              helm lint the chart |
| `chart` | package:           helm package the chart at the derived version |
| `chart` | push:              Package and push the chart (skipped when that version is already published) |
| `chart` | render:            Render the chart and fail on glued separators, unparseable YAML, or a resource drop |
| `chart` | verify:            Lint the chart and render it through the multi-doc separator gate |
| `deploy` | chart-only:       Publish the chart alone — for components running an upstream image |
| `image` | build:             Build the component image (skipped when the tree is clean and it is already built) |
| `image` | gc:                Trim the BuildKit cache to the keep floor and drop dangling images |
| `image` | push:              Push the component image to the registry |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `service` | image and chart name, and the label in every log line |
| `CHART_NAME` | `PROJECT_NAME` | when the chart is not named after the component |
| `REGISTRY` | `localhost:5000` | OCI host |
| `GLOBAL_REGISTRY` | — | a monorepo-wide override; wins over `REGISTRY` |
| `IMAGE_NAMESPACE` | — | path between host and name |
| `DOCKERFILE` | `./Dockerfile` | resolved from the component directory |
| `DOCKER_CONTEXT` | `.` | build context, when it is not the component directory |
| `DOCKER_BUILD_FLAGS` | — | verbatim extra buildx flags |
| `CHART_DIR` | `./deploy/chart` | |
| `CHART_APP_VERSION` | derived version | pin it when the image is upstream's |
| `CHART_MIN_RESOURCES` | `1` | render-gate floor |
| `HELM_FLAGS` | — | e.g. `--insecure-skip-tls-verify` for a self-signed registry |
| `INFO_ENV_FILE` | `./deploy/info.env` | where the build metadata is written |
| `VERSION_BASE` | `0.1.0` | base for untagged builds |
| `VERSION_TAG_EXCLUDE` | — | tag glob to keep out of the version, e.g. `api/*` |
| `APP_VERSION` | — | pin the version outright, skipping git derivation |
| `TIMEZONE` | `UTC` | zone of the build timestamp |
| `K8S_NAMESPACE` | `default` | the namespace the chart renders against |

## Examples

### A Go service that publishes to a private registry

```yaml
vars:
  PROJECT_NAME: core-api
  IMAGE_NAMESPACE: acme
  REGISTRY: registry.internal
  DOCKERFILE: ./deploy/Dockerfile
  HELM_FLAGS: --insecure-skip-tls-verify

includes:
  release: { taskfile: '{{.TASKLIB}}release?ref={{.TASKLIB_TAG}}', dir: . }

tasks:
  deploy: { cmds: [{ task: release:deploy }] }
```

```console
$ task deploy
▸ core-api · version 1.4.0 → ./deploy/info.env
▸ core-api · image · build registry.internal/acme/core-api:1.4.0
✔ core-api · chart · renders 10 resources cleanly
✔ core-api · image · pushed 1.4.0
✔ core-api · chart · pushed 1.4.0
```

Run it again on the same commit and it does nothing:

```console
$ task deploy
⚠ core-api · image · 1.4.0 already built — skipping
⚠ core-api · chart · 1.4.0 already in the registry — skipping
```

### A component whose image comes from upstream

```yaml
vars:
  PROJECT_NAME: tei-embed
  CHART_APP_VERSION: cpu-1.5     # the upstream runtime tag the chart serves
  CHART_MIN_RESOURCES: 2

tasks:
  deploy: { cmds: [{ task: release:deploy:chart-only }] }
```

### An image that needs the repo root as its build context

```yaml
vars:
  DOCKERFILE: ./Dockerfile     # relative to this component
  DOCKER_CONTEXT: ../..        # go.mod `replace` points at sibling modules
```

## The version scheme

```
exact tag, clean tree  →  X.Y.Z
otherwise, clean tree  →  <base>-dev.<committer-ts>.g<sha>
dirty tree             →  <base>-dev.<committer-ts>.g<sha>.dirty.<now>
```

The **committer** timestamp, not the wall clock: a clean tree then produces the
same version on every run, which is what makes `deploy` idempotent. A dirty tree
is not reproducible by definition, so it takes a wall-clock suffix and always
rebuilds.

Timestamp before sha, because SemVer compares pre-release identifiers left to
right: the leading numeric timestamp orders builds chronologically, and ArgoCD's
`>=0.0.0-0` resolver lands on the newest push. A sha-first form lets an
alphabetically larger sha from an **older** commit shadow a newer build.

The `g` prefix follows git-describe. Without it an all-digit short sha with a
leading zero is an invalid SemVer numeric identifier and Helm rejects the chart.

## The chart render gate

`chart:render` fails on three things: a `---` glued to the end of the previous
line, YAML that does not parse, and a resource count below `CHART_MIN_RESOURCES`.
The first is why the gate exists — a range block that strips the newline before a
separator makes every parser read the stream as one garbage document and silently
drop every resource after the first.

---

Part of [taskfiles](../README.md).
