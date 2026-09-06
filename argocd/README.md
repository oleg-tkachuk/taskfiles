# argocd — make the cluster re-read the registry

A push to the OCI registry does not reach the cluster until Argo's repo-server
drops its cached chart. Without a hard refresh the cluster can sit on the
previous version until the next poll fires — the deploy looks done and is not.

```yaml
includes:
  argocd: { taskfile: '{{.TASKLIB}}argocd{{.TASKLIB_REF}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `argocd:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `list` | Show the sync + health state of every application matching APP_PREFIX |
| `refresh` | Hard-refresh every Argo application matching APP_PREFIX |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `APP_PREFIX` | — | required; which applications to refresh |
| `ARGOCD_NS` | `argocd` | |
| `K8S_CONTEXT` | current context | |

## Examples

```yaml
includes:
  argocd: { taskfile: '{{.TASKLIB}}argocd{{.TASKLIB_REF}}', dir: . }

tasks:
  deploy:sync:
    cmds:
      - task: argocd:refresh
        vars: { APP_PREFIX: "acme-" }
```

```console
$ task argocd:list APP_PREFIX=acme-
$ task deploy:sync
✔ argocd · hard-refreshed acme-api
✔ argocd · hard-refreshed acme-worker
```

## APP_PREFIX has no default

A bare prefix would hard-refresh unrelated applications — the infra Postgres, a
registry — that must not be touched. Name the family explicitly, and keep the
prefix narrow enough that it cannot match a sibling.

## No cluster is not a failure

Every task here no-ops when kubectl cannot reach the cluster, so it is safe to
chain after a deploy on a laptop.

---

Part of [taskfiles](../README.md).
