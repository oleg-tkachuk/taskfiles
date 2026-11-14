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
| `rollout:wait` | Wait until the Deployment runs VERSION and has rolled out (VERSION=1.4.0) |
| `restart` | Roll the deployment (no-op when the cluster, namespace or deployment is absent; `RESTART_UNREACHABLE=fail` makes an unreachable cluster an error) |
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
| `ROLLOUT_TIMEOUT` | `2m` | how long `restart` waits, and `rollout:wait` in all; a whole number with `s`, `m` or `h` |
| `RESTART_UNREACHABLE` | `skip` | what `restart` does when the cluster does not answer: `skip`, or `fail` |
| `VERSION` | — | required by `rollout:wait`: the version to wait for |
| `ROLLOUT_MATCH` | `image` | what says a Deployment runs `VERSION`: `image`, a container's image tag, or `chart`, its `helm.sh/chart` label |
| `ROLLOUT_SELECTOR` | — | label selector: `rollout:wait` then waits for every Deployment it matches, not `K8S_DEPLOYMENT_NAME` alone |
| `ROLLOUT_MIN` | `1` | with `ROLLOUT_SELECTOR`: how many Deployments it has to match before the wait can end |
| `HELM_UPGRADE_FLAGS` | — | extra flags for `upgrade` |
| `PORT` | `8080` | local port for `port-forward` |
| `TARGET_PORT` | `PORT` | pod-side port for `port-forward`, when it differs |
| `LOG_TAIL` | `100` | line count for `logs` |

`PROJECT_NAME`, `K8S_NAMESPACE` and `K8S_DEPLOYMENT_NAME` are also read from
the `vars:` of a `task:` call — see
[One include, several Deployments](#one-include-several-deployments).

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
◉ start · core-api · k8s · roll deploy/core-api in acme
✔ ok    · core-api · k8s · rolled core-api

$ task k8s:port-forward PORT=8080
$ task k8s:port-forward PORT=8081 TARGET_PORT=80    # container listens on :80
$ task k8s:logs LOG_TAIL=500
```

## One include, several Deployments

`PROJECT_NAME`, `K8S_NAMESPACE` and `K8S_DEPLOYMENT_NAME` are read on every
call. A value in the `vars:` of a `task:` call wins over the include's, for
that call alone, so a repository that operates more than one Deployment names
each where it acts on it:

```yaml
includes:
  k8s: { taskfile: '{{printf .TASKLIB "k8s"}}', dir: ., vars: { K8S_NAMESPACE: acme } }

tasks:
  restart:
    cmds:
      - task: k8s:restart
        vars: { K8S_DEPLOYMENT_NAME: example-app }
      - task: k8s:restart
        vars: { K8S_DEPLOYMENT_NAME: my-service, K8S_NAMESPACE: jobs }
```

The order, most specific first: the call's value when it is not empty, the
include's, the default. A `PROJECT_NAME` on the call names the Deployment as
well, unless a `K8S_DEPLOYMENT_NAME` is given on the call or at the include.
An empty value on the call turns nothing off — it falls back, as
[an empty value does everywhere](../README.md#an-empty-value-turns-nothing-off).

This is the `vars:` of a `task:` call, not the command line: Task ranks an
include's `vars:` above the command line, so `task k8s:restart
K8S_NAMESPACE=…` reaches the module only when the include sets none.
Pin `K8S_CONTEXT` at the include, never on a call. The kubectl tasks take
the context as the include loads and do not see a call's, while `upgrade` and
`uninstall` hand helm whatever the call says — so a context given on a call
would send the two halves of this module to different clusters.

## restart — when there is nothing to roll

`restart` skips, and passes, when the cluster does not answer or the
Deployment is not there: it sits in chains that have to stay green on a
laptop with no cluster running. It says which of the two happened, and a
lookup the cluster refuses — RBAC, an expired login — fails.

In a chain that deploys, a cluster that did not answer is a roll that never
ran, and a green step hides it. `RESTART_UNREACHABLE=fail` makes that case an
error, at the include or on the call:

```yaml
- task: k8s:restart
  vars: { RESTART_UNREACHABLE: fail }
```

```
✖ fail  · core-api · k8s · cluster unreachable — nothing was rolled
```

An absent namespace or Deployment is still a skip under it: that is an answer
from the cluster, not the lack of one.

## doctor — what this component points at

`task k8s:doctor` prints the cluster, namespace and deployment this component
resolved, so a `restart` or an `uninstall` is not the thing that discovers
them:

```
✔ ok    · orders-api · doctor · context prod-eu (pinned)
✔ ok    · orders-api · doctor · chart ./deploy/chart
✔ ok    · orders-api · doctor · namespace acme
✔ ok    · orders-api · doctor · deployment orders-api
✔ ok    · orders-api · doctor · ready
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

## Waiting for a version someone else deploys

When Argo CD, Flux or another pipeline does the deploying, the publish step
ends before anything has changed in the cluster. `kubectl rollout status` is
not the wait for that: until the new chart is picked up the Deployment is the
old one, fully rolled out, and the wait returns at once.

`rollout:wait` first waits for the Deployment to carry the version, then for
the roll, both inside `ROLLOUT_TIMEOUT`:

```console
$ task release:deploy && task argocd:refresh APP_PREFIX=acme-
$ task k8s:rollout:wait VERSION=$(task release:version)
◉ start · core-api · k8s · wait for 1.4.0 on deploy/core-api in acme
deployment "core-api" successfully rolled out
✔ ok    · core-api · k8s · 1.4.0 rolled out
```

By default the version is a container's image tag. A chart that runs someone
else's image has a version of its own and no such tag: `ROLLOUT_MATCH: chart`
reads the `helm.sh/chart` label instead, which the chart has to set on the
Deployment.

One component, one Deployment is this module's rule, and the wait follows it.
A release that brings several sets `ROLLOUT_SELECTOR`, and every Deployment
the selector matches has to arrive:

```yaml
vars: { ROLLOUT_SELECTOR: app.kubernetes.io/instance=core-api }
```

A selector matches what exists. On a first install the Deployments are created
one after another, and the wait would end with the first of them: say how many
the release brings, and it waits until that many are there.

```yaml
vars: { ROLLOUT_SELECTOR: app.kubernetes.io/instance=core-api, ROLLOUT_MIN: "3" }
```

A wait that times out names what each Deployment runs instead. A Deployment
that does not exist yet is waited for, since a first install creates it; a
lookup the cluster refuses fails at once.

## Absent is not an error

`restart` says what it did and skips when there is nothing to roll:

```console
$ task k8s:restart
○ skip  · core-api · k8s · deploy/core-api not found in acme — skipping restart
```

That is deliberate. These tasks sit in chains that have to stay green on a laptop
with no cluster running, and a silent skip reads exactly like a task that did
nothing at all — so it says which of the two happened.

---

Part of [taskfiles](../README.md).
