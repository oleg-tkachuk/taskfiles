# auth — a local-dev JWT

One task: mint a token for local development. Dev only — the default secret is a
self-describing placeholder, so a token minted here must never be accepted by
anything that matters.

```yaml
includes:
  auth: { taskfile: '{{.TASKLIB}}/auth{{.TASKLIB_REF}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `auth:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `mint-token` | Mint a JWT for local development (override any JWT_* var) — alias `mint` |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `JWT_ALG` | `HS256` | |
| `JWT_SECRET` | `dev-secret-change-me-32-bytes-min` | |
| `JWT_ISS` / `JWT_AUD` / `JWT_SUB` | `local-dev` / `local-api` / `dev-user` | claims |
| `JWT_TTL_SECONDS` | `86400` | |

## Examples

```yaml
includes:
  auth:
    taskfile: '{{.TASKLIB}}/auth{{.TASKLIB_REF}}'
    dir: .
    vars: { JWT_ISS: acme-dev, JWT_AUD: core-api }
```

```console
$ task auth:mint-token
$ task auth:mint JWT_SUB=alice JWT_TTL_SECONDS=3600
$ export TOKEN=$(task auth:mint-token)
```

## The key never reaches the process table

It goes in through a process substitution rather than an argument. Needs the
smallstep `step` CLI.

---

Part of [taskfiles](../README.md).
