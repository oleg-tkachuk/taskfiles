# terraform — the gates of a configuration

Four checks a Terraform or OpenTofu configuration should pass before anything
is applied, and the task that writes its dependency lock. Nothing here changes
infrastructure or state: `lock` writes the lock file, every other task only
reads.

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

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `TERRAFORM_DIR` | `.` | The root module's directory |
| `TERRAFORM_BIN` | `terraform` | The CLI to run — `terraform`, or `tofu` for OpenTofu |
| `TERRAFORM_PLATFORMS` | `["linux_amd64", "darwin_arm64"]` | List of platforms the lock file must hold checksums for |
| `TERRAFORM_PLAN_FLAGS` | — | Extra flags for the plan `drift` makes: a `-var-file`, a `-target` |

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
