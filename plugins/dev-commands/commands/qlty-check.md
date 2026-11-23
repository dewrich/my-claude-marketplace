---
description: Run qlty locally the way the qlty Cloud PR check runs it, and fix what it reports before pushing
argument-hint: "[--all | <path>]"
allowed-tools: [Read, Edit, Bash, Grep, Glob]
---

Reproduce the `qlty check` that the qlty Cloud GitHub App posts on the PR, before
pushing. The point is that local and CI agree — so run the same binary against
the same config, scoped to the same diff.

## 1. Confirm the toolchain

```bash
command -v qlty || ls ~/.qlty/bin/qlty
```

If neither exists, qlty is not installed and nothing below is meaningful. Say so
and offer the installer — **do not run it without confirmation**, it pipes a
remote script to a shell:

```bash
curl https://qlty.sh | bash
```

It installs to `~/.qlty/bin`. If that is not on `PATH`, invoke it by full path
rather than editing the user's shell config.

## 2. Confirm the config that CI will use

```bash
ls .qlty/qlty.toml
```

`.qlty/qlty.toml` is read by **both** the CLI and qlty Cloud, so it is the only
thing that makes a local run predict the PR check.

If it is missing, the CLI does not fall back — it exits with
`Qlty must be set up in this repository. Try: qlty init` and runs nothing. qlty
Cloud still analyzes the PR on its own defaults, so the check keeps reporting
while local verification is impossible. Report that and stop. Do not run
`qlty init` unprompted: it writes a committed, repo-wide config that is a team
decision, not a side effect of a lint run.

## 3. Run it, diff-scoped

Scope to the same commits the PR contains. Resolve the base branch rather than
assuming `main` — this repo family uses `master`:

```bash
BASE=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo master)
qlty check --upstream "origin/$BASE"
qlty smells --upstream "origin/$BASE"
```

With `$ARGUMENTS` given, pass it through instead — `--all` for the whole
codebase, or a path to narrow to one area.

Other flags worth reaching for: `--sample <N>` for a fast look, `--filter
<plugin>` to isolate one linter, `--level` to raise the reporting floor from its
`note` default, and `--fail-level` (defaults to `fmt`) to match what CI treats
as blocking. Prefer `--no-fix` on the first pass so you see findings before
anything rewrites them.

## 4. Fix and report

- Fix what `check` reports. `qlty fmt` handles formatting-class findings, but
  review its diff — do not commit auto-formatting blind.
- `smells` findings (duplication, complexity) are advisory. Fix them or state
  plainly why one is being left.
- Silence a finding in `.qlty/qlty.toml` via a `[[triage]]` or `[[exclude]]`
  entry, never by deleting the check. Prefer fixing the code.

Report each command's real outcome, including anything left unfixed. A local
pass is evidence the PR check will pass, not a guarantee — qlty Cloud also
applies its own Mode setting for whether findings block the merge.

## Related

`/lint` (rails-standards plugin) runs Rubocop and Pronto alongside qlty smells —
that is the broader Ruby quality pass. This command is narrower on purpose: it
mirrors the one check that gates the PR.
