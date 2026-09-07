# release — commit to artifact

Everything between a commit and an artifact in a registry: the version this tree
publishes as, the container image, the Helm chart, and the one task that does all
three in the right order.

Nothing here talks to a cluster. A repository that only publishes — a CI job with
no kubeconfig anywhere near it — needs this module and not `k8s`.

```yaml
includes:
  release: { taskfile: '{{printf .TASKLIB "release"}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `release:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `deploy` | Verify the chart, then publish image + chart to the registry |
| `deploy:chart-only` | Publish the chart alone — for components running an upstream image |
| `doctor` | Check that everything this component declares actually resolves |
| `metadata` | Write APP_VERSION / GIT_COMMIT_HASH / BUILD_TIME into the deploy info file — alias `info` |
| `version` | Print the version this working tree publishes as |
| `image:build` | Build the component image (skipped when the tree is clean and it is already built) |
| `image:push` | Push the component image to the registry |
| `image:gc` | Trim the BuildKit cache to the keep floor and drop dangling images |
| `chart:verify` | Lint the chart and render it through the multi-doc separator gate |
| `chart:lint` | helm lint the chart |
| `chart:render` | Render the chart and fail on glued separators, unparseable YAML, or a resource drop |
| `chart:validate` | Check the rendered manifests against the Kubernetes schemas (kubeconform) |
| `chart:package` | helm package the chart at the derived version |
| `chart:push` | Package and push the chart (skipped when that version is already published) |
| `chart:clean` | Remove packaged chart tarballs from the component directory |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `service` | image and chart name, and the label in every log line |
| `CHART_NAME` | `PROJECT_NAME` | when the chart is not named after the component |
| `IMAGE_NAME` | `PROJECT_NAME` | image name when it differs from the label in the log lines |
| `REGISTRY` | `localhost:5000` | OCI host |
| `GLOBAL_REGISTRY` | — | a monorepo-wide override; wins over `REGISTRY` |
| `IMAGE_NAMESPACE` | — | path between host and name |
| `DOCKERFILE` | `./Dockerfile` | resolved from the component directory, **not** from `DOCKER_CONTEXT` |
| `DOCKER_CONTEXT` | `.` | build context, when it is not the component directory |
| `DOCKER_BUILD_FLAGS` | — | verbatim extra buildx flags |
| `IMAGE_LATEST` | `0` | set to `1` to push a floating `:latest` beside the version tag |
| `CHART_DIR` | `./deploy/chart` | the chart every chart task reads |
| `CHART_APP_VERSION` | derived version | pin it when the image is upstream's |
| `CHART_MIN_RESOURCES` | `1` | render-gate floor |
| `K8S_VERSION` | — | schema version `chart:validate` checks against |
| `KUBECONFORM_FLAGS` | — | extra kubeconform flags |
| `HELM_FLAGS` | — | e.g. `--insecure-skip-tls-verify` for a self-signed registry |
| `HELM_LINT_FLAGS` | — | extra flags for `helm lint` |
| `HELM_TEMPLATE_FLAGS` | — | extra flags for `helm template` |
| `HELM_PACKAGE_FLAGS` | — | extra flags for `helm package` |
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
  REGISTRY: registry.example.com
  DOCKERFILE: ./deploy/Dockerfile
  HELM_FLAGS: --insecure-skip-tls-verify

includes:
  release: { taskfile: '{{printf .TASKLIB "release"}}', dir: . }

tasks:
  deploy: { cmds: [{ task: release:deploy }] }
```

```console
$ task deploy
◉ core-api · version 1.4.0 → ./deploy/info.env
◉ core-api · image · build registry.example.com/acme/core-api:1.4.0
✔ core-api · chart · renders 10 resources cleanly
✔ core-api · image · pushed 1.4.0
✔ core-api · chart · pushed 1.4.0
```

Run it again on the same commit and it does nothing:

```console
$ task deploy
○ core-api · image · 1.4.0 already built — skipping
○ core-api · chart · 1.4.0 already in the registry — skipping
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
  DOCKERFILE: ./Dockerfile     # resolved from THIS directory, not the context
  DOCKER_CONTEXT: ../..        # go.mod `replace` points at sibling modules
```

The two are resolved differently and it is easy to get wrong: `docker build`
reads `--file` relative to the working directory and only the final argument is
the context. A component whose image needs the repo root sets the context to
`../..` and still names its own `./Dockerfile`.

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

## doctor — what a component declares, checked before it costs minutes

`task release:doctor` reports, in one pass, whether what this component declares
actually resolves — the version, the chart, the Dockerfile, the build contexts
and the registry. It is a report, not a gate: it prints every problem instead of
stopping at the first, then exits non-zero if any of them is fatal.

```
✔ billing-api · doctor · version 0.1.0-dev.1788728844.g6ec96167
✔ billing-api · doctor · chart ./deploy/chart → oci://registry.example.com/acme/charts/billing-api
✔ billing-api · doctor · image registry.example.com/acme/billing-api from ./deploy/Dockerfile (context .)
✔ billing-api · doctor · build context proto is passed
✔ billing-api · doctor · registry registry.example.com answers
✔ billing-api · doctor · ready to publish
```

It checks the mistakes that have actually happened here:

- **a `DOCKERFILE` named relative to the build context.** `docker build --file`
  reads the path from the working directory, so a component building from the
  repo root still names its own Dockerfile — `DOCKER_CONTEXT: ../..` with
  `DOCKERFILE: ./Dockerfile`. Fatal when `DOCKERFILE` is declared and missing;
  an absent default one is only a note, because a chart around an upstream image
  is a supported shape.
- **`CHART_NAME` disagreeing with `Chart.yaml#name`.** `helm package` names the
  `.tgz` after `Chart.yaml`, while the push looks for `<CHART_NAME>-<version>.tgz`
  — a mismatch is a push that 404s on a file that was never written.
- **a `COPY --from=NAME` that names nothing.** `NAME` must be a build stage, an
  earlier stage index, or an external tree passed as
  `--build-context NAME=<path>` in `DOCKER_BUILD_FLAGS`. When it is none of the
  three, BuildKit reads it as an image and pulls `docker.io/library/NAME:latest`
  — which surfaces as a registry permission error pointing nowhere near the
  cause.
- **a version that cannot be derived**, an unreachable registry, and missing
  tools.

---


## chart:validate does not ignore missing schemas

`-ignore-missing-schemas` turns an apiVersion the cluster no longer serves into
a *skip* — a chart on `apps/v1beta1` renders, lints, and passes while nothing
is checked. Verified: with the flag that chart reports `Skipped: 1` and exits
0; without it, `Errors: 1` and exit 1, while a real chart still validates
12 of 12 clean.

A chart that ships custom resources adds `-ignore-missing-schemas` or
`-skip <Kind>` through `KUBECONFORM_FLAGS`, where a reader can see it.

## `:latest` is off by default

Nothing here needs it. Charts read their tag from the chart's `appVersion`,
which `deploy` stamps with the version it tagged the image with, so a
deployment always names an exact build. A floating `:latest` breaks that: what
it resolved to yesterday is gone, and a rollback has nothing to roll back to.

`IMAGE_LATEST: '1'` turns it on for the repositories that genuinely need it —
where something outside this pipeline pulls the image by name. The version tag
is still pushed first, and `:latest` is a second tag on the same digest.

Part of [taskfiles](../README.md).
