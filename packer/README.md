# packer — one template, and every build named for real

The gates of one Packer template — formatting and validity — and building it
only once it is valid, with every name in `ONLY` and `EXCEPT` held to
something the template has.

```yaml
includes:
  packer:
    taskfile: '{{printf .TASKLIB "packer"}}'
    dir: .
    vars: { PACKER_DIR: images }
```

```console
$ task packer:init
$ task packer:validate
$ task packer:build ONLY=base.amazon-ebs.web
```

`dir: .` is required: it pins the module's commands to the including
component's directory. Tasks then read `packer:<task>`.

One include is one template: one directory of `.pkr.hcl` files. A repository
with several includes this once per template.

## Tasks

| Task | What it does |
|---|---|
| `init` | Install the plugins the template requires |
| `fmt` | Fail when a file under `PACKER_DIR` is not in the canonical format |
| `inspect` | Show the variables and builds of the template; changes nothing |
| `validate` | Validate the template, or the builds `ONLY` and `EXCEPT` leave; changes nothing |
| `build` | Validate, ask, then build the template, or the builds `ONLY` and `EXCEPT` leave |

## Inputs

At the include's own `vars:` — see
[Variable scoping](../README.md#variable-scoping):

| Var | Default | Meaning |
|---|---|---|
| `PACKER_DIR` | `.` | The template's directory |
| `PACKER_VAR_FLAGS` | — | Flags for reading the template, in `validate` and `build` alike: a `-var`, a `-var-file` |
| `PACKER_BUILD_FLAGS` | — | Extra flags for the build: `-force`, `-parallel-builds=1` |
| `PACKER_INIT_FLAGS` | — | Extra flags for `init`: `-upgrade` |

On the call itself:

| Var | Meaning |
|---|---|
| `ONLY` | Build names, separated by spaces, to narrow `validate` and `build` to. Each has to match a build |
| `EXCEPT` | Names of builds and post-processors, separated by spaces, to leave out of `validate` and `build`. Each has to match one |

Every task runs the CLI in `PACKER_DIR`, with `.` for the template: its own
relative paths — a `file()` it reads, a `-var-file` in `PACKER_VAR_FLAGS`, a
builder's output directory — resolve from where it lives.

## What stays with the environment

The credentials of whatever the template builds on, where plugins are kept
(`PACKER_PLUGIN_PATH`), and variables given as `PKR_VAR_<name>`. This module
runs the CLI in the environment it is given: the caller's, or the `env:` at
the top of the including Taskfile. An `env:` on a task that calls these does
not reach them.

So is installing plugins before anything else: `validate` and `build` fail on
a template whose plugins are missing, and the CLI says to run `init`.

## Formatting and validity

`fmt` checks every `.pkr.hcl` and `.pkrvars.hcl` file under `PACKER_DIR` and
rewrites none. The CLI has an exit code of its own for a file that is not
formatted, so that is told from a file it could not read.

`validate` checks the configuration of every builder, provisioner and
post-processor, and for that needs the template's plugins and its variables:
`PACKER_VAR_FLAGS` reach it as they reach the build. It does not evaluate data
sources — the CLI leaves them out unless asked, since reading one may cost.

A directory with no template fails, and so does a template with no build: the
CLI refuses both itself.

## Every name in ONLY and EXCEPT is there

A build's name is `<type>.<name>` of its source — `amazon-ebs.web` — and
`<build>.<type>.<name>` where the `build` block has a name of its own. A name
may be a pattern: `base.*`.

A name that matches no build is not an error to the CLI. It warns, builds the
names that do match, and exits 0: a mistyped name is an image nobody built,
in a run that passed. Asked to validate, it reports a valid template having
checked no build at all.

`EXCEPT` fails the other way. A name there that matches nothing leaves
nothing out: the build it was meant to skip is built, and the CLI exits 0. It
takes the names of post-processors as well as builds, and matches a build
only among those `ONLY` has left — a build `ONLY` already leaves out is, to
`EXCEPT`, a name that matches nothing.

`validate` reads the CLI's output for either warning and refuses the input,
and `build` validates first. The warnings are sentences and nothing else — no
exit code, nothing more in `-machine-readable` — so `validate` also asks the
CLI about a name nothing has, and refuses `ONLY` or `EXCEPT` altogether on a
CLI that does not give the warning there, showing what it said instead.
Without an `ONLY` or an `EXCEPT` nothing more is asked.

This holds for `ONLY` and `EXCEPT`. An `-only` or an `-except` put in
`PACKER_BUILD_FLAGS` is passed as written: nothing checks it.

## Validated, asked, then built

`build` validates the template with the same variables, `ONLY` and `EXCEPT`,
then asks, then builds. Nothing is saved in between: the build reads the
template again, and Packer has no preview of what a build will create.

Builds run side by side, and one that fails does not undo the others. The CLI
exits 1 for the lot, and the builds that finished keep their artifacts.

What a build does about an artifact already there is its builder's own: some
replace it, some refuse until `-force` is among `PACKER_BUILD_FLAGS`.
