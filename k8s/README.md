# k8s — the cluster side

Rolling a deployment, tailing it, looking at what is running, installing the
chart from disk.

Independent of `release` and usable without it: a repository that operates a
cluster it does not build for needs this module alone. Include both when a
component does both — they read the same input names.

```yaml
includes:
  k8s: { taskfile: '{{.TASKLIB}}k8s{{.TASKLIB_REF}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `k8s:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `logs` | Tail the deployment's logs (Ctrl-C to stop) |
| `port-forward` | Port-forward the deployment (PORT local, TARGET_PORT in the pod) |
| `restart` | Roll the deployment (no-op when the namespace or deployment is absent) |
| `status` | Show the deployment and its pods |
| `upgrade` | helm upgrade --install the release from the local chart directory |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `service` | the label in every log line |
| `K8S_NAMESPACE` | `default` | namespace every task acts in |
| `K8S_DEPLOYMENT_NAME` | `PROJECT_NAME` | when the deployment is not named after the component |
| `K8S_CONTEXT` | current context | pin a cluster |
| `CHART_DIR` | `./deploy/chart` | for `upgrade` |
| `ROLLOUT_TIMEOUT` | `2m` | how long `restart` waits |
| `HELM_UPGRADE_FLAGS` | — | extra flags for `upgrade` |

## Examples

```yaml
vars:
  PROJECT_NAME: core-api
  K8S_NAMESPACE: acme
  K8S_CONTEXT: orbstack

includes:
  k8s: { taskfile: '{{.TASKLIB}}k8s{{.TASKLIB_REF}}', dir: . }

tasks:
  restart: { cmds: [{ task: k8s:restart }] }
```

```console
$ task k8s:restart
🔵 core-api · k8s · roll deploy/core-api in acme
✅ core-api · k8s · rolled core-api

$ task k8s:port-forward PORT=8080
$ task k8s:port-forward PORT=8081 TARGET_PORT=80    # container listens on :80
$ task k8s:logs TAIL=500
```

## Absent is not an error

`restart` says what it did and skips when there is nothing to roll:

```console
$ task k8s:restart
🟡 core-api · k8s · deploy/core-api not found in acme — skipping restart
```

That is deliberate. These tasks sit in chains that have to stay green on a laptop
with no cluster running, and a silent skip reads exactly like a task that did
nothing at all — so it says which of the two happened.

---

Part of [taskfiles](../README.md).
