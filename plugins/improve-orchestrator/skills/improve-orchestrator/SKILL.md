---
name: improve-orchestrator
description: Improve the orchestrator plugin from inside any project. Tell it once what should work differently (/improve-orchestrator <what you spotted>); it records the idea, starts an agent in a new dewterm pane that builds the change in an isolated worktree of the marketplace repo, then guides review, merge and `claude plugin update` so the next /orchestrator is already better. Also records mistakes as lessons that must become code (/improve-orchestrator lesson <text>). Use when the user types /improve-orchestrator or says the orchestrator should work differently, got something wrong, or needs a new behaviour.
---

# improve-orchestrator: the orchestrator keeps getting better

The loop, from the diagram this plugin implements:

```
you spot something -> tell the orchestrator in a new tile -> it's built and merged
-> claude plugin update -> next /orchestrator is already better
```

One command works in every project. Nothing project-specific is stored in the project; the
improvement lands in the `orchestrator` plugin itself, so every project gets it.

## Commands

- `/improve-orchestrator <what you spotted>`: run the loop below.
- `/improve-orchestrator lesson <text>`: record a mistake as a lesson (step L).
- `/improve-orchestrator update`: skip to step 5 (after the PR merged).
- `/improve-orchestrator status`: print config, open lessons, and any in-flight improvement (step 0 only plus the ledger).

## 0. Set itself up (first start creates every file)

Run the setup script every time; it creates only what is missing and is safe to repeat. The base
directory of this skill is shown when it loads.

```sh
sh <skill-dir>/setup.sh            # inside the marketplace repo, or:
sh <skill-dir>/setup.sh /path/to/my-claude-marketplace
```

It writes `${XDG_CONFIG_HOME:-$HOME/.config}/improve-orchestrator/` with:

- `config`: `REPO` (marketplace checkout holding `plugins/orchestrator`), `DEFAULT_BRANCH`,
  `BRANCH_MODE` (`main` or `staging`), `PLUGIN_REF` (`orchestrator@<marketplace>`).
- `lessons.md`: the lessons log.
- `inflight.tsv`: created on first use in step 3: `id  pane  branch  worktree  idea`.

If it exits with `NEEDS_REPO=1`, ask the user once for the marketplace repo path and rerun with
it. If setup printed `BRANCH_MODE` wrongly, edit `config` on the user's say-so.

## 1. Capture

Restate the idea as one outcome, in the orchestrator's terms: what should work differently, and
how a user would notice. If it is ambiguous in a way that changes the build, ask one question;
otherwise proceed. Check `lessons.md` and the orchestrator's `SKILL.md` first: if the behaviour
already exists or a lesson covers it, say so instead of building it again.

Classify it:

- **change**: new or different behaviour in `plugins/orchestrator`.
- **lesson**: something went wrong. Goes through step L, then becomes a change.

## 2. Fit the branches

Read `BRANCH_MODE` from `config`.

- `main`: the agent branches off `DEFAULT_BRANCH`; the PR targets `DEFAULT_BRANCH`.
- `staging`: the agent branches off `staging`; the PR targets `staging`. Promotion
  `staging -> main` is a separate, user-run step; never include it here.

Branch name: `improve/<short-slug>`. Worktree: `<REPO>/../my-claude-marketplace-improve-<slug>`,
created with `git -C "$REPO" worktree add -b <branch> <path> <base>` after `git fetch`. Never edit
`REPO`'s own checkout, so a run in progress is never disturbed.

## 3. Tell the orchestrator in a new tile

Needs dewterm (`$DEWTERM_SOCKET`, `$DEWTERM_PANE`). If missing, say so and offer to run the
build in this session in the worktree instead.

Start one Claude agent in a new pane beside this one, with the worktree as working directory,
using the same mechanics as the orchestrator skill (`dewterm __tmux split-window -h -d -P -F
'#{pane_id}' -c <worktree> env ${CLAUDE_CONFIG_DIR:+CLAUDE_CONFIG_DIR=...} "$(command -v claude)"
"<prompt>"`; forward `CLAUDE_CONFIG_DIR` when set; no permission-bypass flags). If a pane for an
earlier improvement is still in `inflight.tsv` and alive, split below it (no `-h`) instead of
making a new column. Append `id pane branch worktree idea` to `inflight.tsv`.

