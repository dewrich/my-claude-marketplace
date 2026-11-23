# my-claude-marketplace

One local marketplace for everything personal that extends Claude Code on this machine:
plugins (skills, agents, hooks), mods (UI), and slash commands. Separate from the work
marketplace and from the managed `dewrich-mods` entry.

## Layout

```
.claude-plugin/marketplace.json   the catalog: one entry per plugin
plugins/<name>/                   each plugin: .claude-plugin/plugin.json + skills/ agents/ hooks/ commands/
```

Every shipped thing is a plugin under `plugins/`, because a marketplace only lists plugins. A mod
is a plugin whose `hooks/register.tsx` draws UI; a skill or slash command is a plugin with
`skills/` or `commands/`.

## Plugins

| Plugin | Kind | Status |
|---|---|---|
| `orchestrator` | skill | live |
| `promote-claude-way` | skill | live |
| `improve-orchestrator` | skill | live |
| `fix-ci` | skill | live |
| `dewrich-commands` | slash commands: gitpb, gmgp, qlty-check, wp | live |

## Adding one

1. Create `plugins/<name>/.claude-plugin/plugin.json` and its content.
2. Add an entry to `.claude-plugin/marketplace.json`.
3. `claude plugin validate .`, then enable `<name>@my-claude-marketplace` in
   `~/.claude-home/settings.json`.
