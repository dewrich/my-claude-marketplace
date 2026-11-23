---
name: orchestrator
description: Run a fleet of Claude agents, each in its own dewterm pane, up to 20 at once. Reports blockers first, reads the playbook and handover, checks main and every open lane (HOLD when main is red), plans which work runs side by side and which waits (a planner agent writes the plan if none exists), starts three zero-token clocks (timer, sweeps, watch), then launches agents on the next work, collects results and refills free slots. Use when the user types /orchestrator or asks to fan work out to several visible terminal agents.
---

# Orchestrator: a fleet of agents in dewterm panes

Start Claude Code agents, each in its own dewterm pane next to this one, give each a task, hear
when each finishes, collect results, and refill the free slot from the queue. The user watches
every agent work live.

Typing `/orchestrator` runs twelve steps in order. It reports first, gets up to speed, checks,
plans, and launches; three clocks keep it going afterwards.

## Preconditions

Run these first. Stop and tell the user if any fails.

```sh
test -n "$DEWTERM_SOCKET" && test -n "$DEWTERM_PANE"   # must be running inside a dewterm pane
command -v dewterm                                      # the CLI that talks to the app
```

dewterm has no public subcommand for panes yet. It exposes a tmux-compatible control socket
through `dewterm __tmux`, and this skill drives that. Each Bash call starts a fresh shell, so put
this at the top of every call that uses it:

```sh
dt() { dewterm __tmux "$@"; }
```

Supported commands: `split-window`, `send-keys`, `list-panes`, `kill-pane`, `select-pane`,
`display-message`. `capture-pane` returns nothing, so output is never read from a pane; agents
report through files.

## Hard limit: 20 agents

Never run more than 20 agent panes at once, not counting this orchestrator pane. Tasks beyond the
limit queue in `$RUN/queue.tsv` and start as agents finish and their panes close. Before every
spawn, count the `running` lines in the ledger and check them against
`dt list-panes -F '#{pane_id}'`; a pane whose shell exited is gone from that list, so mark its
ledger line `gone`. Fewer panes beat more: launch only as many agents as there are unblocked, non-overlapping tasks;
the limit is a ceiling, never a target.

## State lives in files

Shell variables do not survive between calls, so everything is on disk. Create the run once:

```sh
RUN=$(mktemp -d "${TMPDIR:-/tmp}/orchestrator.XXXXXX")
printf '%s\n' "$RUN" > "${TMPDIR:-/tmp}/orchestrator.current"
```

and start every later call with `RUN=$(cat "${TMPDIR:-/tmp}/orchestrator.current")`.

`$RUN` holds:

- `ledger.tsv`: one line per agent, tab separated: `n  pane  state  workdir  task`. `state` is
  `running`, `done` or `gone`. Append a line right after the pane id comes back from a spawn;
  rewrite the line's state when it changes.
- `queue.tsv`: tasks waiting for a slot, one per line: `n  workdir  task`, with the full prompt in
  `$RUN/<n>.prompt`.
- `<n>.prompt`, `<n>.md`, `<n>.done`: the agent's prompt, its result summary, its finished marker.
- `clocks.txt`: ids of the timer and monitors. `stop`: touching it ends the monitor scripts.
  `<n>.sig`, `<n>.flag-*`: sweeps bookkeeping.

The repo holds two files that outlive a run, in `.orchestrator/` at the repo root. Keep that
directory out of commits unless the user says otherwise.

- `plan.md`: the phase plan and backlog, written by the planner agent (step 5) and updated by this
  run as items finish. Format:

  ```
  # Plan <date>
  ## Phase 1: <name>
  status: active | waiting | done
  waits-on: nothing | phase N | user decision: <what>
  - [ ] P1.1 <task> | files: <paths or globs> | needs: none
  - [ ] P1.2 <task> | files: <paths> | needs: P1.1
  ## Backlog
  - [ ] B1 fix: <task> | files: <paths>
  - [ ] B2 check: <task> | files: <paths>
  ```

  Item marks: `[ ]` open, `[~]` running (add `agent n`), `[x]` done, `[!]` failed or gone.
- `playbook.md`: the standing rules, including rules not yet enforced by code, and optionally the
  command that tests main (`test-command: ...`). The user owns it; never edit it.
- `handover.md`: written by each run for the next one. Exactly these sections, so the report can
  be built from them:

  ```
  # Handover <date and time>
  ## Blockers
  ## The phase waits on
  ## Waits on you
  ## Open lanes
  - <lane>: <branch or PR>, <ahead/behind main>, <dirty or clean>, <CI>, <agent pane or none>
  ```

## Procedure

### 1. Report first

Before anything else, print one screen the user can read in ten seconds. Read only
`.orchestrator/handover.md` and the `waits-on:` lines of `.orchestrator/plan.md` for this; if it is missing, print "no handover yet (first run)" and
move on. Three headings, one to three lines each:

