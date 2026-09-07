# checkov — policy scanning for infrastructure

Manifests, charts, Dockerfiles and workflows, checked against a baseline of
findings already accepted.

```yaml
includes:
  checkov: { taskfile: '{{.TASKLIB}}checkov{{.TASKLIB_REF}}', dir: . }
```

## Tasks

| Task | What it does |
|---|---|
| `scan` | Policy-scan against the baseline — the CI gate |
| `all` | Every finding, baselined ones included — a triage view, never a gate |
| `baseline` | Regenerate the baseline, after deliberately fixing findings |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `CHECKOV_CONFIG` | `.checkov.yaml` | |
| `CHECKOV_BASELINE` | `.checkov.baseline` | |
| `CHECKOV_FRAMEWORKS` | `github_actions dockerfile helm kubernetes` | frameworks the triage view walks |
| `CHECKOV_TARGET` | `.` | directory the triage view walks |
| `CHECKOV_FLAGS` | — | extra checkov flags, appended to every invocation |

## Why this is not in `security`

`security` scans a repository's code and the artifacts built from it: every task
there wants Go modules or a git history. This one wants YAML a cluster will
apply. A repository usually has one or the other, and a module should not fill a
consumer's task list with work it has nothing to run against.

## Why the baseline is counted, not just written

`baseline` prints the number of accepted findings before and after. A baseline
regenerated to clear one fixed finding also swallows anything that broke since —
and the run that does that looks exactly like the run that does not, so the
count is the only thing that tells them apart.

```console
$ task checkov:baseline
▸ checkov · baselined findings: 41 → 38
```

A number that went up is reported as a warning: something new was accepted
rather than fixed.

---

Part of [taskfiles](../README.md).
