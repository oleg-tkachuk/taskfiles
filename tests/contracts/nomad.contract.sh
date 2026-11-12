#!/usr/bin/env bash
# nomad, against the real CLI and an agent of this run's own: the exit codes
# the tasks read still mean what they report, the server still refuses a job
# that moved on since its plan, and a prefix still stands in for a job's ID.
source "$(dirname "$0")/../lib.sh"

# An agent of this run's own, on ports nothing else is expected to hold. Every
# call below names it or an address nothing listens on: the CLI's default,
# 127.0.0.1:4646, may be somebody's cluster.
HTTP_PORT=14646
RPC_PORT=14647
SERF_PORT=14648
NOBODY_PORT=14649
AGENT_ADDR=http://127.0.0.1:$HTTP_PORT
NOBODY_ADDR=http://127.0.0.1:$NOBODY_PORT
# How long the agent gets to elect itself, in seconds.
AGENT_WAIT=60

unset NOMAD_NAMESPACE NOMAD_REGION NOMAD_TOKEN
export NOMAD_ADDR=$AGENT_ADDR
export NOMAD_CLI_NO_COLOR=1

cat > "$WORK/agent.hcl" <<HCL
bind_addr = "127.0.0.1"
ports {
  http = $HTTP_PORT
  rpc  = $RPC_PORT
  serf = $SERF_PORT
}
HCL

# Started where its configuration is: CI runs each tool in a container that
# sees the working directory and nothing else.
(cd "$WORK" && exec nomad agent -dev -config agent.hcl > agent.log 2>&1) &
AGENT_PID=$!
# The agent's own exit status, a signal's, is not this run's.
trap 'kill "$AGENT_PID" 2>/dev/null || true; wait "$AGENT_PID" 2>/dev/null || true; rm -rf "$WORK"' EXIT

waited=0
until nomad operator raft list-peers >/dev/null 2>&1; do
  if [ "$waited" -ge "$AGENT_WAIT" ] || ! kill -0 "$AGENT_PID" 2>/dev/null; then
    printf '%s\n' "✖ the agent did not come up at $AGENT_ADDR" >&2
    quoted '    | ' "$WORK/agent.log"
    exit 1
  fi
  sleep 1
  waited=$((waited + 1))
done

JOBS="$CONSUMER/jobs"
PLANS="$JOBS/.nomad-plan"
mkdir -p "$JOBS"

# job <id> <priority> — a job file for <id>, in the canonical format. The
# priority tells one version of the job from another: changing it changes the
# job and moves no allocation.
job() {
  cat > "$JOBS/$1.nomad.hcl" <<HCL
job "$1" {
  type     = "batch"
  priority = $2

  group "g" {
    task "t" {
      driver = "raw_exec"

      config {
        command = "/bin/sleep"
        args    = ["600"]
      }
    }
  }
}
HCL
}

# priority <id> — the priority of the job the cluster holds.
priority() { nomad job inspect -t '{{.Priority}}' "$1"; }

# The versions of the job below, by priority.
FIRST=41
SECOND=42
UNREAD=43
PLANNED=44
BEHIND=45

job contract-web "$FIRST"
# Submissions return once the server has the job: placing it is the client's
# business, and nothing here reads an allocation.
consumer nm nomad '{ NOMAD_DIR: jobs, NOMAD_RUN_FLAGS: "-detach", NOMAD_STOP_FLAGS: "-detach" }'

# ─── fmt ─────────────────────────────────────────────────────────────────────
run_task nm:fmt
expect_status ok "fmt: a formatted job file passes"

printf 'job "loose" {\n      type="batch"\n}\n' > "$JOBS/loose.nomad.hcl"
run_task nm:fmt
expect_status fail "fmt: a file not in the canonical format fails"
expect_output "loose.nomad.hcl" "fmt: and the CLI lists it"
if [ "$(awk 'NR == 2' "$JOBS/loose.nomad.hcl")" = '      type="batch"' ]; then pass "fmt: without rewriting it"; else fail "fmt: the check rewrote the file"; fi

printf 'job "loose" {\n  type =\n' > "$JOBS/loose.nomad.hcl"
run_task nm:fmt
expect_status fail "fmt: a file that does not parse fails"
rm -f "$JOBS/loose.nomad.hcl"

# ─── validate ────────────────────────────────────────────────────────────────
run_task nm:validate
expect_status ok "validate: a valid job passes, checked by the agent"

# With no agent to ask, the CLI still validates the job itself.
NOMAD_ADDR=$NOBODY_ADDR run_task nm:validate
expect_status ok "validate: a valid job passes with no agent to ask"
expect_output "not validated" "validate: and the CLI says what it left unchecked"

cat > "$JOBS/twice.nomad.hcl" <<'HCL'
job "twice" {
  type = "batch"

  group "g" {
    task "t" {
      driver = "raw_exec"
    }

    task "t" {
      driver = "raw_exec"
    }
  }
}
HCL
run_task nm:validate
expect_status fail "validate: a job with a task defined twice fails"
expect_output "twice.nomad.hcl" "validate: and is named"
NOMAD_ADDR=$NOBODY_ADDR run_task nm:validate
expect_status fail "validate: and fails with no agent to ask, too"
rm -f "$JOBS/twice.nomad.hcl"

