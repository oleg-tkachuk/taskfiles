# k8s — the cluster side

Rolling a deployment, tailing it, looking at what is running, installing the
chart from disk.

Independent of `release` and usable without it: a repository that operates a
cluster it does not build for needs this module alone. Include both when a
component does both — they read the same input names.

```yaml
includes:
  k8s: { taskfile: '{{printf .TASKLIB "k8s"}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `k8s:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `doctor` | Check that the context, namespace and deployment this component declares resolve |
| `logs` | Tail the deployment's logs (Ctrl-C to stop) |
| `port-forward` | Port-forward the deployment (PORT local, TARGET_PORT in the pod) |
| `restart` | Roll the deployment (no-op when the namespace or deployment is absent) |
| `status` | Show the deployment and its pods |
| `upgrade` | helm upgrade --install the release from the local chart directory |
| `uninstall` | helm uninstall this component's release — asks first |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `service` | the label in every log line |
| `K8S_NAMESPACE` | `default` | namespace every task acts in |
| `K8S_DEPLOYMENT_NAME` | `PROJECT_NAME` | when the deployment is not named after the component |
| `K8S_CONTEXT` | current context | pin a cluster |
| `CHART_DIR` | `./deploy/chart` | for `upgrade` |
| `VALUES` | — | a values file for `upgrade` |
| `ROLLOUT_TIMEOUT` | `2m` | how long `restart` waits |
| `HELM_UPGRADE_FLAGS` | — | extra flags for `upgrade` |
| `PORT` | `8080` | local port for `port-forward` |
| `TARGET_PORT` | `PORT` | pod-side port for `port-forward`, when it differs |
| `TAIL` | `100` | line count for `logs` |

## Examples

```yaml
vars:
  PROJECT_NAME: core-api
  K8S_NAMESPACE: acme
  K8S_CONTEXT: orbstack

includes:
  k8s: { taskfile: '{{printf .TASKLIB "k8s"}}', dir: . }

tasks:
  restart: { cmds: [{ task: k8s:restart }] }
```

```console
$ task k8s:restart
◉ core-api · k8s · roll deploy/core-api in acme
✔ core-api · k8s · rolled core-api

$ task k8s:port-forward PORT=8080
$ task k8s:port-forward PORT=8081 TARGET_PORT=80    # container listens on :80
$ task k8s:logs TAIL=500
```

## doctor — what this component points at

`task k8s:doctor` prints the cluster, namespace and deployment this component
resolved, so a `restart` or an `uninstall` is not the thing that discovers
them:

```
✔ billing-api · doctor · context prod-eu (pinned)
✔ billing-api · doctor · chart ./deploy/chart
✔ billing-api · doctor · namespace acme
✔ billing-api · doctor · deployment billing-api
✔ billing-api · doctor · ready
```

An unpinned context is a warning rather than a pass: without `K8S_CONTEXT`
every task here follows whatever `kubectl config use-context` last set, which
can be a different cluster tomorrow. An unreachable cluster is a warning too —
that is the normal state on a laptop, and a doctor that fails there is one
nobody runs.

## Your chart's Deployment must be named after the release

Every task addresses the Deployment directly — `deploy/<name>` — rather than
discovering it through a selector, and that name has to be exactly
`K8S_DEPLOYMENT_NAME` (`PROJECT_NAME` by default). `helm create`'s own
scaffold does not do this: it names the resource `<release>-<chart>` through
its "fullname" helper. Skip that helper and set `metadata.name` to
`{{ .Release.Name }}` directly — one component, one release, one name — the
way this library's own [demo/](../demo/README.md) chart does.

`status`'s pod list does not have that problem: it reads the selector off
the Deployment itself (`spec.selector.matchLabels`) rather than assuming a
label convention, so it finds the right pods whatever your chart happens to
label them.

## Absent is not an error

`restart` says what it did and skips when there is nothing to roll:

```console
$ task k8s:restart
○ core-api · k8s · deploy/core-api not found in acme — skipping restart
```

That is deliberate. These tasks sit in chains that have to stay green on a laptop
with no cluster running, and a silent skip reads exactly like a task that did
nothing at all — so it says which of the two happened.

---

Part of [taskfiles](../README.md).
