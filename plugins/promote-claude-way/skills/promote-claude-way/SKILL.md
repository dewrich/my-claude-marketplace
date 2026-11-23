---
name: promote-claude-way
description: Promote skills, commands, plugins and mods from the personal marketplace (~/projects/go/src/github.com/dewrich/my-claude-marketplace) into the Wayleadr marketplace (~/projects/go/src/github.com/wayleadr/claude-marketplace). Inventories what is promotable, copies the chosen items, adapts them to the target's conventions (manifest fields, catalog row, README paragraph, skill-router index, no personal paths), runs the target's strict validation, and leaves a local commit on a fresh branch. Never pushes. Use when the user types /promote-claude-way or asks to share a personal skill, command, plugin or mod with the Wayleadr marketplace.
---

# promote-claude-way: personal marketplace to the Wayleadr marketplace

```
SRC = ~/projects/go/src/github.com/dewrich/my-claude-marketplace     (personal, source of truth for the item)
DST = ~/projects/go/src/github.com/wayleadr/claude-marketplace       (shared, company-owned catalog `wayleadr-tools`)
```

`/promote-claude-way` copies, it never moves: `SRC` is left unchanged. Everything lands in `DST`
as a local commit; the user types `gcpr` to push and open the PR.

Usage:

- `/promote-claude-way` : list what is promotable and ask which.
- `/promote-claude-way <name> [<name>...]` : promote those plugins, or skills/commands/mods found inside plugins.
- `/promote-claude-way --dry-run <name>` : do steps 0 to 4 and show the plan and diff; write nothing to `DST`.

## 0. Preconditions

Stop and tell the user if any fails.

```sh
SRC=~/projects/go/src/github.com/dewrich/my-claude-marketplace
DST=~/projects/go/src/github.com/wayleadr/claude-marketplace
test -f "$SRC/.claude-plugin/marketplace.json" && test -f "$DST/.claude-plugin/marketplace.json"
git -C "$DST" status --porcelain      # must show no changes to tracked files; untracked .claude/settings.json is the user's, leave it
git -C "$DST" fetch origin
```

