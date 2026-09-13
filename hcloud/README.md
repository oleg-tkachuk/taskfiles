# hcloud — the power state of the servers

Turning Hetzner Cloud servers off and on, restarting them at three levels of
force, and opening a console on the one that will not boot.

Every task except `console` acts on **every** server the selector matches,
which is what makes one command work on a single server and on five. The
selector is therefore the whole safety boundary: an empty one matches every
server in the project, so a missing value is refused rather than widened.

```yaml
includes:
  hcloud: { taskfile: '{{printf .TASKLIB "hcloud"}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `hcloud:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `servers` | Power state of every server the selector matches; changes nothing |
| `poweron` | Power the servers on — nothing else can |
| `shutdown` | ACPI shutdown: the power button, and the guest decides — asks first |
| `reboot` | ACPI reboot, for a kernel that lives when the agent does not — asks first |
| `poweroff` | Cut power without a clean shutdown — asks first |
| `reset` | Hard reset: a power cut and a start in one — asks first |
| `console` | VNC console on one server, `HCLOUD_SERVER=<name>` |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `servers` | the label in every log line |
| `HCLOUD_SELECTOR` | — | label selector naming the servers; **required** |
| `HCLOUD_SELECTOR_CMD` | — | a command printing one, when it has to be looked up |
| `HCLOUD_TOKEN_CMD` | — | a command printing the API token |
| `HCLOUD_SERVER` | — | the server for `console` |
| `HCLOUD_LIST_COLUMNS` | `name,status,type,location,ipv4,private_net` | columns for `servers` |

## Examples

```yaml
includes:
  hcloud:
    taskfile: '{{printf .TASKLIB "hcloud"}}'
    dir: .
    vars:
      HCLOUD_SELECTOR: 'component=api'
```

```bash
task hcloud:servers
task hcloud:reboot --yes
task hcloud:console HCLOUD_SERVER=api-0
```

When the selector or the token is not a constant, give the module a command to
get it rather than a value. Both run **inside** the task, so `task --list`
never reaches for a credential and never shells out to work out a name:

```yaml
      HCLOUD_SELECTOR_CMD: 'my-inventory selector {{.env}}'
      HCLOUD_TOKEN_CMD: 'pass hetzner/token'
```

`HCLOUD_TOKEN` exported in the shell is what the CLI itself reads, so a
session that already has one needs neither input.

## Three rungs, and which one to reach for

Restarting a server is a question about what is still answering:

| Rung | Needs | Use when |
|---|---|---|
| the guest's own restart | the guest answering | normally — whatever runs inside closes down first |
| `hcloud:reboot` | the kernel running | the agent has stopped answering, the machine has not |
| `hcloud:reset` | nothing | the server is gone entirely |

`shutdown` and `poweroff` are the same pair without the coming back:
`shutdown` asks the guest, `poweroff` pulls the plug. Prefer the guest's own
shutdown whenever it answers, and reach for these when it does not.

## What is deliberately not here

`hcloud server` alone also has rebuild, change-type, rescue mode, ISO
attachment, backups, snapshots, RDNS and metrics. Each of those either fights
whatever provisions the servers for ownership of them, or is a one-off an
operator is better off typing — and `metrics` is marked ALPHA upstream. A
wrapper per API call would be a second, worse CLI to keep in step with the
first.

Use the CLI for those, with the token this module already resolves:

```bash
export HCLOUD_TOKEN="$(pass hetzner/token)"
hcloud server --help
```

## Stopping does not save money

A Hetzner server is billed while it **exists**, not while it runs, so stopping
one changes nothing on the invoice. What stopping buys is a server that is
unreachable and unchanging, with its disks at rest.
