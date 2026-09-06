# runtime — running a locally built image on a local cluster

`release:image:build` writes to whatever Docker daemon the host talks to.
Whether that image is then visible to your cluster depends entirely on which
cluster it is:

| Runtime | What it takes |
|---|---|
| `docker/` | nothing — Docker Desktop's Kubernetes reads the same image store |
| `orbstack/` | nothing — same store |
| `minikube/` | `minikube image load` — it runs its own daemon |
| `kind/` | `kind load docker-image` — nodes are containers with their own containerd |
| `k3d/` | `k3d image import` — same reason |

That difference is the only thing these modules contain. All five expose the
same three tasks, so moving between them is one line:

```yaml
includes:
  release: { taskfile: '{{.TASKLIB}}/release{{.TASKLIB_REF}}', dir: . }
  local:   { taskfile: '{{.TASKLIB}}/runtime/orbstack{{.TASKLIB_REF}}', dir: . }
```

Include one **alongside** `release`, not instead of it: `local:image:load` moves
what `release:image:build` produced, and the version comes from the release
module.

## Tasks

| Task | What it does |
|---|---|
| `check` | fail early when the runtime or its kube context is not there |
| `image:load` | make the built image visible to the cluster (a logged no-op where the store is shared) |
| `install` | `helm upgrade --install` from the chart directory, pinned to the built tag with `pullPolicy=IfNotPresent` |

## Inputs

The same vars `release` reads — `PROJECT_NAME`, `REGISTRY`, `IMAGE_NAMESPACE`,
`CHART_DIR`, `K8S_NAMESPACE`, `K8S_CONTEXT` — plus:

| Var | Default | Meaning |
|---|---|---|
| `K8S_CONTEXT` | the runtime's usual name | `orbstack`, `minikube`, `kind-kind`, … |
| `VALUES` | — | a values file for `install` |
| `HELM_UPGRADE_FLAGS` | — | extra flags for `install` |
| `KIND_CLUSTER` / `K3D_CLUSTER` | — | when the cluster is not the default one |

## Examples

```yaml
vars:
  PROJECT_NAME: core-api
  K8S_NAMESPACE: acme

includes:
  release: { taskfile: '{{.TASKLIB}}/release{{.TASKLIB_REF}}', dir: . }
  local:   { taskfile: '{{.TASKLIB}}/runtime/minikube{{.TASKLIB_REF}}', dir: . }

tasks:
  deploy:local:
    desc: "Build and install into the local cluster — no registry"
    cmds:
      - task: release:image:build
      - task: local:install
```

```console
$ task deploy:local
▸ core-api · image · build registry.example/acme/core-api:0.1.0-dev.…
✔ core-api · local · minikube running
▸ core-api · local · minikube image load registry.example/acme/core-api:0.1.0-dev.…
▸ core-api · local · helm upgrade --install into minikube/acme
✔ core-api · local · 0.1.0-dev.… installed into minikube
```

## Why one directory per runtime rather than one module with a switch

`docker/` and `orbstack/` are the same file with different labels today, which
looks like duplication — and would be, if the point were to save lines. The
point is that the include line names the runtime, so a reader of a consumer's
Taskfile can see which cluster it targets without opening anything else. When a
third shared-store runtime shows up, it should become a var rather than a sixth
copy.

---

Part of [taskfiles](../README.md).