The agent prompt must be complete (the agent has none of this conversation):

1. The outcome from step 1, and the lesson text if any.
2. Scope: edit only `plugins/orchestrator/` (and `lessons.md` status if it fixes a lesson).
   Prefer the smallest change. Read `plugins/orchestrator/skills/orchestrator/SKILL.md` and
   `sweeps.sh` first and match their style.
3. **Every lesson becomes code**: if the idea comes from a mistake, the fix must be enforced, not
   just described: a check in `sweeps.sh`, a precondition or step in `SKILL.md`, or a script
   with a test. A sentence in the Rules section alone is not enough unless nothing can be
   automated; say why in the PR body.
4. Bump the `version` in `plugins/orchestrator/.claude-plugin/plugin.json` (patch for fixes,
   minor for new behaviour). `claude plugin update` only sees a new version.
5. Verify: `claude plugin validate <worktree>`, `sh -n` on every changed `.sh`, and run any
   script it added against a scratch directory.
6. Commit locally on the branch with a normal message. **Do not push, open a PR, or touch
   anything outside the worktree.** The user approves that with `gcpr` (see the user's global
   instructions); when they type it, the commit, push and PR happen in that one run, as a new PR
   from this branch targeting the branch from step 2.
7. Result contract: write a short summary (what changed, why, how verified) to
   `<config-dir>/results/<id>.md`, then create `<config-dir>/results/<id>.done`.

Tell the user the pane, the branch, and that they can watch it. Do not wait for it unless they
ask; a `Monitor` on the `.done` file (zero tokens while idle) is the way to hear it if they want
to be told.

## 4. Review and merge

On the `.done` file: read the result, show `git -C <worktree> diff <base>...HEAD --stat` and the
key hunks, and run `claude plugin validate`. Then stop and say it is ready: the user types
`gcpr` to push and open the PR, and merges it themselves. This skill never pushes, opens a PR,
or merges.

## 5. claude plugin update

After the user says it is merged (or runs `/improve-orchestrator update`):

```sh
git -C "$REPO" fetch origin
git -C "$REPO" branch -r --merged origin/<target> | grep -q "origin/<branch>"   # confirm it landed
claude plugin marketplace update my-claude-marketplace
claude plugin update "$PLUGIN_REF"
```

Verify with `claude plugin list` that the version matches the bump. Tell the user the new
version and that it applies to **new** sessions: type `/orchestrator` in a fresh session (or
`/reload-plugins` if available). Then clean up: remove the `inflight.tsv` line, close the agent's
pane (`dewterm __tmux kill-pane -t <pane>`, only a pane recorded there), and offer
`git -C "$REPO" worktree remove <worktree>` and deleting the merged local branch. Mark any
lesson it fixed `status: coded (<PR>)`.

If the merge has not landed yet, say so and stop; do not update to a pre-merge version.

## L. Record a lesson

Append to `lessons.md` using the format in its header comment: what happened, the rule that
prevents it, where in `plugins/orchestrator` it will live, `status: open`. Then run steps 2 to 3
for it so the lesson becomes code. A lesson stays `open` until its PR is merged and updated;
`status` lists the open ones, and any session start that reads them should treat open lessons as
backlog.

## Rules

- Never push, open or update a PR, or merge without the user's `gcpr` or equally explicit
  instruction. Never add Claude attribution to commits or PR text.
- Never edit `REPO`'s own checkout; work only in worktrees this skill created.
- Only kill panes recorded in `inflight.tsv`.
- Never write project-specific rules into the orchestrator plugin; if a rule only applies to one
  project, it belongs in that project's `.orchestrator/playbook.md`, which the user owns.
- One improvement per agent. Two ideas are two tasks with two branches.
- Do not store anything in the current project; all state is in the config directory.
