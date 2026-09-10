# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this is

HealMe is a World of Warcraft Retail addon (Midnight 12.1+) for click-casting:
bind spells to mouse buttons and the wheel, then cast by clicking unit frames.
Plain Lua 5.1 against the Blizzard API, **no libraries** (Ace3 was removed on
purpose; do not reintroduce vendored libs). The design spec at
`docs/superpowers/specs/2026-09-06-healme-design.md` is the authority on why
things are the way they are; update it when behaviour changes.

## Commands

```
lua5.1 test/run.lua      # unit tests (CI uses lua5.1)
luacheck HealMe test     # lint, config in .luacheckrc
```

There is no Lua interpreter on this Windows dev box and Docker is usually not
running. Run the tests through the `lupa` Python package instead:

```
python -c "import lupa.lua51 as L; lua=L.LuaRuntime(unpack_returned_tuples=True); print(lua.execute(open('test/run.lua').read().replace('os.exit(harness.run())','return harness.run()')))"
```

luacheck runs on this box from PowerShell (Lua 5.4 under
`~/AppData/Local/Programs/Lua/bin`, luacheck in `~/.luarocks` with a tiny
`lfs.lua` shim there since no C compiler exists):

```
$env:PATH = "$HOME\AppData\Local\Programs\Lua\bin;$env:PATH"
$env:LUA_PATH = "$HOME\.luarocks\share\lua\5.4\?.lua;$HOME\.luarocks\share\lua\5.4\?\init.lua;;"
lua "$HOME\.luarocks\share\lua\5.4\luacheck\main.lua" HealMe test --no-color --no-cache
```

Keep it at zero warnings. Unused `self` is silenced by config; a Blizzard
table we add entries to belongs in `globals`, one we only read in
`read_globals`.

The Lua language server (lua-language-server 3.19, under
`~/AppData/Local/Programs/lua-language-server`, launcher in `~/.local/bin`)
backs the lua-lsp plugin and has a batch checker; `.luarc.json` carries the
WoW globals it cannot see. Keep this at zero too:

```
lua-language-server --check D:\healme --checklevel=Warning --check_out_path=<file.json>
```

A new WoW global goes in both `.luacheckrc` and `.luarc.json`.

Run a single suite by editing the `suites` list in `test/run.lua` temporarily,
or `dofile` one `test/test_*.lua` file with the harness and loaded modules.
Add any new WoW global you use to `read_globals` in `.luacheckrc`.

Frames cannot run outside the client. Anything touching frames or the secure
API is verified in-game with `docs/manual-test-checklist.md`; add a checklist
entry for every UI or secure change. A throwaway smoke test with a permissive
`CreateFrame` stub (every method a no-op) catches nil errors in the panel's
build and refresh paths before the user tests it.

Versions are calendar dates (`2026.09.07`, `.2` for a second release that
day), written only in `HealMe/HealMe.toc`; Core reads it at load. Releasing
is a TOC edit plus a matching `v2026.09.07` tag.

Commit after each change. Another agent (Codex) also commits to this repo, so
re-read files before editing.

## Architecture

Load order is `HealMe/HealMe.toc`; each module is `local _, ns = ...` and
publishes itself on the shared `ns` table. On the desktop runner each module
loads with its own `ns`, so modules that need each other's constants keep a
local fallback copy (see `Serialize` and `Secure` for the frame-class order).

**The central decision:** conditions compile to WoW macro text and every
binding resolves the unit as the literal `mouseover`. Blizzard's secure code
evaluates conditions at click time; HealMe never reads combat state (Secret
Values make health/aura logic impossible). The same compiled attribute set is
written to every registered frame, filtered only by the binding's frame scope.

Data flow: `Bindings` (record validation, conflict detection, `frames` scope)
→ `Compiler` (record → `{name, value}` secure attributes, condition strings)
→ `Secure` (writes attributes to frames, queues under combat lockdown, wheel
bindings via a hidden proxy button and secure handler snippets)
← `Registry` (frame discovery: Blizzard frames, compact raid/party via
`hooksecurefunc`, third-party via the `ClickCastFrames`/`ClickCastHeader`
Clique protocol; classifies each frame by global name into
player/target/focus/pet/party/raid/other).

`Core` owns saved variables (`HealMeDB`: `profiles`, `rules`, `ui`), profile
selection and automatic switching (spec change and `GROUP_ROSTER_UPDATE`,
resolved by the pure `Core.ResolveProfile`), change notification
(`NotifyChanged` → `Secure:ApplyAll` + listeners), and the `/healme` slash
command. `Serialize` is the export/import codec: a bespoke `^`/`~` field
format with a trailing `frames` field that older strings simply lack.
`Native` reads Blizzard's own click-casting profile and warns, because native
binds beside HealMe rather than under it and ignores frame scopes.

`Bar` is the cooldown bar: a container with twelve `SecureActionButtonTemplate`
slots, unit-less `type=spell` casts, anchored to whichever Blizzard group frame
is on screen (`Bar.AnchorTarget`, pure). Its spell list is `profile.bar`, its
side and size live in `HealMeDB.ui.bar`, and the export codec carries it as
`c^<spell>` records. `Bar:Apply` is the one entry point, called from
`Core:ApplyAll`; it queues under combat lockdown and flushes on
`PLAYER_REGEN_ENABLED` from its own event frame. Cooldown display goes through
`C_Spell.GetSpellCooldownDuration` and `SetCooldownFromDurationObject`, never
raw numbers (see the rules below). Spec:
`docs/superpowers/specs/2026-09-09-cooldown-bar-design.md`.

**UI** (`Widgets` + `Options`) is built on Blizzard's own templates and atlases
to look like the Housing dashboard: `PortraitFrameTemplate`, `TabSystemTemplate`
top tabs, `WowStyle1DropdownTemplate`, filigree corner atlases, quest-log
header atlas. Every atlas name and anchor was taken from
github.com/Gethe/wow-ui-source (live branch); verify there, never guess. Each
constructor checks for the method or atlas it needs and falls back to a plain
control, so a renamed template costs the look, not the addon. Every editor
setter stashes the previous value and reverts on validation failure.

## Rules that are easy to break

- A new binding is created **disabled** and incomplete; `Validate` skips the
  action-completeness checks while `enabled == false`. Do not tighten that.
- Never write a secure attribute or wrap a script outside the
  `InCombatLockdown()` guard; use the queue in `Secure`.
- Destructive UI actions go through `Widgets.Confirm` (Blizzard's popup).
- Do not lowercase spell names anywhere; the client's spell lookup is
  case-sensitive.
- Cooldown and charge data from `C_Spell` are Secret Values in combat, and
  `Cooldown:SetCooldown` refuses a secret from addon code. Show a cooldown only
  through `C_Spell.GetSpellCooldownDuration` handed to
  `SetCooldownFromDurationObject`; never compare or branch on a cooldown or
  charge value in a refresh path. Blizzard's own ActionButton code passes raw
  values because it is untainted; do not copy it.