# ─── plan ────────────────────────────────────────────────────────────────────
NOMAD_ADDR=$NOBODY_ADDR run_task nm:plan FILE=contract-web.nomad.hcl
expect_status fail "plan: a cluster that does not answer fails"
expect_output "did not complete" "plan: the CLI's exit code for it is read as an error"
if [ -e "$PLANS/contract-web.nomad.hcl.json" ]; then fail "plan: a plan that did not complete was saved"; else pass "plan: and nothing is saved"; fi

run_task nm:plan FILE=contract-web.nomad.hcl
expect_status ok "plan: a job the cluster does not have is planned"
expect_output "contract-web" "plan: shows the plan"
if [ "$(awk 'NR == 1' "$PLANS/contract-web.nomad.hcl.index")" = 0 ]; then
  pass "plan: the modify index of a job that is not there is still 0"
else
  fail "plan: the modify index of a new job is no longer 0"
fi
# Why the plan's namespace and region are saved beside it: the rendered job
# carries neither unless the file sets them.
if holds "$PLANS/contract-web.nomad.hcl.json" '"Namespace": null'; then
  pass "plan: the rendered job still names no namespace of its own"
else
  fail "plan: the rendered job now carries a namespace — apply need not compare the environment's"
fi

# ─── apply ───────────────────────────────────────────────────────────────────
run_task nm:apply FILE=contract-web.nomad.hcl
expect_status ok "apply: submits the saved plan"
if [ "$(priority contract-web)" = "$FIRST" ]; then pass "apply: the cluster holds the job that was planned"; else fail "apply: the cluster does not hold the planned job"; fi

# A change that moves no allocation. The CLI exits 0 for it, as it does for no
# change at all: why there is no task here that reads "unchanged" off a plan.
job contract-web "$SECOND"
status=0
(cd "$JOBS" && nomad job plan contract-web.nomad.hcl > "$OUT" 2>&1) || status=$?
if [ "$status" = 0 ] && holds "$OUT" "in-place"; then
  pass "the CLI still exits 0 for a plan that updates a job in place"
else
  fail "the CLI no longer exits 0 for an update in place (exit $status) — a plan's exit code may now tell a change"
fi

# The job is rendered when it is planned: what the file says later is not
# what is submitted.
run_task nm:plan FILE=contract-web.nomad.hcl
expect_status ok "plan: an update in place is planned"
job contract-web "$UNREAD"
run_task nm:apply FILE=contract-web.nomad.hcl
expect_status ok "apply: submits an update"
if [ "$(priority contract-web)" = "$SECOND" ]; then pass "apply: as it was planned, not as the file reads now"; else fail "apply: submitted the file as it reads now"; fi

# A job that moved on since the plan: the server refuses the submission.
job contract-web "$PLANNED"
run_task nm:plan FILE=contract-web.nomad.hcl
job contract-web "$BEHIND"
(cd "$JOBS" && nomad job run -detach contract-web.nomad.hcl >/dev/null 2>&1)
run_task nm:apply FILE=contract-web.nomad.hcl
expect_status fail "apply: a job that changed since the plan is refused"
expect_output "was not submitted" "apply: the CLI's exit code for it is read as a refusal"
if [ "$(priority contract-web)" = "$BEHIND" ]; then pass "apply: and the cluster keeps what it had"; else fail "apply: the stale plan reached the cluster"; fi
if [ -e "$PLANS/contract-web.nomad.hcl.json" ]; then fail "apply: a refused plan was kept"; else pass "apply: the refused plan is spent"; fi

# ─── stop ────────────────────────────────────────────────────────────────────
# Why stop wants the ID whole: the CLI resolves a prefix to the one job it
# matches. When this stops being true, the refusal can go.
if [ "$(nomad job inspect -t '{{.ID}}' contract 2>/dev/null)" = contract-web ]; then
  pass "the CLI still resolves a prefix to the job it matches"
else
  fail "the CLI no longer resolves a prefix to a job — stop need not refuse one"
fi

run_task nm:stop JOB=contract CONFIRM=contract
expect_status fail "stop: a prefix is refused"
expect_output "contract-web" "stop: and the job it would have stopped is named"
if [ "$(nomad job inspect -t '{{.Stop}}' contract-web)" = false ]; then pass "stop: which goes on running"; else fail "stop: the prefix stopped the job"; fi

run_task nm:stop JOB=no-such CONFIRM=no-such
expect_status fail "stop: a job the cluster does not have fails"

run_task nm:stop JOB=contract-web CONFIRM=contract-web
expect_status ok "stop: a job named whole, twice, is stopped"
if [ "$(nomad job inspect -t '{{.Stop}}' contract-web)" = true ]; then pass "stop: and the cluster has it stopped"; else fail "stop: the job is not stopped"; fi

finish
