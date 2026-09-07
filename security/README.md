# security — the scans worth running before a release

govulncheck, golangci-lint, gitleaks, trivy and buf breaking. A missing binary
produces an install hint rather than a stack trace, but present-and-failing is
always fatal: a scan that can be silently skipped is a scan that does not exist.

```yaml
includes:
  security: { taskfile: '{{printf .TASKLIB "security"}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `sec:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `all` | Run every scan: vulnerabilities, lint, secrets, SAST, filesystem |
| `lint` | golangci-lint across every Go module, limited to issues new since main |
| `gosec` | gosec — insecure patterns the compiler is happy with; part of `all` |
| `secrets` | gitleaks — committed credentials anywhere in the history |
| `trivy` | trivy — vulnerable dependencies and secrets (blocking) plus IaC misconfig (report-only) |
| `vuln` | govulncheck across every Go module — vulnerabilities the code actually reaches |
| `proto` | breaking:       buf breaking — refuse incompatible proto changes against main |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `GO_MODULES` | `.` | whitespace-separated module directories for the Go scans; one without a `go.mod` is skipped, not failed |
| `GOVULNCHECK_FLAGS` | — | extra govulncheck flags |
| `GOLANGCI_FLAGS` | — | extra golangci-lint flags |
| `GITLEAKS_FLAGS` | — | extra gitleaks flags |
| `TRIVY_SUBCOMMAND` | `fs` | `image` to scan a built image instead |
| `TRIVY_SCANNERS` | `--scanners vuln,secret` | which scanners run; `--scanners misconfig` for IaC |
| `TRIVY_TARGET` | `.` | what to scan |
| `TRIVY_FLAGS` | — | extra trivy flags |
| `BUF_BREAKING_FLAGS` | — | extra buf breaking flags |
| `GITLEAKS_BASELINE` | — | findings accepted as known, so the gate reports only new ones |
| `GOSEC_FLAGS` | — | extra gosec flags |
| `BASE` | `main` | branch the new-findings and breaking gates compare against |

Every tool takes a FLAGS input, appended rather than replacing the invocation:
the flags that make a task a gate — trivy's `--exit-code 1`, the base
golangci-lint measures against — stay where a consumer cannot drop them by
accident, and everything else is theirs to add.

## Examples

```yaml
includes:
  security:
    taskfile: '{{printf .TASKLIB "security"}}'
    dir: .
    vars:
      GO_MODULES: "backend/api backend/worker"
      BASE: develop
```

```console
$ task security:all           # vuln · lint · secrets · gosec · trivy
$ task security:secrets       # gitleaks over the whole history
$ task security:proto:breaking
```

## A repository with no Go still gets scanned

Three of the five scans read Go — `vuln`, `lint` and `gosec` — and two apply to
anything: `secrets` and `trivy`. `all` runs the agnostic pair first, then the
Go ones, and a directory in `GO_MODULES` without a `go.mod` is skipped with a
line saying so:

```
◉ sec · gitleaks
✔ sec · no secrets in history
◉ sec · trivy fs .
✔ sec · trivy clean
○ sec · govulncheck · . is not a Go module — skipped
○ sec · golangci-lint · . is not a Go module — skipped
○ sec · gosec · . is not a Go module — skipped
```

The rule is: **skip when there is nothing to scan, fail when there is
something to scan and the tool is missing.** So a Python repository does not
need govulncheck installed, while a Go repository that lacks it stops with an
install hint rather than passing quietly. The skip is printed rather than done
with `status:`, which is silent — a typo in `GO_MODULES` has to be visible, or
the scan it disables is one nobody notices is gone.

## Why lint is new-findings-only

Whole-repo mode on a codebase with years of accumulated findings is a permanently
red gate that everyone learns to ignore. `--new-from-merge-base=$BASE` is a gate
that can actually stay green. The full audit is still one command away:
`golangci-lint run ./...`.

## trivy config is report-only

Misconfiguration findings are dense and noisy, and blocking on them would stop
every release for a Kubernetes default. Vulnerabilities and secrets block;
misconfiguration reports.

Infrastructure policy scanning lives in [`checkov`](../checkov/README.md): it
asks a different question of a different tree, and a repository usually has one
or the other.

---

Part of [taskfiles](../README.md).
