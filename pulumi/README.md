# pulumi — one project, the stack named every time

Preview, update, refresh and destroy one Pulumi project, and read its
outputs. Two things are held to on every call: the stack is named, never taken
from the workspace, and a change is shown before it is made.

```yaml
includes:
  pulumi:
    taskfile: '{{printf .TASKLIB "pulumi"}}'
    dir: .
    vars: { PULUMI_DIR: infra }
```

```console
$ task pulumi:plan STACK=dev
```

`dir: .` is required: it pins the module's commands to the including
component's directory. Tasks then read `pulumi:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `plan` | Preview the update of `STACK`; changes nothing |
| `apply` | Show the preview, ask, then update `STACK` |
| `destroy:plan` | Preview the destruction of `STACK`; changes nothing |
| `destroy` | Show that preview, ask, then destroy what `STACK` holds — needs `CONFIRM` |
| `unchanged` | Fail when an update of `STACK` would change anything; changes nothing |
| `refresh:plan` | Preview what a refresh of `STACK` would write to its state; changes nothing |
| `refresh` | Show that preview, ask, then bring the state of `STACK` in line with what exists |
| `output` | Print one output of `STACK`, and nothing else |

## Inputs

At the include's own `vars:` — see
[Variable scoping](../README.md#variable-scoping) — or on a `task:` call, as
[One include, several projects](#one-include-several-projects) shows:

| Var | Default | Meaning |
|---|---|---|
| `PULUMI_DIR` | `.` | The project's directory, the one holding `Pulumi.yaml` |
| `PULUMI_PLAN_FLAGS` | `--diff` | Flags for every preview of an update |
| `PULUMI_UP_FLAGS` | — | Extra flags for the update: `--refresh --run-program` |
| `PULUMI_DESTROY_FLAGS` | — | Extra flags for a destruction and its preview alike: `--ignore-protect`, an `--exclude` |
| `PULUMI_REFRESH_FLAGS` | `--diff` | Flags for a refresh and its preview alike: `--run-program` |
| `PULUMI_ENV` | — | `NAME=value` words, separated by spaces: [environment for the CLI of one call](#environment-for-one-call) |

On the call itself:

| Var | Meaning |
|---|---|
| `STACK` | Required by every task: the stack to act on |
| `TARGETS` | Whole URNs, separated by spaces, to narrow the call to |
| `CONFIRM` | Required by `destroy`: the stack's name again |
| `OUTPUT` | Required by `output`: the name of the output to print |
| `SHOW_SECRETS` | `1` for `output` to print a secret in plaintext; `0`, the default, leaves it masked |

## What stays with the repository

Logging in and the backend, the passphrase or access token, and creating the
stack: this module runs the CLI in the environment it is given, and a stack
that does not exist is the CLI's own error.

So is the order of several projects. A call acts on one project; a repository
with layers calls these tasks from a loop it owns, in the order it knows and
the reverse of it to destroy.

## One include, several projects

`PULUMI_DIR`, the four `*_FLAGS` inputs and `PULUMI_ENV` are read on every call. A value in
the `vars:` of a `task:` call wins over the include's, for that call and the
preview it shows first:

```yaml
includes:
  pulumi: { taskfile: '{{printf .TASKLIB "pulumi"}}', dir: . }

tasks:
  plan:
    desc: "Preview one layer (task plan LAYER=10-network STACK=dev)"
    requires: { vars: [LAYER, STACK] }
    cmds:
      - task: pulumi:plan
        vars: { STACK: "{{.STACK}}", PULUMI_DIR: "layers/{{.LAYER}}" }
```

The order, most specific first: the call's value when it is not empty, the
include's, the default. An empty value on the call turns nothing off — it
falls back, as [an empty value does everywhere](../README.md#an-empty-value-turns-nothing-off).

This is the `vars:` of a `task:` call, not the command line. `task
pulumi:plan PULUMI_DIR=…` reaches the module only when the include sets no
`PULUMI_DIR` of its own: Task ranks an include's `vars:` above the command
line. A repository that includes the module once per project is not affected
by any of this, and needs none of it.

## Environment for one call

A Pulumi program and its providers take some of their settings from the
environment, and some of those belong to one run only: a variable that tells
the program this is a teardown must not be set when it is updated. A task's
`env:` does not follow a `task:` call, so `PULUMI_ENV` carries them:

```yaml
tasks:
  destroy:
    requires: { vars: [LAYER, STACK, CONFIRM] }
    cmds:
      - task: pulumi:destroy
        vars:
          STACK: "{{.STACK}}"
          CONFIRM: "{{.CONFIRM}}"
          PULUMI_DIR: "layers/{{.LAYER}}"
          PULUMI_ENV: "EXAMPLE_TEARDOWN=1 HELM_REPOSITORY_CACHE=.cache/helm"
```

Each word is `NAME=value` and is exported to the CLI of that call — the
change and the preview shown before it — and to nothing else: not to the
next call, and not to any other command. Words are separated by spaces, so a
value holds none; anything else in a value is data, and an `=` after the
first is part of it. A word that is not `NAME=value` is refused before
anything runs.

At the include it is every call's. A call's own replaces the include's
whole — the two are not merged — and an empty one falls back to it.

No value is printed: the module says which word it refused by its place in
the list, and holds the list in a `secret: true` var, so `task --verbose` and
`task --dry` print `*****` for it. The name *you* pass it under is yours to
mark the same way — see [Secrets are marked](../README.md#secrets-are-marked):
`task --summary` lists a call's vars under their own names, and one typed on
the command line cannot be marked at all. Keep a credential in a var of your
own that is.

This is an input of this module alone, not a convention of the library.
Everywhere else a per-run setting is a flag, and
[every tool invocation takes flags](../README.md#every-tool-invocation-takes-flags);
here the thing being configured is the consumer's own program, which the CLI
has no flag for.

### Without it: a child process

A task's `env:` does reach a command, and a command can be Task itself. That
needs nothing from this module, and works with any module here:

```yaml
includes:
  pulumi: { taskfile: '{{printf .TASKLIB "pulumi"}}', dir: . }

tasks:
  plan:
    requires: { vars: [LAYER, STACK] }
    env: { HELM_REPOSITORY_CACHE: .cache/helm }
    cmds:
      - task pulumi:plan STACK={{.STACK | q}} PULUMI_DIR={{printf "layers/%s" .LAYER | q}}
```

The include must set no `PULUMI_DIR` of its own for that, since an include's
value outranks the command line. The child is a second Task process: it asks
its own question for `apply`, and a `--yes` given to the parent has to be
passed on to it.

## The stack is always named

The CLI's "current stack" is a file in the workspace, set by whoever last ran
`pulumi stack select` there. Every call here passes `--stack`, and a call
with no `STACK` is refused rather than left to that file. `--non-interactive`
goes on every call too: nothing here waits on a terminal that a pipeline does
not have.

## Shown, then asked

Task runs a task's dependencies and then asks its prompt, so `apply` previews
first and the question arrives with the changes on screen; `destroy` and
`refresh` do the same with their own previews.

There is no saved plan behind that. The CLI's plan files are a preview
feature, and one constrains a second run of the program rather than replaying
the first. What is approved here is what was just shown, and the update
computes it again: a change made between the preview and the answer is not
caught. Run `plan` yourself first when that matters, and keep the gap short.

Under `--yes` no question is asked, which is why `destroy` also needs
`CONFIRM` to repeat the stack: a second word that has to agree is what stands
between a wrong `STACK` and its loss.

## Targets are whole URNs

A pattern that matches nothing is not an error to the CLI:
`pulumi preview --target '**::Release::no-such'` reports no changes and exits
0, so a typo reads as "nothing to do". `TARGETS` therefore takes whole URNs
and refuses a pattern. Turning a name into the URNs it means — and failing on
one that means none — is done before the call, by the repository.

Destroy flags get no such check. An `--exclude` in `PULUMI_DESTROY_FLAGS` that
matches nothing is silent as well, and the preview `destroy` shows is where
that is caught.

## Unchanged

`unchanged` reads the preview's exit code, and only "no changes" passes. A
preview that errored — a program that would not run, a stack that is not
there — fails as an error, never as a clean result and never as a change.
That needs the CLI's distinct exit codes, which it has had since 3.227.0.

It answers "would an update change anything". Whether that includes changes
made behind the state depends on the flags: add `--refresh` to
`PULUMI_PLAN_FLAGS` for it. A change in the stack's outputs alone is not one
the CLI counts.

## Refresh

A refresh changes no infrastructure and does change the state: a resource
that is gone, or that its provider could not reach, leaves it, and the next
update creates it again. So `refresh` is shown and asked about like an update,
and `refresh:plan` is the same preview by itself — what the state no longer
matches, for one stack, with nothing written.

## Outputs

```console
$ url=$(task pulumi:output STACK=dev OUTPUT=url)
```

`output` prints the value and nothing else, so it can be captured. It takes
one name: every output at once is where a secret gets printed by somebody who
asked for something else. A secret output prints as `[secret]` unless
`SHOW_SECRETS=1` is passed on that call.