- **Blockers**: what is stuck right now.
- **The phase waits on**: the specific work or decision the current phase is blocked by.
- **Waits on you**: decisions or actions only the user can take.

Do not wait for an answer unless something under "Waits on you" blocks the request.

### 2. Read the playbook and the handover

Read `.orchestrator/playbook.md` and the rest of the handover (open lanes). A missing file is one
line of notice, not an error. Where the playbook and this file disagree, the playbook wins,
except on the hard limit and the Rules section, which only the user can change.

### 3. What's running

If a ledger exists from an earlier run (`${TMPDIR:-/tmp}/orchestrator.*/ledger.tsv`) with
`running` lines whose panes are still in `dt list-panes`, say so and ask whether to adopt that
run or start a new one. Do not spawn duplicates of work an alive agent already has.

### 4. Check

Read only; push nothing. Run after step 3 and again before every refill in step 10.

- **main**: is it red? Check the latest CI run on the default branch:
  `gh run list --branch main --limit 1 --json status,conclusion,headSha`. If `gh` is missing or
  offline, use the playbook's `test-command` on a clean checkout of main (a worktree, never this
  one). If neither exists, say "main status unknown" in the report and continue.
  - Red (`conclusion` is `failure`, or the test command fails): the state is **HOLD**. The only
    task that launches is one agent whose prompt is to find and fix the failure on its own
    branch, not push. Queue every other task and say HOLD, with the failing run, in the report.
  - In progress: treat as green, but recheck before the next refill.
  - Green: HOLD lifts; queued tasks may launch.
- **every open lane**: each ledger `running` line, each entry of `git worktree list` other than
  this checkout, and each open PR from `gh pr list --state open --json number,headRefName,statusCheckRollup`.
  For each, record one line: branch or PR, ahead/behind main, dirty files, CI result, which
  agent pane is attached or none. A lane with no agent and unfinished work is a candidate to
  finish before new work starts. These lines become "Open lanes" in the handover.

### 5. Phase plan

Decide which work runs side by side and which must wait, and write it to
`.orchestrator/plan.md`.

- **A plan exists** (at least one phase with open items): read it. Update statuses from the check
  in step 4 and from the ledger: an item whose agent is gone is `[!]`; a phase whose items are all
  `[x]` is `done`, and the next phase becomes `active` only if its `waits-on:` is satisfied and
  main is green.
- **The user gave explicit tasks**: those tasks are the plan. Write them as the items of phase 1,
  with `files:` filled in by reading the repo, and skip the planner.
- **No plan and no tasks**: launch one planner agent (it takes one slot) before anything else,
  except the main fix under HOLD. Its prompt: "Read the repo, `.orchestrator/playbook.md`,
  `.orchestrator/handover.md`, the docs, and open issues (read only). Write a phase plan to
  `.orchestrator/plan.md` in this format: <the format above>. Phases are ordered; items inside a
  phase must be able to run side by side, so give each its `files:` and any `needs:`. Add a
  backlog of fixes and checks. Do not edit anything else, do not push." Start the clocks first (step 8) so the watch hears it, then launch it as in step 9 and wait for its
  `DONE`.
  Then print a summary of the plan (phases, item counts, what each phase waits on) and ask the
  user once to approve it before launching. After approval, later ticks proceed on their own.

Two items run side by side only if their `files:` do not overlap and neither `needs:` the other.
Overlapping items are serialized, or each runs in its own worktree (step 7).

### 6. What to build

Choose which items fill the free slots (`20` minus `running` in the ledger), in this order:

1. **Finish what's open**: lanes from step 4 that have unfinished work and no agent, and `[!]`
   items whose agent went missing.
2. **The plan's next pieces**: open items of the active phase whose `needs:` are done and whose
   `files:` do not overlap anything running or already chosen.
3. **Backlog**: fixes and checks, only when 1 and 2 leave slots free.

Under HOLD, the only choice is the fix for main. Chosen items beyond the free slots go to
`queue.tsv` in this order, and the order is recomputed on every refill and tick. Never choose an
item from a phase that is not `active`.

### 7. Split the work

Turn each chosen item into a task with a complete prompt of its own: the agent has none of this
conversation. Include the item id and text, its `files:`, the playbook rules that apply to it,
and the result contract (step 9). Write each prompt to `$RUN/<n>.prompt`.

Any task that edits files gets its own git worktree and branch when another agent is running or
chosen, so up to 20 agents cannot trample one checkout:
`git worktree add ../<repo>-agent-N -b agent/N`, used as that agent's working directory. A task
that is read-only, or the only agent, can use this checkout. Worktrees are never removed by the
orchestrator; they appear as open lanes until the user merges or removes them. Start the ledger
task text with the item id, for example `P1.2: add retry to fetch`.

