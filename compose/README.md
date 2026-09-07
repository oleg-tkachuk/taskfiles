# compose — the local dependency stack

Postgres, Redis, queues — whatever the service needs to run locally. `up` waits
for health checks, so a task chained after it does not race the seeding.

```yaml
includes:
  compose: { taskfile: '{{.TASKLIB}}compose{{.TASKLIB_REF}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `dev:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `build` | Rebuild the images the stack is composed of, then start it |
| `down` | Stop the stack. Volumes are preserved. |
| `logs` | Tail the stack's logs (SERVICE=… for one of them) |
| `ps` | Show what is running |
| `reset` | Stop the stack and DELETE its volumes — local data is lost |
| `up` | Start the stack and wait until every service is healthy |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `COMPOSE_FILE` | `docker-compose.yaml` | the stack definition every task acts on |
| `PROJECT_NAME` | `stack` | the label in every log line |
| `SERVICE` | — | narrow `logs` to one service |
| `TAIL` | `200` | backlog for `logs` |
| `COMPOSE_ENGINE` | `docker compose` | e.g. `podman compose` |

## Examples

```yaml
includes:
  compose:
    taskfile: '{{.TASKLIB}}compose{{.TASKLIB_REF}}'
    dir: .
    vars: { COMPOSE_FILE: docker-compose.dev.yaml, PROJECT_NAME: acme }
```

```console
$ task compose:up
▸ acme · compose · up (docker-compose.dev.yaml)
✔ acme · compose · stack healthy

$ task compose:logs SERVICE=postgres
$ task compose:reset          # asks first: this deletes the volumes
```

## Everything here is idempotent

`up` on a running healthy stack is a no-op, and `down` on an absent one is the
desired end state rather than an error. `reset` is the exception: it deletes the
volumes, so it asks first.

---

Part of [taskfiles](../README.md).
