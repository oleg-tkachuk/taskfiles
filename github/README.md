# github — repository administration, done deliberately

One task, and it exists because of a gap that was measured rather than guessed.

A protected `main` with `enforce_admins` on refuses **every** direct ref update.
Both were tried: a plain push and a `--force` push, each declined with
`5 of 5 required status checks are expected`. GitHub has no "admins follow the
rules except for force-push" setting, and a ruleset bypass is whole-ruleset —
it would hand back every rule at once, which is the hole rather than the hatch.

So the escape hatch is a toggle. A toggle is exactly the thing a human gets
right on the way in and forgets on the way out, and that forgetting is not
hypothetical: `enforce_admins` sat at `false` in this repository while
`CONTRIBUTING.md` said *"there is no direct push, for anyone"*. Nothing
reported the gap; it surfaced only when a direct push succeeded that should
have been refused.

`force-push` closes the window itself. The flag is restored from an `EXIT`
trap, which covers a push that succeeds and one that fails.

It does **not** cover a hard interrupt. The shell Task runs commands in accepts
`trap … EXIT` and rejects everything else — `trap: INT: invalid signal
specification`, measured rather than assumed — so Ctrl-C in the second or two
between the two API calls can leave protection down. The task prints the
one-line restore command *before* it lifts anything, so the way back is already
in the scrollback if that happens.

```yaml
includes:
  github: { taskfile: '{{printf .TASKLIB "github"}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. Tasks then read `github:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `force-push` | Drop `enforce_admins`, force-push the branch, restore the flag |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `GH_REPO` | the `origin` remote | `owner/name` |
| `GH_BRANCH` | `main` | the protected branch |
| `REF` | `HEAD` | what to push |
| `REASON` | — | **required**; recorded beside the flag change |

## Using it

```bash
task github:force-push REASON="drop the secret from 3 published commits"
```

`REASON` is not decoration. It is what the next reader sees when they ask why
protection was off for ninety seconds, and requiring it is what stops the task
becoming a reflex.

The push is `--force-with-lease`, not `--force`: if somebody else moved the
branch while protection was down, the push is refused rather than silently
discarding their work.

## What it refuses

If `enforce_admins` is already off, the task **fails** instead of proceeding.
It exists to reopen a closed door for one command; finding the door already
open means the branch is not in the state the caller assumed, and carrying on
would restore a flag that was never set — this task inventing policy rather
than borrowing it.
