# security — the scans worth running before a release

govulncheck, golangci-lint, gitleaks, trivy and buf breaking. A missing binary
produces an install hint rather than a stack trace, but present-and-failing is
always fatal: a scan that can be silently skipped is a scan that does not exist.

```yaml
includes:
  sec: { taskfile: '{{.TASKLIB}}security?ref={{.TASKLIB_TAG}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `sec:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `all` | Run every scan: vulnerabilities, lint, secrets, filesystem, proto compatibility |
| `lint` | golangci-lint across every Go module, limited to issues new since main |
| `secrets` | gitleaks — committed credentials anywhere in the history |
| `trivy` | trivy — vulnerable dependencies and secrets (blocking) plus IaC misconfig (report-only) |
| `vuln` | govulncheck across every Go module — vulnerabilities the code actually reaches |
| `proto` | breaking:       buf breaking — refuse incompatible proto changes against main |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `GO_MODULES` | `.` | whitespace-separated module directories for the Go scans |
| `BASE` | `main` | branch the new-findings and breaking gates compare against |

## Examples

```yaml
includes:
  sec:
    taskfile: '{{.TASKLIB}}security?ref={{.TASKLIB_TAG}}'
    dir: .
    vars:
      GO_MODULES: "backend/api backend/worker"
      BASE: develop
```

```console
$ task sec:all           # vuln · lint · secrets · trivy
$ task sec:secrets       # gitleaks over the whole history
$ task sec:proto:breaking
```

## Why lint is new-findings-only

Whole-repo mode on a codebase with years of accumulated findings is a permanently
red gate that everyone learns to ignore. `--new-from-merge-base=$BASE` is a gate
that can actually stay green. The full audit is still one command away:
`golangci-lint run ./...`.

## trivy config is report-only

Misconfiguration findings are dense and noisy, and blocking on them would stop
every release for a Kubernetes default. Vulnerabilities and secrets block;
misconfiguration reports.

---

Part of [taskfiles](../README.md).
