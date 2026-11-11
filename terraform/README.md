# terraform — gates, and changes only through a saved plan

Four checks a Terraform or OpenTofu configuration should pass before anything
is applied, the task that writes its dependency lock, and the three that
change infrastructure. `apply` and `destroy` never use `-auto-approve`: each
applies a plan file. `lock` writes the lock file; every other task only reads.

```yaml
includes:
  terraform:
    taskfile: '{{printf .TASKLIB "terraform"}}'
    dir: .
    vars: { TERRAFORM_DIR: infra }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. Tasks then read `terraform:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `fmt` | Fail when a file under `TERRAFORM_DIR` is not in the canonical format; rewrites nothing |
| `validate` | Install the providers the lock file names, without the backend, and validate the configuration |
| `lock` | Write the dependency lock file with checksums for every `TERRAFORM_PLATFORMS` entry |
| `lock:check` | Fail when the lock file is absent, not tracked by git, or lacks a platform's checksums |
| `drift` | Plan against the real backend and fail when the infrastructure differs from the configuration |
| `plan` | Plan the changes and save the plan for `apply`; changes nothing |
| `apply` | Apply the plan `plan` saved, and nothing else — asks first |
| `destroy:plan` | Plan the destruction of everything `TERRAFORM_DIR` manages and save it for `destroy`; changes nothing |
| `destroy` | Apply the destruction `destroy:plan` saved, and nothing else — needs `CONFIRM`, asks first |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `TERRAFORM_DIR` | `.` | The root module's directory |
| `TERRAFORM_BIN` | `terraform` | The CLI to run — `terraform`, or `tofu` for OpenTofu |
| `TERRAFORM_PLATFORMS` | `["linux_amd64", "darwin_arm64"]` | List of platforms the lock file must hold checksums for |
| `TERRAFORM_PLAN_FLAGS` | — | Extra flags for every plan made here: a `-var-file`, a `-target` |
| `TERRAFORM_PLAN_FILE` | `.terraform/tfplan` | Where `plan` saves and `apply` reads, relative to `TERRAFORM_DIR`; `destroy:plan` and `destroy` use the same name with `.destroy` appended |
| `CONFIRM` | — | Required by `destroy`: `<TERRAFORM_DIR>:<workspace>` |

Pass them at the include's own `vars:` — see
[Variable scoping](../README.md#variable-scoping).

## The CLI's version

There is no version input. `required_version` in the configuration already
refuses a CLI outside it, on every command, so the pin lives there and nowhere
else:

```hcl
terraform {
  required_version = "~> 1.17"
}
```

## The lock file

A lock written on a laptop holds that platform's checksums, and the first
`init` on another one — the pipeline's, usually — refuses it. `lock` asks for
every platform in `TERRAFORM_PLATFORMS` at once, and `lock:check` fails a lock
that would not survive that.

The check asks the CLI rather than reading the file: `providers lock` leaves a
complete lock byte for byte as it was and rewrites an incomplete one. Whatever
it did, the file is put back, so the check changes nothing. It needs the
registry, as `init` does.

`validate` and `drift` run `init` with `-lockfile=readonly`: a lock behind the
configuration is a failure that names itself, never a silent rewrite.

## Drift

`drift` reads the plan's detailed exit code, and only "no changes" passes. A
plan that errored — credentials, a provider that would not start, a state that
would not lock — has proved nothing, so it fails as *unknown*, not as clean
and not as drift.

It initialises the real backend, so it needs the credentials a plan needs, and
it takes the state lock a plan takes.

## Plan, then apply

```console
$ task terraform:plan     # saves the plan and shows it
$ task terraform:apply    # applies that file
```

What `apply` runs is the file `plan` wrote, so what was read is what happens.
There is no plan made at apply time and no `-auto-approve`. The CLI itself
refuses a saved plan the state has moved past, and `apply` removes the file
once it has been tried — applied or refused, it is spent. A `plan` that fails
removes the previous one, so an older plan is never applied as the new one.

A plan file holds every value it will write, secrets included. The default
location is the CLI's own `.terraform/` directory, which is not committed;
keep a `TERRAFORM_PLAN_FILE` of your own out of the repository too. To plan
in one pipeline job and apply in another, pass that file between them.

## Destroy

```console
$ task terraform:destroy:plan                    # saves the destruction and shows it
$ task terraform:destroy CONFIRM=infra:default   # applies that file
```

The same two steps, for the same reason: `destroy` makes no plan of its own,
so the list of what goes is on screen before the question is asked, not after
it is answered. The destruction is saved under a name of its own —
`apply` never picks it up, and `destroy` never runs a plan made for `apply`.

`CONFIRM` must name the directory and the workspace selected in it. The
prompt guards against not meaning it; `CONFIRM` guards against meaning it in
the wrong workspace, which is ambient state nobody re-reads before typing a
command.
