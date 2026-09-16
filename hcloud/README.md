# hcloud — the servers a project owns

What a project owns in Hetzner Cloud, the power state of its servers,
restarting them at three levels of force, a way in when one stops answering,
and a freeze for when it must not be touched.

Every task except `ssh` and `console` acts on **every** server the selector
matches, which is what makes one command work on a single server and on five.
The selector is therefore the whole safety boundary: an empty one matches every
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
| `inventory` | **Every** resource the selector matches, not just the servers; changes nothing |
| `poweron` | Power the servers on — nothing else can |
| `shutdown` | ACPI shutdown: the power button, and the guest decides — asks first |
| `reboot` | ACPI reboot, for a kernel that lives when the agent does not — asks first |
| `poweroff` | Cut power without a clean shutdown — asks first |
| `reset` | Hard reset: a power cut and a start in one — asks first |
| `protect` | Refuse deletion and rebuild on every matched server |
| `unprotect` | Lift that protection again — asks first |
| `ssh` | SSH into one server, `HCLOUD_SERVER=<name>` |
| `console` | VNC console on one server, `HCLOUD_SERVER=<name>` |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `servers` | the label in every log line |
| `HCLOUD_SELECTOR` | — | label selector naming the servers; **required** |
| `HCLOUD_SELECTOR_CMD` | — | a command printing one, when it has to be looked up |
| `HCLOUD_TOKEN_CMD` | — | a command printing the API token |
| `HCLOUD_SERVER` | — | the server for `ssh` and `console` |
| `HCLOUD_LIST_COLUMNS` | `name,status,type,location,ipv4,private_net` | columns for `servers` |
| `HCLOUD_STATUS` | — | show only servers in these states in `servers`, e.g. `off` |
| `HCLOUD_PAID_ONLY` | `0` | `1` limits `inventory` to what costs money |
| `HCLOUD_PROTECTION` | `delete rebuild` | what `protect`/`unprotect` set |
| `HCLOUD_SSH_USER` | `root` | user for `ssh` |
| `HCLOUD_SSH_PORT` | `22` | port for `ssh` |
| `HCLOUD_SSH_IPV6` | `0` | `1` reaches the server over IPv6 |

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
task hcloud:servers HCLOUD_STATUS=off
task hcloud:inventory HCLOUD_PAID_ONLY=1
task hcloud:reboot --yes
task hcloud:ssh HCLOUD_SERVER=api-0
task hcloud:ssh HCLOUD_SERVER=api-0 -- journalctl -u nginx --since -1h
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