Account rule (user's global instructions): the Claude account `dewrich@gmail.com` may use both
repos. `DST` is company-owned (`Wayleadr/claude-marketplace`): before any `gh` call, check
`gh auth status` and `gh repo view Wayleadr/claude-marketplace --json viewerPermission`. If the
active GitHub user cannot see or write it, run `gh auth switch --user <user>` for the user that
can (expect `dewleadr`), or ask. Local work in steps 1 to 6 needs no GitHub access.

Never read or copy anything from `DST`'s untracked `.claude/settings.json`.

## 1. Inventory

Read `SRC/.claude-plugin/marketplace.json`. For each listed plugin, find its parts:

- **plugin**: `plugins/<n>/.claude-plugin/plugin.json`
- **skill**: `skills/<s>/SKILL.md`
- **command**: `commands/<c>.md`
- **agent**: `agents/*.md`
- **hook**: `hooks/hooks.json`
- **mod**: a plugin with `hooks/register.tsx` (draws Claude UI)

Mark each plugin `new` (no `plugins/<n>` in `DST`), `changed` (exists; compare versions and
`git diff --no-index`), or `same`. Print one table: name, kind, parts, status. A `same` item is
skipped. A request for a loose skill or command (not a whole plugin) needs a home: `DST` lists
only plugins, so ask which plugin it joins, or default to a new plugin named after it.

## 2. Gate each item

Ask once, before copying, about anything that makes an item a poor fit for a shared company
catalog. Do not copy these silently:

- Depends on a personal tool or setup: dewterm panes, `~/.claude-home`, personal marketplace names,
  personal accounts or paths. It may still be promotable if made generic; say what would change.
- Mods and hooks: they run code or change the UI for every user who enables them. Confirm, and
  point out the `DST` rule that these are personal-workflow plugins enabled in user settings.
- Anything that pushes, merges, or writes to external systems: confirm it asks before acting.
- A `changed` plugin overwrites `DST`'s copy: show the diff and confirm; never overwrite a plugin
  whose `DST` history has commits that are not from this promotion without saying so.

## 3. Copy and adapt

Work on a fresh branch in `DST` off its default branch:

```sh
git -C "$DST" switch -c promote/<slug> origin/main    # <slug>: the plugin name, or a short joined list
```

Copy with `cp -R "$SRC/plugins/<n>" "$DST/plugins/<n>"` (exclude `.git`, `node_modules`,
`__pycache__`, `.DS_Store`). Then adapt to `DST`'s conventions, read from a sibling plugin such
as `plugins/bugfix` rather than from memory:

1. **Manifest** `plugin.json`: keep `name`, `version`, `description`; add `displayName`,
   `author: {"name": "Wayleadr Platform"}`, `repository: "https://github.com/Wayleadr/claude-marketplace"`,
   `keywords`, and **`defaultEnabled: false`**.
2. **Catalog** `.claude-plugin/marketplace.json`: append an entry with `name`, `description`
   (same text as the manifest), `category` (`development`, `operations`, `productivity` or
   `documentation`) and `source: "./plugins/<n>"`.
3. **README.md** (`DST` root): add a catalog table row (`Version`, `Default: disabled`, one line)
   and a short paragraph in the same voice as its neighbours; mention user-settings scope for
   personal-workflow plugins. Add a `plugins/<n>/README.md` in the style of `plugins/bugfix`.
4. **Descriptions**: `check-structure.py --strict` warns above 400 characters for a skill
   description (always-on context cost). Tighten any longer.
5. **Scrub** for things that must not reach a shared repo, with `grep -rnE` over the copied
   plugin: `/Users/`, `~/.claude-home`, `drichard`, `dewrich`, `gmail`, `dewleadr`,
   `my-claude-marketplace`, `.orchestrator`, tokens, keys, emails. Replace with generic or
   `DST` equivalents (`wayleadr-tools`), or ask. Plugin names referenced as
   `<plugin>@my-claude-marketplace` become `<plugin>@wayleadr-tools`.
6. **Skill-router index**: `DST` ships `plugins/skill-router/index.json`, and CI fails when stale.
   Run `python3 plugins/skill-router/scripts/build_index.py` in `DST` after the catalog edit.
7. **Skill-vet**: CI scans every skill for exfiltration, injection and destructive commands. If
   the plugin legitimately trips it (for example `rm -rf` in a cleanup step), do not weaken
   the scan; list the exact finding and ask before touching `.skillvet-allowlist.yml`.
8. If the plugin ships executable code with logic, add or carry its tests and a CI line in
   `.github/workflows/validate.yml`, as `thoropass` and `ticket-standards` do.

## 4. Validate

In `DST`:

```sh
sh scripts/validate.sh --strict
python3 plugins/skill-router/scripts/build_index.py --check
```

plus any test commands for plugins with code. Fix and rerun until green; report the final lines.
If a failure is in `DST`'s existing files and not in what was just added, say so and stop rather
than editing unrelated plugins. With `--dry-run`, stop here after printing the plan and
`git -C "$DST" diff --stat`, then `git -C "$DST" switch -` and delete the scratch branch.

## 5. Commit locally

`git -C "$DST" add` only the files this promotion touched (plugin directory, `marketplace.json`,
`README.md`, `index.json`, allowlist if approved). Do not add `.claude/settings.json`. Commit with
a plain message following `DST`'s Git workflow (`standards-core`): short subject, a body listing
what was promoted and what was adapted. No Claude attribution. The pre-commit hook may run
`validate.sh --strict` on the index; let it, and do not use `--no-verify`.

## 6. Hand off

Print: branch, commit, plugins promoted (with version), adaptations made, items skipped and why,
and anything the reviewer at Wayleadr must decide (scope, `category`, personal-workflow note).
Then stop. Pushing and the PR need the user's `gcpr`: when typed, push the branch and open a new
PR against `DST`'s default branch as the GitHub user that can write to `Wayleadr/claude-marketplace`;
confirm that user with `gh auth status` first. After it merges, the personal copy in `SRC` stays;
tell the user which `DST` version it matches so later `changed` runs compare cleanly.

## Rules

- Copy, never move: do not edit or delete anything in `SRC`.
- Never push, open or update a PR, or merge without `gcpr` or an equally explicit instruction.
  Never add Claude attribution to commits or PR text.
- Never modify `DST` files unrelated to the promotion, and never edit other teams' plugins.
- Never commit secrets, personal paths, personal emails or account names to `DST`.
- Never skip or weaken `DST`'s validation (`--no-verify`, allowlist edits without asking).
- Everything promoted ships `defaultEnabled: false`.
- One branch and one PR per promotion; do not bundle unrelated plugins unless the user named them together.