### 8. Start the 3 clocks

The clocks keep the run going without this session polling. They cost no tokens while nothing
happens and wake this session only with a result. Start each once per run, before launching.
Load `Monitor`, `CronCreate`, `CronList` and `CronDelete` with `ToolSearch` if they are deferred.
Record each clock's id in `$RUN/clocks.txt` so a resumed run can check them (`CronList`, task
list) before starting duplicates.

**watch**: hears when an agent finishes. One `Monitor`, `timeout_ms: 1800000`, command:

```sh
RUN=$(cat "${TMPDIR:-/tmp}/orchestrator.current"); seen=""
while [ ! -e "$RUN/stop" ]; do
  for f in "$RUN"/*.done; do
    [ -e "$f" ] || continue
    n=$(basename "$f" .done)
    case " $seen " in *" $n "*) ;; *) seen="$seen $n"; echo "DONE $n" ;; esac
  done
  sleep 10
done
```

It prints `DONE n` once per finished agent. Do not poll faster than every 10 seconds.

**sweeps**: checks every agent's pane and movement. One `Monitor`, `timeout_ms: 1800000`, command:
`sh <skill-dir>/sweeps.sh "$RUN"`, where `<skill-dir>` is the directory holding this
SKILL.md (the base directory shown when the skill loads). Every 2 minutes, for each ledger line still `running` without a
`.done` file, it checks the pane is still in `dt list-panes` and that the agent's working
directory moved (HEAD, `git status`, `git diff --shortstat`). It prints one line per agent per
state, only on a change:

- `GONE n`: the pane closed without a `.done` file.
- `STUCK n no change for Nm`: nothing in the working directory moved for 15 minutes (set
  `STUCK_AFTER` in seconds to change this). Movement clears the flag, so a later stall reports
  again.

`capture-pane` returns nothing, so sweeps cannot read the screen. An agent that is only thinking
or reading, or whose directory is shared with another agent, can look stuck or look alive by
mistake; treat `STUCK` as a prompt to look at the pane, never as proof. If agent hooks are
installed (`dewterm hooks install`), the user also gets a bell notification when an agent needs
input or stops.

**timer**: starts the next work every 25 minutes, day and night. `CronCreate` with cron
`7-59/25 * * * *` (minutes 7, 32 and 57, off the :00 and :30 marks), recurring, prompt
`/orchestrator tick`. The scheduler may run it up to half a period late, and it fires only while
this session is idle. Cron jobs live only in this session and expire after 30 days; tell the user
both when starting it.

**Tick.** When the prompt is `/orchestrator tick`, do not start a new run. Read `$RUN` from
`${TMPDIR:-/tmp}/orchestrator.current`, then:

1. Reconcile the ledger with `dt list-panes`: mark panes that vanished `gone`; collect any `.done`
   the watch missed (step 10).
2. Run the check (step 4). If main turned red, HOLD starts; if it turned green, HOLD lifts.
3. Re-run steps 5 and 6, and launch what they choose into free slots (step 9).
4. If any of it changed, rewrite the handover and print one line saying what changed. If
   nothing changed, print `tick: no change` and nothing else.
5. Re-arm any expired monitor: both `Monitor` clocks stop at 30 minutes, so check the task list
   and start a fresh watch or sweeps if one is missing.

**Monitor events.** On `DONE n`, collect and refill (step 10). On `GONE n`, step 11. On
`STUCK n`, tell the user the pane and how long, and offer a nudge (step 11).

**Stopping.** When the queue is empty, no phase is `active` with open items, and no agent is running, or the user says stop: `touch
"$RUN/stop"` (both scripts exit on it), `TaskStop` the monitors, and `CronDelete` the timer.

### 9. Launch

`-d` keeps focus here and `-P -F` prints the new pane id. Pass the command and prompt as separate
arguments so dewterm quotes them. `-t` is the pane to split and `-h` is the only flag that
changes direction. The prompt is the task prompt plus the result contract below:

```sh
CLAUDE=$(command -v claude)   # absolute path: panes run `$SHELL -l -c`, which skips .zshrc and may lack it on PATH
PANE=$(dt split-window $SPLIT -t "$TARGET" -d -P -F '#{pane_id}' -c "$WORKDIR" \
  env ${CLAUDE_CONFIG_DIR:+CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"} "$CLAUDE" "$PROMPT")
printf '%s\t%s\trunning\t%s\t%s\n' "$N" "$PANE" "$WORKDIR" "$TASK" >> "$RUN/ledger.tsv"
```

Panes do not inherit this session's environment, so forward `CLAUDE_CONFIG_DIR` when it is set.
Without it the agent logs in with the default `~/.claude` account and may fail with "Your
authentication token belongs to organization ...". Forward any other variable the agent needs the
same way.

