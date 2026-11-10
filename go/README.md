# go — build, test, lint

The Go surface for a single module: build, the test suites, the linters, the
dependency bumps.

`GOWORK=off` is the default and is the point of this file. A `go.work` in the
tree makes a local build resolve dependencies through the workspace, so a module
can be missing entries from its own `go.sum` and still look green here while CI —
which builds each module standalone — fails on it.

```yaml
includes:
  go: { taskfile: '{{printf .TASKLIB "go"}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `go:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `build` | Compile the command packages into the bin directory |
| `compile` | Type-check every package without writing a binary (for library modules) |
| `fmt` | gofmt -s -w, plus goimports when there is one (GO_FMT_GOIMPORTS=1 to need it, 0 to never run it) |
| `fmt:check` | Fail if gofmt -s would change any file — the CI-safe half of fmt |
| `lint` | golangci-lint over the module |
| `test` | Run the unit suite |
| `tidy` | go mod tidy the way CI resolves the module — standalone |
| `vuln` | govulncheck — vulnerabilities this module's code actually reaches |
| `deps:outdated` | List dependencies with a newer version available (read-only) |
| `deps:update` | Bump dependencies to the latest minor/patch, tidy, then prove it still builds |
| `test:coverage` | Run the unit suite with coverage; HTML report lands in coverage/ |
| `test:integration` | Run the integration suite (build tag, needs Docker) |
| `test:tagged:compile` | Type-check build-tagged suites that the default test run never compiles |
| `bench` | Run the benchmarks — no unit tests, just the measurements |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `go` | the label in every log line |
| `GO_PKG` | `./...` | package patterns to test and lint, space-separated; each is passed as one argument |
| `GO_MAIN` | `./cmd/...` | packages that produce binaries, space-separated like `GO_PKG` |
| `GO_BIN_DIR` | `./bin` | where `build` writes its binaries |
| `GO_TEST_FLAGS` | `-race -short` | flags for the unit run |
| `GO_BUILD_FLAGS` | — | extra `go build` flags, e.g. `-ldflags` |
| `GOLANGCI_FLAGS` | — | extra golangci-lint flags |
| `GO_TOOL_MODFILE` | — | a `go.mod` whose `tool` directives pin the tools, when they are not in this module's own |
| `GO_FMT_GOIMPORTS` | runs it when it is found | `1`: `fmt` needs goimports and fails without it; `0`: `fmt` never runs it |
| `GO_BENCH_PKG` | `GO_PKG` | packages to benchmark, space-separated like `GO_PKG` |
| `GO_BENCH_FLAGS` | `-benchtime=1x` | flags for the benchmark run |
| `GO_TEST_TAGS` | `integration` | for the tagged suites |
| `GO_TEST_TIMEOUT` | `10m` | `go test -timeout` for `test:integration`: a hang still fails, load need not |
| `GO_TEST_JSON` | — | where `test:integration` writes `go test -json`'s stream, for a consumer to read each package's result and time; needs gotestsum, and fails the run without it |
| `GOWORK` | `off` | `auto` to build through the workspace (an empty value keeps `off`) |

The `*_FLAGS` inputs are shell: they are word-split and parsed as written.
Every other value reaches the tool as data.

## Examples

```yaml
vars:
  PROJECT_NAME: core-api
  GO_MAIN: ./cmd/server
  GO_TEST_FLAGS: -p 1          # this suite shares package-level state

includes:
  go: { taskfile: '{{printf .TASKLIB "go"}}', dir: . }

tasks:
  build: { cmds: [{ task: go:build }] }
  test:  { cmds: [{ task: go:test }] }
  lint:  { cmds: [{ task: go:lint }] }
```

A library module with no `main`:

```yaml
tasks:
  build: { cmds: [{ task: go:compile }] }   # type-checks, writes nothing
```

## Why the tagged suites are compiled but not run

A build-tagged suite is invisible to the normal gate: it does not compile, it
does not run, and nothing notices it has rotted until someone needs it. `go vet`
with the tag takes seconds and catches exactly that — put it in the commit gate
next to `test`.

## gotestsum when there is one, `go test` when there is not

`test` uses `gotestsum` when there is one (one line per package) and plain
`go test` otherwise. Neither is worth a hard dependency.

## A pinned tool before PATH's

golangci-lint, govulncheck, goimports and gotestsum are each found the same
way: the one a `tool` directive pins, and only then the one on `PATH`.

```bash
go get -tool golang.org/x/vuln/cmd/govulncheck
```

That line in a module's `go.mod` is the version every machine and CI run uses.
`PATH` is whatever was installed last, and two versions of one linter disagree
about what is clean — a finding CI reports and a laptop does not, with nothing
changed in between.

Linters bring a long list of requirements with them. To keep those out of the
module's own `go.mod`, pin the tools in a separate one and name it:

```yaml
go:
  taskfile: '{{printf .TASKLIB "go"}}'
  dir: .
  vars: { GO_TOOL_MODFILE: tools/go.mod }
```

A `GO_TOOL_MODFILE` that does not exist fails the task. Falling back to `PATH`
there would drop the pin in silence.

`fmt` is the one place a missing tool changes the result rather than the
speed: with goimports it rewrites import blocks, without it it does not. A
repository that gates on formatting sets `GO_FMT_GOIMPORTS` to `1` or `0`, so
every machine does the same.

---

Part of [taskfiles](../README.md).
