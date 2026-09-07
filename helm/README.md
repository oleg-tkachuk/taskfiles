# helm — the cluster view

What is installed on a cluster, and removing it.

```yaml
includes:
  helm: { taskfile: '{{.TASKLIB}}helm{{.TASKLIB_REF}}', dir: . }
```

## Tasks

| Task | What it does |
|---|---|
| `list` | Show every Helm release on the cluster |
| `uninstall-all` | Uninstall every release in scope — destructive, asks first |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `K8S_CONTEXT` | current | pin a cluster |
| `HELM_NS` | every namespace | limit the scope to one namespace |
| `CONFIRM` | — | required by `uninstall-all`; must name the context being emptied |

## Examples

```yaml
includes:
  helm: { taskfile: '{{.TASKLIB}}helm{{.TASKLIB_REF}}', dir: . }
```

```console
$ task helm:list
NAME       NAMESPACE   REVISION  STATUS    CHART
argo-cd    argocd      13        deployed  argo-cd-10.8.1
cnpg       cnpg-system 2         deployed  cloudnative-pg-0.29.0

$ task helm:list HELM_NS=argocd            # one namespace
$ task helm:uninstall-all CONFIRM=minikube # asks before it empties it
```

## Why this is not in `k8s`

`k8s` acts on one component's deployment and is included by every component, so
a cluster-wide delete would sit in each of their task lists. These two tasks ask
about the cluster as a whole, which is a different question from the one `k8s`
answers.

Packaging, linting and pushing a chart live in [`release`](../release/README.md);
installing one component's chart is `k8s:upgrade`. This module is what is
already there.

## The two locks on `uninstall-all`

```console
$ task helm:uninstall-all
task: Task "helm:uninstall-all" cancelled because it is missing required variables: CONFIRM

$ task helm:uninstall-all CONFIRM=staging
task: CONFIRM does not name the context this would empty.
Re-run with CONFIRM=<the context you mean>, after checking
which one that is:  kubectl config current-context
```

A prompt guards against not meaning it. It does nothing about meaning it on the
wrong cluster, which is the mistake that actually happens: the current context
is ambient state nobody re-reads before typing a command. So `CONFIRM` has to
name the context, and the releases are listed before the prompt asks — so the
question is answered with the list in view rather than from memory.

---

Part of [taskfiles](../README.md).