If a pane closes right after it opens, the command failed: rerun it as
`sh -c 'cmd > $RUN/err.log 2>&1; sleep 5'` and read the log.

**Result contract.** Append verbatim to every prompt, with the real `$RUN` and task number
substituted:

> When finished, write a short summary of what you did and anything the reviewer must know to
> `$RUN/<n>.md`, then create the empty file `$RUN/<n>.done`. Do not edit files outside your task.

**Layout: stack up to 4 agents per column, then start a new column.** Never run `select-layout`:
it rebuilds the layout and discards the columns. Agents stack top to bottom (split without `-h`,
so the new pane goes below); a column holds at most 4. The next agent starts a new column to the
right (`-h`). With the orchestrator on the left, 20 agents make 5 columns of 4:

```
orchestrator | agent 1 | agent 5 | agent 9  | agent 13 | agent 17
             | agent 2 | agent 6 | agent 10 | agent 14 | agent 18
             | agent 3 | agent 7 | agent 11 | agent 15 | agent 19
             | agent 4 | agent 8 | agent 12 | agent 16 | agent 20
```

Create every column's top pane first, then fill the columns, so each column spans the full
height. A split divides only the pane you target, so splitting a column head with `-h` after the
panes below it exist would make a short pane beside it and not a column.

- Columns needed: `ceil(agents / 4)`. Agent 1 is `SPLIT=-h`, `TARGET=$DEWTERM_PANE` as `%N` (the
  orchestrator pane); each later column head is `-h` with `TARGET` the previous column's head.
- Each remaining agent has `SPLIT=` (empty, stacked) and `TARGET` the pane above it in its
  column. Spawn all heads first (agents 1, 5, 9, ...), then fill column 1 top to bottom, then
  column 2, and so on. For 5 agents the order is 1, 5, 2, 3, 4.
- A refill goes under the last live pane of a column with fewer than 4, or else starts a new
  column at the right edge. Read the live pane list from the ledger, not from memory.
- Twenty panes are narrow. If a run needs fewer than 20, use fewer columns.

### 10. Collect and refill

On each `DONE n` from the watch clock:

1. Read `$RUN/<n>.md`.
2. Mark the item `[x]` in `plan.md` (or `[!]` if the summary says it failed). Set the ledger line
   to `done` and close the pane with `dt kill-pane -t "$PANE"` (only panes
   this run started). dewterm gives the closed pane's space to its neighbour.
3. Check main again (step 4), then re-run steps 5 and 6: finishing an item may unblock `needs:`
   or complete a phase. Launch what they choose into the freed slots (step 9); if main is red,
   only the main fix launches.

### 11. Handle stuck agents

If an agent needs input, tell the user which pane and why; the user can type in that pane. To
nudge one yourself: `dt send-keys -t "$PANE" "your text" Enter`. Say so before sending anything
that is not a plain continue. A ledger line whose pane vanished from `list-panes` without a
`.done` file is `gone`: tell the user and put its task back at the front of the queue only if
they agree.

### 12. Report and hand over

When the queue is empty and nothing is running, print one line per task: pane, status, summary,
files touched. Flag conflicts and agents that never wrote `.done`.

Then rewrite `.orchestrator/handover.md` in the format above for the next run: what is blocked,
what the phase waits on (copied from `plan.md`), what waits on the user, and the open lanes from
the last check. Also
rewrite it right after the first launch in step 9, so a session that ends early still leaves a
handover.

## Rules

- Never leave the clocks running after the run ends; step 8 says how to stop them.
- Only kill panes this run created. Never kill the orchestrator's own pane or any pane not in the
  ledger.
- Do not give agents permission-bypass flags unless the user asked for them; an agent that stops
  at a permission prompt is visible in its pane and the user can answer it.
- Under HOLD, launch nothing except the fix for main.
- Never launch from a phase that is not `active`, and never launch two items whose `files:` overlap
  into one checkout.
- Never rewrite or reorder a plan the user approved without saying so; mark items, do not delete
  them.
- Do not push, open PRs, or touch anything outside the repo from the orchestrator or in agent
  prompts unless the user asked.
- If `dt` fails with "not running inside dewterm" or "cannot reach dewterm", stop; do not fall
  back to tmux or background subprocesses without asking.

## Limits to mention to the user

- Agents are separate `claude` processes, not subagents; they share nothing but files.
- Panes live in this tab and are not restored by session restore.
- Output is not captured by dewterm; results arrive only through the files the agents write, and
  sweeps infer health from panes and git, not the screen.
- Up to 20 panes in one tab are narrow, and 20 agents burn tokens fast; the plan decides how many
  actually run.
- The timer is session-only and lasts at most 30 days; both monitors need re-arming every 30 minutes.
