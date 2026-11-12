# nomad — job files, and a cluster named every time

The gates of a directory of Nomad job files — formatting and validity — and
changing a cluster only by submitting a plan that was saved and read first, or
by stopping a job named twice.

```yaml
includes:
  nomad:
    taskfile: '{{printf .TASKLIB "nomad"}}'
    dir: .
    vars: { NOMAD_DIR: jobs }
```

```console
$ task nomad:validate
$ task nomad:plan FILE=web.nomad.hcl
$ task nomad:apply FILE=web.nomad.hcl
```

`dir: .` is required: it pins the module's commands to the including
component's directory. Tasks then read `nomad:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `fmt` | Fail when a file under `NOMAD_DIR` is not in the canonical format |
| `validate` | Validate `FILE`, or every job file under `NOMAD_DIR`; needs no cluster |
| `plan` | Plan `FILE` against the cluster and save the plan for `apply`; changes nothing |
| `apply` | Ask, then submit the plan that `plan` saved for `FILE`, and nothing else |
| `stop:plan` | Show the job that `stop` would stop; changes nothing |
| `stop` | Show the job, ask, then stop `JOB` — needs `CONFIRM` |

## Inputs

At the include's own `vars:` — see
[Variable scoping](../README.md#variable-scoping):

| Var | Default | Meaning |
|---|---|---|
| `NOMAD_DIR` | `.` | The directory holding the job files |
| `NOMAD_JOB_FLAGS` | — | Flags for reading a job file, in `validate` and `plan` alike: a `-var`, a `-var-file` |
| `NOMAD_RUN_FLAGS` | — | Extra flags for the submission: `-detach` |
| `NOMAD_STOP_FLAGS` | — | Extra flags for a stop: `-purge`, `-detach` |
| `NOMAD_PLAN_DIR` | `.nomad-plan` | Where `plan` saves and `apply` reads, relative to `NOMAD_DIR` |

On the call itself:

| Var | Meaning |
|---|---|
| `FILE` | A job file, relative to `NOMAD_DIR`. Required by `plan` and `apply`; `validate` takes every job file without one |
| `JOB` | Required by `stop` and `stop:plan`: the job's ID, whole |
| `CONFIRM` | Required by `stop`: the job's ID again |

Every task runs the CLI in `NOMAD_DIR`: it has no flag for a working
directory, and a job file's own relative paths — a `file()` it reads, a
`-var-file` in `NOMAD_JOB_FLAGS` — resolve from where it runs.

## What stays with the environment

The address, the namespace, the region and the token: `NOMAD_ADDR`,
`NOMAD_NAMESPACE`, `NOMAD_REGION`, `NOMAD_TOKEN`, and the TLS variables beside
them. This module runs the CLI in the environment it is given: the caller's,
or the `env:` at the top of the including Taskfile. An `env:` on a task that
calls these does not reach them.

So is the order of several jobs. One call is one job; a repository whose jobs
depend on each other calls these tasks in the order it knows.

## The cluster is always named

With no `NOMAD_ADDR` the CLI talks to `http://127.0.0.1:4646` — whatever
answers there: a development agent, a tunnel left open to production. `plan`,
`apply`, `stop:plan` and `stop` are refused without one rather than left to
that default.

`validate` is the exception, and the reason it works as a gate in a pipeline
with no cluster: the CLI asks an agent to validate the job when it finds one,
and otherwise validates the job itself and says that driver configuration
went unchecked. Set `NOMAD_ADDR` for the fuller check.

## Formatting and validity

`fmt` checks every `.nomad`, `.nomad.hcl` and `.hcl` file under `NOMAD_DIR`
and rewrites none. The CLI has one exit code for a file that is not formatted
and a file that does not parse; it lists the first and prints an error for the
second.

`validate` takes the job files only — a name ending `.nomad.hcl` or `.nomad` —
since a variables file is HCL and is not a job. Every file is validated before
any failure is reported, and a directory with no job file fails: a check that
covers nothing would pass.

The CLI refuses a `-var` the job does not declare, so `NOMAD_JOB_FLAGS` suit a
directory whose jobs share their variables. Where they do not, give each group
of jobs an include of its own, or add `-hcl2-strict=false`.

## Planned, saved, then submitted

`plan` renders the job once — variables resolved, files read — and that
rendering is what is planned, saved and later submitted. `apply` reads no job
file: a variable or a file that changes after the plan does not reach the
cluster unread.

The plan also records the job's modify index, and `apply` submits with
`-check-index`: the server refuses the job once anything else has changed it.
The plan carries the address, namespace and region it was made against, and
`apply` refuses any other — an index means nothing on another cluster.
Submitted or refused, the plan is spent and removed.

A plan that did not complete saves nothing, and removes the plan before it.
The CLI's exit code tells a plan that failed from one that completed, and no
more than that: 0 is "no allocation created or destroyed", which an update in
place is too. So there is no task here that reads "unchanged" off a plan.

Saved plans live in `NOMAD_PLAN_DIR`, with a `.gitignore` of their own: a
rendered job holds every variable's value, secrets among them.

What the server keeps as the job's source is that rendering, as JSON, where a
submission of the file itself would have kept the HCL.

Multi-region jobs are not supported: the CLI documents that a plan of one
returns no modify index, and nothing here has been run against one.

## A stop names its job whole

The CLI takes a prefix wherever it takes a job's ID, and acts on the one job
the prefix matches: `nomad job stop web` stops `web-frontend` where there is
no `web`. `stop` and `stop:plan` ask the cluster for the ID first and refuse a
`JOB` that is only the start of one.

`stop` then shows the job, and asks. Under `--yes` no question is asked, which
is why it also needs `CONFIRM` to repeat the job: a second word that has to
agree is what stands between a wrong `JOB` and its allocations.
