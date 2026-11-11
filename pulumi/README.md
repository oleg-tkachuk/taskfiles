# pulumi — one project, the stack named every time

Preview, update and destroy one Pulumi project. Two things are held to on
every call: the stack is named, never taken from the workspace, and a change
is shown before it is made.

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

## Inputs

At the include's own `vars:` — see
[Variable scoping](../README.md#variable-scoping):

| Var | Default | Meaning |
|---|---|---|
| `PULUMI_DIR` | `.` | The project's directory, the one holding `Pulumi.yaml` |
| `PULUMI_PLAN_FLAGS` | `--diff` | Flags for every preview of an update |
| `PULUMI_UP_FLAGS` | — | Extra flags for the update: `--refresh --run-program` |
| `PULUMI_DESTROY_FLAGS` | — | Extra flags for a destruction and its preview alike: `--ignore-protect`, an `--exclude` |

On the call itself:

| Var | Meaning |
|---|---|
| `STACK` | Required by every task: the stack to act on |
| `TARGETS` | Whole URNs, separated by spaces, to narrow the call to |
| `CONFIRM` | Required by `destroy`: the stack's name again |

## What stays with the repository

Logging in and the backend, the passphrase or access token, and creating the
stack: this module runs the CLI in the environment it is given, and a stack
that does not exist is the CLI's own error.

So is the order of several projects. One include is one project; a repository
with layers includes the module once per layer, or calls these tasks from a
loop it owns, in the order it knows and the reverse of it to destroy.

## The stack is always named

The CLI's "current stack" is a file in the workspace, set by whoever last ran
`pulumi stack select` there. Every call here passes `--stack`, and a call
with no `STACK` is refused rather than left to that file. `--non-interactive`
goes on every call too: nothing here waits on a terminal that a pipeline does
not have.

## Shown, then asked

Task runs a task's dependencies and then asks its prompt, so `apply` previews
first and the question arrives with the changes on screen; `destroy` does the
same with the destruction's preview.

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
