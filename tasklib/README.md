# tasklib — the pin on this library, and its lock

Moves the `?ref=` every Taskfile in a repository pins this library at, and the
lock Task keeps for each of them, in one step — and fails a repository where
the two have come apart.

```yaml
includes:
  tasklib: { taskfile: '{{printf .TASKLIB "tasklib"}}', dir: . }
```

Include it once, in the root Taskfile: it acts on every Taskfile below the
directory the include carries, so `dir: .` there is the whole repository.

## Tasks

| Task | What it does |
|---|---|
| `bump` | Pin every Taskfile to VERSION, then refresh every lock (VERSION=v15.0.0) |
| `check` | Fail when the Taskfiles pin different refs, one does not load from its lock, or a lock holds more or less than its pin names |
| `lock` | Download every Taskfile's remote includes again and replace its lock, dropping what no pin names |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `VERSION` | — | required by `bump`: the tag to pin |
| `TASKLIB_FILES` | every file git knows that is named like a Taskfile | list of the Taskfiles to act on |
| `TASKLIB_CACHE_DIR` | `.task` | what Task takes as `--remote-cache-dir`, relative to each Taskfile's directory |
| `TASKLIB_RETRIES` | `5` | attempts at one Taskfile's download |
| `TASKLIB_TIMEOUT` | `1m` | how long one download may take, as Task's `--timeout` takes it |

A Taskfile is `Taskfile.yaml`, `taskfile.yml` or one with a middle name —
`Taskfile.dev.yaml` — tracked or not, unless git ignores it. Each is loaded as
an entry point of its own, from its own directory; name them in
`TASKLIB_FILES` when one of them cannot load that way.

## Moving to a new version

```console
$ task tasklib:bump VERSION=v15.0.0
◉ start · tasklib · 3 Taskfile(s) pin v15.0.0
✔ ok    · tasklib · ./.task/remote locked
✔ ok    · tasklib · api/.task/remote locked
$ git add -A . && git commit -m 'build(tasks): bump taskfiles v14.3.2 → v15.0.0'
```

`bump` rewrites the ref of every include of this library and of nothing else,
then runs `lock`. A pin written in a YAML comment is an example, not a pin: it
is neither rewritten nor counted by `check`. Run it while the old pin still loads: once a ref has been
edited by hand, that Taskfile is not trusted and `task tasklib:bump` cannot
start. From there, the way back is the lock alone:

```bash
task --yes --offline=false --download tasklib:lock
```

`--yes` accepts what the new ref serves, for the root Taskfile and, inside
`lock`, for every other one. That is the decision the diff of `.task/remote/`
then records, so read it the way you would read a dependency bump.

## What `lock` does, and why one at a time

Task names each file under `.task/remote/` by a hash of the include's whole
URL. A new ref is a new URL, so a bump leaves every old file behind, and
nothing ever removes them. `lock` downloads each directory's includes into a
fresh directory and swaps it in once all of them have loaded: the old files go
without this module knowing how Task names one, and a download that fails
leaves the lock that was there.

It runs one Taskfile at a time. Task clones a ref into one cache per user, and
two clones of the same ref that start together fail on its git lock:

```
task: failed to clone repository
```

A fan-out over the components — or a second worktree, or two hook jobs — does
exactly that. A download that still loses to another process is tried again,
`TASKLIB_RETRIES` times. So is one that fails with nothing else running:
measured across eight repositories, the first attempt at a Taskfile with
several includes of this library failed for a quarter to a half of the
directories, and the second went through. Each attempt gets
`TASKLIB_TIMEOUT`, where Task's own ten seconds is less than a clone can take
on a busy machine.

The command that starts it all, `task --yes --offline=false --download
tasklib:lock`, has one step this module cannot guard: Task loads the root
Taskfile's own includes before any task runs, straight into `.task/remote/`
and with no second attempt. When that step fails, run the command again.

A directory whose Taskfiles have no remote include left loses its lock.

## A gate

`check` is for CI and for a pre-push hook. It refuses pins that disagree, and
names them:

```console
$ task tasklib:check
✖ fail  · tasklib · the Taskfiles pin different refs — task tasklib:bump VERSION=<tag> moves them together:
    v14.3.1	api/Taskfile.yaml
    v14.3.2	Taskfile.yaml
```

Then it loads every Taskfile with `--offline`, so a pin whose lock was never
refreshed, or never committed, fails here rather than for whoever runs it
next. It downloads nothing.

Last, the lock itself. Offline, Task reads a module's `.yaml` and never its
`.checksum`, so a lock can load and still be wrong. `check` refuses:

- a module with no `.checksum` beside it — online, Task would ask to trust it
  again, and with no terminal it fails;
- a module that is not what its `.checksum` records;
- a file no Taskfile in that directory reads, which is what an earlier ref
  leaves behind when the pin is moved by hand.

Which files are read is what Task itself reports under `--verbose`. Should a
later Task stop saying, `check` says that it could not tell, and passes.

## Renovate

Two presets ship with the library. The first finds every pin, in any Taskfile,
with no `# renovate:` comment above it, and moves them in one pull request:

```json
{ "extends": ["github>oleg-tkachuk/taskfiles//renovate/tasklib"] }
```

That pull request moves the pins and not the locks, so `check` is red on it
until someone runs the `lock` command above on the branch. A self-hosted
Renovate can do that itself:

```json
{ "extends": ["github>oleg-tkachuk/taskfiles//renovate/tasklib-lock"] }
```

which needs this module included in `Taskfile.yaml`, and the command in
Renovate's `allowedCommands`:

```
^task --yes --offline=false --download tasklib:lock$
```

A repository that includes it in `Taskfile.dev.yaml` — the root its gates run
from — extends `…//renovate/tasklib-lock-dev` instead, whose command carries
`-t Taskfile.dev.yaml`:

```
^task -t Taskfile\.dev\.yaml --yes --offline=false --download tasklib:lock$
```

`task` has to be where the command runs. With `renovatebot/github-action`
that is inside Renovate's container, not on the runner: install Task on the
runner and mount the binary into the container (the action's
`docker-volumes`), or the command is not found.

One more thing a consumer's own rules can do: the pin is found by a
`custom.regex` manager, from `github-releases`. A `packageRules` entry that
matches every `custom.regex` dependency — a "pinned tools" group, say — takes
the library's bump into that group too. Exclude it there
(`"matchDepNames": ["!oleg-tkachuk/taskfiles"]`) when it should arrive alone.

A command missing from that list is skipped with a log line and nothing turns
red — the pull request simply arrives without its lock.

## What it does not do

An include that carries its own `checksum:` is left as it is. `bump` moves the
ref and then stops at the download, on Task's own mismatch error; the new
value goes in by hand.

`TASKLIB_CACHE_DIR` is where this module reads and writes the lock, whatever
`TASK_REMOTE_DIR` says. A repository that points Task somewhere else sets the
input to the same place.

---

Part of [taskfiles](../README.md).