The two commands above are placeholders. For what they look like when they are
real, see
[`oleg-tkachuk/hetzner-iac`](https://github.com/oleg-tkachuk/hetzner-iac/blob/abc50de2f21afa42c10ffa4e598bbe945a92e1b2/Taskfile.yaml):
there the selector is a cluster label read out of a committed topology file by
the parser that writes it, and the token comes out of an encrypted Pulumi stack
config. Neither could be a constant, which is the whole reason these inputs
take a command.

That example also shows the part worth copying deliberately: both commands are
set once on the `includes:` entry but carry `{{.stack}}`, which arrives on the
call — `task hcloud:servers stack=dev` and `stack=prod` select different
clusters through the same include. Note what that costs. A selector assembled
from a call-time value is not empty when the value is missing, it is malformed
(`cluster=` with nothing after it), so this module's "no HCLOUD_SELECTOR" guard
does not fire and only "no server matches" catches it. Making the argument
mandatory is the consumer's job; hetzner-iac gives `stack` no default on
purpose and prints a usage message naming the task that was run.

## Three rungs, and which one to reach for

Restarting a server is a question about what is still answering:

| Rung | Needs | Use when |
|---|---|---|
| `hcloud:ssh`, then the guest's own restart | the guest answering | normally — whatever runs inside closes down first |
| `hcloud:reboot` | the kernel running | the agent has stopped answering, the machine has not |
| `hcloud:reset` | nothing | the server is gone entirely |

`shutdown` and `poweroff` are the same pair without the coming back:
`shutdown` asks the guest, `poweroff` pulls the plug. Prefer the guest's own
shutdown whenever it answers, and reach for these when it does not.

`ssh` and `console` are the two ways in, in the same order. `ssh` resolves the
address through the same API and the same token as everything else here, so
there is no second place where a name turns into an address — but it needs a
booted guest with sshd and a public Primary IP. `console` needs none of that,
which is what makes it the way into a server that never finished booting.

Flag order in `ssh` is not cosmetic: `hcloud server ssh` stops parsing its own
flags at the first positional, so everything after the server name reaches the
remote shell untouched. That is why `task hcloud:ssh -- journalctl -u nginx`
works, and why no `--` is passed on to `ssh` itself.

## What the selector matches besides servers

`servers` answers one question about one resource type. `inventory` answers the
one that bites: volumes, load balancers, floating and primary IPs, firewalls,
snapshots and networks can all carry the same labels as the servers, and none
of them show up in `servers`. A deleted server leaves its volume behind, still
labelled and still billed.

`HCLOUD_PAID_ONLY=1` is the money question specifically — it drops the free
resources and leaves what the invoice is made of.

`inventory` is the one task that does **not** require the selector to match a
server: a selector can legitimately match a volume while matching no server at
all, and refusing that would hide exactly what the task exists to show.

## The freeze

`protect` turns on Hetzner's delete and rebuild protection for every matched
server; `unprotect` lifts it, and is the half that prompts. Both levels are set
by default, because a freeze that leaves rebuild open is not a freeze — rebuild
replaces the disk in place, losing everything on it without ever deleting the
server.

This is break-glass, not a desired state. Whatever provisions these servers
almost certainly declares protection itself — Terraform's `hcloud_server`
carries `delete_protection` and `rebuild_protection` — and will plan the flag
back to what it says the next time it runs. Turn it on for the length of an
incident, turn it off again, and leave the steady state to the provisioner.

## When one server refuses

A task that acts on the whole selector runs every server before it fails.
A `hcloud` command that refuses on the third of five does not stop the other
two from being tried; the task then exits non-zero naming the ones that did not
take:

```
◉ api · hcloud · poweron · api-0 api-1 api-2

✖ api · hcloud · poweron did not take on: api-1
```

The line above the actions is the expanded selector. Since the selector is the
safety boundary, seeing the names it came out as — before anything lands — is
the one check that is still available to a person.

## What is deliberately not here

`hcloud server` alone also has rebuild, change-type, rescue mode, ISO
attachment, backups, snapshots, RDNS and metrics. Each of those either fights
whatever provisions the servers for ownership of them, or is a one-off an
operator is better off typing — and `metrics` is marked ALPHA upstream. A
wrapper per API call would be a second, worse CLI to keep in step with the
first.

Three more are left out for reasons worth naming, because they look like they
belong here:

| Command | Why not |
|---|---|
| `add-label` / `remove-label` | they mutate the very selector every task here depends on: relabel a server and the next task silently acts on a different set |
| `reset-password` | it needs the server powered on **and** the qemu guest agent answering, so it fails in exactly the situation that sends you to `console` — and it rotates root's password out from under whatever configures the machine |
| `firewall apply-to-resource` | the one tempting cross-resource command ("isolate the fleet"), but it has to name a firewall that already exists, which is the provisioner's to own |

Use the CLI for those, with the token this module already resolves:

```bash
export HCLOUD_TOKEN="$(pass hetzner/token)"
hcloud server --help
```

## Stopping does not save money

A Hetzner server is billed while it **exists**, not while it runs, so stopping
one changes nothing on the invoice. What stopping buys is a server that is
unreachable and unchanging, with its disks at rest.

`task hcloud:inventory HCLOUD_PAID_ONLY=1` is the task that answers what does
cost.
