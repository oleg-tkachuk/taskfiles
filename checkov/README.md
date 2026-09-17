# checkov — policy scanning for infrastructure

Manifests, charts, Dockerfiles and workflows, checked against a baseline of
findings already accepted.

```yaml
includes:
  checkov: { taskfile: '{{printf .TASKLIB "checkov"}}', dir: . }
```

## Tasks

| Task | What it does |
|---|---|
| `scan` | Policy-scan against the baseline — the CI gate |
| `triage` | Every finding, baselined ones included — a triage view, never a gate |
| `baseline` | Regenerate the baseline, after deliberately fixing findings |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `CHECKOV_CONFIG` | `.checkov.yaml` | the config `scan` and `baseline` pass to checkov |
| `CHECKOV_BASELINE` | `.checkov.baseline` | findings already accepted; `scan` reports only what is new. Required to exist only when the config names a baseline — a config without one scans everything |
| `CHECKOV_VERSION` | — | the version to run, whatever is installed |
| `CHECKOV_VERSION_CMD` | — | a command printing one, for a version that already lives somewhere |
| `CHECKOV_FRAMEWORKS` | `github_actions dockerfile helm kubernetes` | frameworks the triage view walks |
| `CHECKOV_TARGET` | `.` | directory the triage view walks |
| `CHECKOV_FLAGS` | — | extra checkov flags, appended to every invocation |

## Examples

```yaml
includes:
  checkov:
    taskfile: '{{printf .TASKLIB "checkov"}}'
    dir: .
    vars:
      CHECKOV_FRAMEWORKS: terraform kubernetes helm
```

```console
$ task checkov:scan
✔ checkov · no findings outside the baseline

$ task checkov:triage       # everything, baselined findings included
$ task checkov:baseline     # after fixing some, accept what is left
```

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
◉ checkov · baselined findings: 41 → 38
```

A number that went up is reported as a warning: something new was accepted
rather than fixed.

## The baseline replaces, it does not merge

`baseline` regenerates the file from the current scan, so every record the
current scan does not reproduce is gone — and the scan reproduces only what its
config and framework list reach *today*. A repository whose `.checkov.yaml` has
narrowed since the baseline was written loses the rest of it here.

The count was always printed. It was printed the same way either direction, so
`177 → 5` read like `12 → 5`:

```console
◉ checkov · baselined findings: 177 → 5
▲ checkov · the baseline LOST most of itself — 177 accepted findings became 5, 172 gone.
         Findings the current scan cannot see are not in the new file. If the
         config or the framework list has narrowed since it was written, those
         records were decisions, not noise: git diff .checkov.baseline before
         committing, and git checkout -- .checkov.baseline to put them back.
```

It takes most of the file **and** at least twenty records to fire. Either test
alone misfires: proportional alone flags `12 → 5`, which is somebody fixing
seven findings and is what the task is for; absolute alone flags a large
baseline losing a fifth of itself, which is a good day's work.

To add a finding without risking the rest, edit the file — it is a list of
`{file, findings:[{resource, check_ids}]}` and appending one entry is a
reviewable diff. Regenerate when the baseline is genuinely meant to be whatever
the scan now says.

---

Part of [taskfiles](../README.md).

## Pinning the version

The rules a scan asserts against change between checkov releases, so a local
run on a different version from the pipeline's is a red result nobody else can
reproduce, or a green one that means nothing. Name a version and every task
here runs that one:

```yaml
includes:
  checkov:
    taskfile: '{{printf .TASKLIB "checkov"}}'
    dir: .
    vars:
      CHECKOV_VERSION: 3.3.18
```

It uses the checkov on `PATH` when that is already the right version, and
`pipx run checkov==<version>` otherwise — checkov is a Python tool, and that
is how one version is run without disturbing what else the machine has. It
says which it used. With no version named, nothing changes: whatever is on
`PATH`, and the install page when there is nothing there.

`CHECKOV_VERSION_CMD` is for a version that already lives somewhere — a
workflow's env, a `.tool-versions` — so that naming it here does not make a
second copy to keep in step:

```yaml
      CHECKOV_VERSION_CMD: awk -F'"' '/CHECKOV_VERSION:/ {print $2}' .github/workflows/ci.yaml
```

It runs inside the task rather than at parse time, so `task --list` reads no
files and a machine missing the source is a failure of the task that needed
it, not of every task.
