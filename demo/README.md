# taskfiles-demo

A working example of the [taskfiles](../README.md) library — one small Go
service, taken from `go test` to a signed, running deployment, using nothing
but the modules this repository ships. The service itself is a prop: a
`/healthz`, a `/quote`, a `/version`. What is actually being demonstrated is
that six `includes:` lines and a dozen `task` calls replace a Makefile, a
Dockerfile linter invocation, a signing script and a deploy runbook that most
projects hand-roll and then let rot.

Read [Taskfile.yaml](Taskfile.yaml) alongside this file — every step below
names the task it runs.

## Prerequisites

| Tool | Used for |
|---|---|
| [Task](https://taskfile.dev/docs/installation) 3.53+ | everything |
| Go 1.27+ | `go:*` |
| Docker (or OrbStack/Podman) | `docker build`, `kind`'s nodes |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | the local cluster |
| kubectl, [helm](https://helm.sh/docs/intro/install/) | everything cluster-side |
| [cosign](https://docs.sigstore.dev/cosign/system_config/installation/), [syft](https://github.com/anchore/syft#installation) | `sign` |
| [gitleaks](https://github.com/gitleaks/gitleaks#installing), [trivy](https://github.com/aquasecurity/trivy#installation), [hadolint](https://github.com/hadolint/hadolint#install), [golangci-lint](https://golangci-lint.run/docs/welcome/install/) | `scan`, `verify` |

Nothing here needs a real registry, a real cluster or a cloud account — every
piece of infrastructure this demo touches lives on your machine and is torn
down by `task down`.

## 1. See what's included

```console
$ task --list-all
```

Six `includes:` lines in [Taskfile.yaml](Taskfile.yaml) — `go`, `release`,
`runtime/kind`, `k8s`, `security`, `cosign` — and every task below belongs to
one of them, plus a handful of tasks this demo owns itself (`up`, `deploy`,
`scan`, `sign`, `cluster:*`, `registry:*`) to stand up local infrastructure a
real consumer usually already has.

## 2. Test and lint the Go code

```console
$ task verify
```

Runs `go:test`, `go:lint`, `go:vuln` — the same three tasks any Go module
included this library gets, unmodified.

## 3. Scan it — expect a finding

```console
$ task scan
```

`gitleaks` scans this repository's whole git history — since this demo
lives inside the library's own repository rather than one of its own, that
means the library's history, not just this directory's. A copy of this demo
in its own repository would see only its own commits instead.

`gitleaks` and the vulnerability half of `trivy` are clean. Its
*configuration* half is not — read [Dockerfile](Dockerfile):

```
Dockerfile (dockerfile)
DS-0002 (HIGH): Specify at least 1 USER command in Dockerfile with non-root user as argument
DS-0026 (LOW): Add HEALTHCHECK instruction in your Dockerfile
```

This does not fail the task. `security:trivy`'s config scan is deliberately
report-only — the [security module's own
README](../security/README.md) explains why: blocking on every
misconfiguration would turn away every release for something as ordinary as
a missing `HEALTHCHECK`. It is a triage list, and DS-0002 is the one worth
acting on: the image runs as root.

(You will also see one `KSV-0125` on the chart itself — "image from an
untrusted registry." That one stays: `localhost:5050` is this demo's own
throwaway registry, and trivy is right to not know that as trusted.
`hadolint` finds nothing at all here — a missing `USER` is not a linting
concern, it is a security-policy one, which is exactly why `trivy config`
and `hadolint` are two different tasks in `security:all` rather than one.)

## 4. Fix it

Add three lines to [Dockerfile](Dockerfile):

```diff
 FROM alpine:3.24
+RUN adduser -D -u 65532 nonroot
 COPY --from=build /out/taskfiles-demo /usr/local/bin/taskfiles-demo
 ARG APP_VERSION=dev
 ARG GIT_COMMIT_HASH=unknown
 ARG BUILD_TIME=unknown
 ENV APP_VERSION=${APP_VERSION} \
     GIT_COMMIT_HASH=${GIT_COMMIT_HASH} \
     BUILD_TIME=${BUILD_TIME}
+USER 65532
 EXPOSE 8080
+HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
 ENTRYPOINT ["/usr/local/bin/taskfiles-demo"]
```

`USER 65532`, not `USER nonroot`: hadolint's own DL3066 note is right that a
name is not guaranteed resolvable on every host, and 65532 is the same UID
[deploy/chart/templates/deployment.yaml](deploy/chart/templates/deployment.yaml)
already declares in `securityContext.runAsUser`.

Notice that word *already*: the pod runs as 65532 even before this fix,
because an explicit `runAsUser` makes Kubernetes set that UID directly
rather than asking the image what its default is — `runAsNonRoot` never
actually inspects the image here, it would only matter for an image with no
`runAsUser` override at all. So the chart's own hardening was quietly doing
the Dockerfile's job for it the whole time you were reading the finding.

That is the case *for* fixing it, not against: the moment this image runs
anywhere without that specific chart's `securityContext` — a plain `docker
run`, a different cluster, someone's local debugging compose file — it is
root again, because nothing in the image itself says otherwise. The fix
moves the guarantee from "whichever orchestrator happens to override it" to
the image, where it holds regardless of what runs it.

Run `task scan` again: `trivy clean`. Then commit it:

```console
$ git add Dockerfile && git commit -m "fix: run the container as a non-root user"
```

Not optional busywork: [release's own versioning
scheme](../release/README.md) stamps a dirty tree with the wall-clock time,
which changes on every single invocation. Leave this uncommitted and `task
deploy` and `task sign` — two separate commands below — would each derive a
*different* version and sign an image neither of them actually built.
Committing is what makes the version `release` computes the same answer
twice.

## 5. Bring up local infrastructure

```console
$ task up
```

Creates a [kind](https://kind.sigs.k8s.io) cluster and helm-installs
[deploy/registry](deploy/registry) — a bare `registry:2` — *inside* it, then
checks that it answers. `localhost:5050` stays live for the rest of the
walkthrough without anything left running: `kind`'s `extraPortMappings` (see
[deploy/kind-config.yaml](deploy/kind-config.yaml)) map the host port
straight to a `NodePort` Service on the cluster, the same way a bare-metal
cluster exposes one in production. An earlier version of this demo used
`kubectl port-forward` instead — it works fine for a single curl and then
falls over under a real registry client's chunked upload, which is worth
knowing if you reach for it elsewhere.

Port 5050, not the library's default 5000: macOS's AirPlay Receiver and
OrbStack's own proxy both already answer on 5000 on plenty of machines, and
the failure mode is a registry that looks reachable and answers every
request with the wrong service's 404 — a confusing thing to debug on a first
run. [Taskfile.yaml](Taskfile.yaml) sets `REGISTRY` explicitly for exactly
this reason.

This is the one piece of this demo that is not a library task: `release`
and `cosign` push to whatever `REGISTRY` you tell them, and something has to
answer there. A real consumer either already has a registry or runs one of
`runtime/docker` / `runtime/orbstack`, which need no registry at all because
the image never leaves the local Docker daemon. This demo uses
`runtime/kind` specifically *because* kind's nodes do not share that daemon,
which is what makes a registry worth demonstrating.

## 6. Build, push, deploy

```console
$ task deploy
```

`release:deploy` derives the version from git, builds the image, pushes it
and the chart to `localhost:5050`; `local:image:load` and `local:install`
then get it onto the kind cluster from there. Check it landed:

```console
$ task k8s:status
```

Then, in a second terminal:

```console
$ task k8s:port-forward
```

and from a third:

```console
$ curl localhost:8080/quote
```

Run `task deploy` again on an unchanged tree — the image build and chart
push both skip, because the version they would publish is already there.
That is `release`'s idempotency, not something this demo added.

## 7. Sign it

```console
$ task sign
```

`cosign:keygen` writes a local key pair once; `cosign:all` signs the image
and the chart and attests an SBOM; `cosign:verify` checks all three
signatures against the public key. No transparency log, no OIDC — the
[cosign module's README](../cosign/README.md) explains why that is the
right default for a registry only your own cluster can reach.

## Try the family swap

Nothing above is specific to `kind`. Change one line in
[Taskfile.yaml](Taskfile.yaml):

```yaml
local: { taskfile: '{{printf .TASKLIB "runtime/orbstack"}}', dir: . }
```

and `task deploy` targets OrbStack instead — same task names, same
behavior, no registry required at all since OrbStack shares the daemon
`release:image:build` writes to. `runtime/docker`, `runtime/minikube` and
`runtime/k3d` are the same swap. This is the promise `check:surface`
enforces in the library's own `task lint`: a family's variants are
interchangeable, not just similarly named.

## Clean up

```console
$ task down
```

Deletes the kind cluster and everything running on it — the registry, the
deployed service, all of it. Nothing this demo does touches anything
outside that one cluster and your local Docker image store.
