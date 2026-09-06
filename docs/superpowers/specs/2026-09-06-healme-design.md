# HealMe — Design Spec

*Date: 2026-09-06 · Status: approved design, not yet implemented*
*Target: World of Warcraft Retail, Midnight 12.1.0 (`Interface: 120007, 120100`)*

---

## 1. What this is

HealMe is a click-casting addon: it lets a healer cast spells by clicking unit
frames with the mouse, instead of targeting a player and then pressing a key.
Mouse button + modifier combinations (and mouse wheel) map to spells, so
`shift+right-click` on a raid frame casts Regrowth on that person.

It owns a binding table and applies it to unit frames. It draws nothing.

## 2. Why it exists

Retail has shipped native click-casting since 10.1.5 (`C_ClickBindings`,
Options → Gameplay → Combat). HealMe is only worth building for what native
cannot do:

| Capability | Native | HealMe |
|---|---|---|
| Mouse button + modifier binds | yes | yes |
| Mouse wheel binds | no | yes |
| Per-specialization binding sets | no | yes |
| Conditional binds (friendly / hostile / dead / out-of-combat) | no | yes |
| Third-party unit frames (Grid2, ElvUI, Cell, SUF) | partial | yes |
| Export / import / version-control your binds | no | yes |

HealMe replaces native click-casting rather than supplementing it, so there is
one place to look when a bind misbehaves.

## 3. Hard constraints

These are properties of the game, not choices. Everything below is designed
around them.

### 3.1 Secure execution

Casting a spell is a protected action. Addon code cannot decide who to heal and
then cast. The only sanctioned path is a `SecureActionButtonTemplate` frame
whose attributes were set by insecure code **outside of combat**, triggered by a
genuine hardware click. HealMe's entire job is putting the right attributes on
the right frames before combat starts.

### 3.2 Combat lockdown

Insecure code cannot set attributes on, show, hide, or reparent a protected
frame while the player is in combat. New frames appearing mid-combat (someone
joins the raid, a frame addon rebuilds its layout) must be queued and wired up
on `PLAYER_REGEN_ENABLED`.

The one legal exception is a **secure handler snippet**: code stored in a frame
attribute and executed by Blizzard inside the restricted environment. Snippets
may set attributes and key bindings during combat. HealMe uses this for two
things only: mid-combat frame registration, and mouse wheel bindings.

### 3.3 Secret Values (Midnight 12.0+)

Combat-state data is wrapped in opaque secret values. Addon code may store,
pass, and display them, but **may not compare them, do arithmetic on them,
index them, use them as table keys, or take their length** — all raise Lua
errors. `COMBAT_LOG_EVENT_UNFILTERED` cannot be registered at all. Aura reading
for logic was tightened further in 12.1. Direction of travel is tighter every
patch.

Consequences for HealMe:

- **Health- and aura-based conditions are impossible.** "Cast when they are
  below 40%" and "only if they have a dispellable magic debuff" cannot be built
  by any addon. They are out of scope permanently, not deferred.
- Conditions must be expressible in **WoW macro syntax**, so that Blizzard's own
  secure code evaluates them at click time. This is the central design decision
  (§6).
- HealMe never reads combat state, so it is otherwise unaffected. Click-casting
  is one of the few combat-adjacent addon categories Midnight did not remove.

## 4. Scope

**In scope**

- Bindings on mouse buttons 1–5 with any combination of shift / ctrl / alt.
- Bindings on mouse wheel up / down with the same modifiers.
- Actions: cast a spell, target, set focus, open the unit context menu, run a
  macro.
- Macro-expressible conditions: friendly, hostile, dead, alive, in combat, out
  of combat.
- An **"also target"** setting: when a bind casts, the player's target switches
  to the clicked unit as well, so action-bar follow-ups land on the same person.
- Binding sets that swap automatically with specialization.
- Blizzard party/raid/player/target/focus frames, plus any addon frame that
  registers through the community `ClickCastFrames` protocol.
- An in-game options panel to create, edit, and delete bindings.
- Export and import of a binding set as a shareable string.

**Out of scope**

- Drawing any unit frames. HealMe rides frames that already exist.
- Health-, aura-, or combat-log-driven conditions (§3.3 — impossible).
- Hover-plus-keyboard bindings. Those belong in Blizzard's keybind UI.
- Bindings that fire without a frame under the cursor.
- Healing decisions of any kind. HealMe wires buttons; the player aims them.
- Classic / Cataclysm / MoP flavors.

## 5. Repository layout

The addon lives in a subfolder so that docs, tests, and CI stay out of what
users install. The release workflow zips that one folder.

```
D:\healme\
  HealMe\                       <- this folder is what ships
    HealMe.toc
    Core.lua
    Registry.lua
    Compiler.lua
    Secure.lua
    Bindings.lua
    Options.lua
    Serialize.lua
    Libs\                       <- vendored, committed
    Media\icon.tga
  .github\workflows\release-addon.yml
  test\                         <- desktop Lua tests
  docs\
  LICENSE
  .gitignore
  .luarc.json
  .luacheckrc
```

TOC header:

```
## Interface: 120007, 120100
## Title: HealMe
## Notes: Mouse click-casting for healers.
## Author: <handle>
## Version: 0.1.0
## SavedVariables: HealMeDB
## IconTexture: Interface\AddOns\HealMe\Media\icon
## AddonCompartmentFunc: HealMe_OnAddonCompartmentClick
```

Anything declaring an `Interface` below `120000` does not load at all under
Midnight. Vendored libraries (LibStub, CallbackHandler, AceAddon, AceDB,
AceEvent, AceConsole, AceConfig, AceGUI, AceDBOptions, AceSerializer,
LibDeflate) are committed rather than pulled as packager externals, matching the
zip-the-folder release workflow.

## 6. The central design decision: conditions compile to macro text

A binding with conditions compiles to `type="macro"` with macro text that
carries the condition, e.g.

```
/cast [@mouseover,help,nodead] Rejuvenation
```

Blizzard's secure code evaluates `help` and `nodead` at click time, inside the
box HealMe cannot see into. Nothing needs rewriting when the target's state
changes, so there is no combat-lockdown problem and no restricted-environment
state machine.

The rejected alternative — watching events, deciding in Lua which binding is
live, and rewriting attributes — is not merely harder. Under Secret Values the
inputs it would need are unreadable (§3.3), so it cannot be built.

Cost accepted: macro text is capped at 255 characters (compiled binds run ~60),
and conditions are limited to what macro syntax offers.

## 7. Unit resolution: `mouseover` for every frame

Hovering a unit frame sets the player's `mouseover` unit. Therefore every
binding compiles to the literal unit token `"mouseover"`, and **the same
attribute set is applied unchanged to every registered frame**. No per-frame
unit wiring, no recompilation when a frame's unit changes, no work at all when
the raid reshuffles.

This applies to all five action kinds: `type="spell"` and `type="macro"` use
`@mouseover` / `unit="mouseover"`, and `type="target"`, `type="focus"`,
`type="menu"` read the button's `unit` attribute, which is likewise the literal
string `"mouseover"`.

*Risk:* this depends on the hovered frame actually setting the mouseover unit,
which requires it to be a real unit frame. Blizzard frames and every frame that
registers via `ClickCastFrames` are unit frames, so this should hold
universally. **Fallback if it does not:** `Registry` already reads each frame's
own `unit` attribute at registration time, so `Secure` can fall back to
per-frame unit attributes for the offending frame. This is the first thing to
verify in-game.

## 8. Modules

Each module has one job and a stated dependency set. `Compiler.lua` calls no WoW
API at all, which is what makes the riskiest logic testable on the desktop.

| Module | Responsibility | Depends on |
|---|---|---|
| `Core.lua` | AceAddon lifecycle, slash command, addon compartment entry, wiring the other modules together | Ace3 |
| `Bindings.lua` | The binding table: create, edit, delete, validate, per-spec profiles. Knows nothing about frames or secure code. | AceDB |
| `Compiler.lua` | Pure: one binding record in, a list of `(attribute, value)` pairs out. No WoW API. | nothing |
| `Registry.lua` | Frame discovery. Hooks Blizzard compact raid/party/player/target/focus frames; owns the `ClickCastFrames` global table and the `ClickCastHeader` secure header so third-party addons self-register. Reads each frame's `unit` attribute for the §7 fallback. | — |
| `Secure.lua` | The only module that touches secure frames. Owns the secure header and its snippets, applies compiled attributes, manages the combat queue, manages wheel bindings. | Compiler, Registry |
| `Options.lua` | AceConfig options table plus a custom combo-capture widget. | Bindings |
| `Serialize.lua` | Export/import strings. | AceSerializer, LibDeflate |

## 9. Data model

A binding record, stored in AceDB under the active profile:

```lua
{
  id         = "b7",                     -- stable unique key
  enabled    = true,
  key = {
    button   = "BUTTON1".."BUTTON5" | "WHEELUP" | "WHEELDOWN",
    shift    = false,
    ctrl     = true,
    alt      = false,
  },
  action = {
    kind      = "spell" | "macro" | "target" | "focus" | "menu",
    spell     = "Rejuvenation",           -- kind == "spell"
    macrotext = "/cast [@mouseover] ...", -- kind == "macro", author-supplied
  },
  conditions = {                         -- all optional; nil means unconstrained
    unitFilter = "help" | "harm" | nil,  -- friendly only / hostile only
    aliveOnly  = true | nil,             -- -> nodead
    deadOnly   = true | nil,             -- -> dead
    combat     = true | false | nil,     -- -> combat / nocombat
  },
}
```

Profile-level settings, stored alongside the binding list:

```lua
settings = {
  alsoTarget = false,   -- see §10; default off, one click to flip
}
```

`alsoTarget` is a profile setting rather than a per-binding field. It is the
kind of thing a player wants on or off as a habit, not per bind, and keeping it
out of the record means the binding list stays readable. §19 records the seam if
per-binding control is ever wanted.

Validation rules enforced by `Bindings.lua` before a record is accepted:

- `aliveOnly` and `deadOnly` are mutually exclusive.
- `kind == "spell"` requires `C_Spell.GetSpellInfo(spell)` to return a result.
- `kind == "macro"` requires non-empty `macrotext` of at most 255 characters.
- No two enabled bindings in a profile may share the same `key` (same button
  and identical modifier set). The UI surfaces the conflict rather than
  silently overwriting.

## 10. Compilation

`Compiler.Compile(binding) -> { {name, value}, ... }`

**Attribute name** is `<modifier prefix><attribute><button suffix>`, e.g.
`ctrl-type1`, `alt-ctrl-shift-spell2`. Modifier prefix order is fixed by
Blizzard's `SecureButton_GetModifierPrefix` and must be emitted in that exact
order — believed to be `alt-`, `ctrl-`, `shift-`, **to be confirmed against
`Gethe/wow-ui-source` before writing the compiler** (§16). Button suffixes are
`1`–`5` for the five mouse buttons; wheel bindings use the literal suffixes
`wheelup` / `wheeldown` supplied by `SetBindingClick` (§12).

**Attribute values**, by action kind:

- No conditions, `kind == "spell"` → `type=spell`, `spell=<name>`,
  `unit=mouseover`. Preferred over macro text where possible: no 255-character
  ceiling, marginally cheaper at click time, and Blizzard's native spell-error
  handling applies.
- Conditions present, `kind == "spell"` → `type=macro`,
  `macrotext=/cast [@mouseover,<conds>] <spell>`.
- `kind == "macro"` → `type=macro`, `macrotext=<author's text>` verbatim.
  Conditions are the author's problem; HealMe does not rewrite their macro.
- `kind == "target" | "focus" | "menu"` → `type=<kind>`, `unit=mouseover`.
  Conditions, if any, wrap it as `type=macro` with
  `/target [@mouseover,<conds>]` and equivalents.

**"Also target."** When the profile setting `alsoTarget` is on, a binding of
kind `spell` compiles to `type=macro` regardless of whether it carries
conditions, with a target line appended:

```
/cast [@mouseover,help,nodead] Regrowth
/target [@mouseover,help,nodead]
```

Rules:

- **Cast line first.** If the target line ever fails, the heal has already gone
  out. The reverse order risks retargeting without healing.
- **The same conditions guard both lines**, so a bind that declines to fire also
  declines to retarget. Compiling the condition string once and emitting it
  twice keeps that guaranteed rather than merely intended.
- **`kind == "macro"` is exempt.** The author's macro text is theirs; if they
  want a `/target` line they write one. HealMe does not rewrite author macros
  (consistent with the rule above).
- **`kind == "target" | "focus" | "menu"` are unaffected.** `target` already
  targets, and silently retargeting off a focus or a context-menu click would be
  a surprise.

The only cost is that affected binds lose the `type=spell` path and its modest
advantages listed above. That is why the setting defaults off.

**Condition ordering** is fixed — `unitFilter`, then `nodead`/`dead`, then
`combat`/`nocombat` — so that identical bindings always compile to
byte-identical macro text. That makes the compiler's output directly assertable
in tests.

## 11. Frame registration

Two sources, one sink.

1. **Blizzard frames.** Hook the compact raid/party frame factory and the
   player/target/focus frames, handing each frame to `Secure` as it appears.
2. **The community protocol.** `Registry` creates the global `ClickCastFrames`
   table with a metatable whose `__newindex` fires on write, and the global
   `ClickCastHeader` secure header. Third-party unit frame addons already write
   to these (the convention Clique established), so Grid2, ElvUI, Cell, and
   Shadowed Unit Frames register with HealMe without either side knowing about
   the other.

Registration during combat goes through the header's secure snippet, which may
legally set attributes on an already-secure frame. Registration out of combat
takes the direct path. Every third-party interaction is wrapped in `pcall` so a
broken frame addon cannot take HealMe down with it.

**The exact `ClickCastHeader` snippet protocol will be read from Clique's source
and matched, not guessed** — third-party compatibility depends on byte-level
agreement (§16).

## 12. Mouse wheel

The wheel is not a click, so it cannot be bound by attributes. `Secure` creates
one hidden `SecureActionButtonTemplate` proxy button carrying the wheel
bindings' attributes, and registers each frame with a
`SecureHandlerEnterLeaveTemplate` header:

- `_onenter` snippet → `self:SetBindingClick(true, "MOUSEWHEELUP", <proxy>, "wheelup")`
  and the same for `MOUSEWHEELDOWN` / `wheeldown`, plus modifier variants.
- `_onleave` snippet → `self:ClearBindings()`.

`SetBindingClick` inside a restricted snippet is the only way to bind keys
during combat; the insecure `SetOverrideBinding*` APIs are blocked in combat.

Because wheel binds resolve through `@mouseover` like everything else, the proxy
button is a **single global button**, not one per frame.

## 13. Options panel

An AceConfig options table registered through AceConfigDialog, which itself
registers with the modern `Settings` API (the removed
`InterfaceOptions_AddCategory` is not used anywhere). Reachable from the addon
compartment and from `/healme`.

Contents:

- An **"Also target"** checkbox (§10): when a bind casts, switch your target to
  the clicked unit so action-bar follow-ups land on the same person. Applies to
  the whole profile.
- A list of bindings in the active profile, each row showing its combo, its
  action, and its conditions.
- An editor for the selected binding: action kind, spell picker or macro text
  box, condition checkboxes.
- A **combo capture control**. AceConfig has no widget for "press the mouse
  combination you want," so this is a small custom AceGUI widget: a button that,
  once armed, captures the next click and its modifier state and writes them
  into the binding. This is the only hand-built UI in the addon.
- Profile management (AceDBOptions) and import/export.

## 14. Profiles

AceDB profiles, with automatic switching on `PLAYER_SPECIALIZATION_CHANGED`
between profiles named for the character's specializations. A spec swap in
combat queues the reapplication for `PLAYER_REGEN_ENABLED` like any other
attribute write.

## 15. Error handling

Defensive throughout; the failure mode to avoid is an error propagating into
Blizzard's call stack, which taints the UI and produces "action blocked" errors
mid-raid.

- Every spell validated against `C_Spell.GetSpellInfo` before entering the
  binding table. Invalid bindings are flagged in the UI, disabled, and never
  compiled.
- Every secure-frame write gated on `InCombatLockdown()`, with the
  queue-and-flush fallback.
- Every third-party registration wrapped in `pcall`.
- Frames are held in a weak-keyed table so a frame addon's teardown does not
  leak.
- No `OnUpdate` handlers anywhere. All work is event-driven.
- No retry or circuit-breaker machinery: there is no network and nothing
  transient to retry against. Combat lockdown is the only "try later" case and
  the queue handles it.

## 16. Things to confirm before writing the relevant code

These are known unknowns, each attached to the module that depends on it. Each
is answered by reading a source, not by guessing.

1. **Modifier prefix order** in `SecureButton_GetModifierPrefix`, and the button
   suffix mapping for mouse buttons 4 and 5. Source: `Gethe/wow-ui-source`.
   Blocks `Compiler.lua`.
2. **The `ClickCastHeader` snippet protocol** — exact attribute names and
   snippet bodies. Source: Clique's published source. Blocks `Registry.lua`.
3. **Whether `mouseover` resolves reliably on every registered frame** (§7).
   Verified in-game; the per-frame `unit` fallback is already designed.
4. **Whether a desktop Lua 5.1 interpreter is available** on the dev machine for
   the compiler tests. If not, the tests ship anyway and run in CI.

## 17. Testing

Pure logic gets automated tests. Everything touching the WoW API gets a written
manual checklist, because a mock WoW API costs more to maintain than the bugs it
would catch.

**Automated** (`test/`, plain Lua 5.1, a hand-rolled assert harness — no test
framework dependency):

- `Compiler.Compile` output for every action kind, every condition combination,
  and every modifier permutation, asserted as exact attribute name/value pairs.
- `alsoTarget` on and off across all five action kinds: that `spell` gains the
  target line with identical conditions on both lines and the cast line first,
  and that `macro`, `target`, `focus`, and `menu` are left untouched.
- `Bindings` validation rules: mutual exclusion, duplicate key detection, macro
  length, spell validation via an injected stub.
- Round-trip: `Serialize.Export(profile)` → `Import` → identical table.

**Manual checklist** (`docs/manual-test-checklist.md`), run in-game:

- Bind and fire each action kind out of combat, then in combat.
- Join a group mid-combat; confirm new frames wire up on combat exit.
- Change specialization in combat; confirm the profile swaps on combat exit.
- Enable a third-party frame addon; confirm its frames register.
- Wheel binds fire while hovering and do not leak outside the frame.
- Conditional binds: a friendly-only bind does nothing on a hostile target, and
  a `nodead` bind does nothing on a corpse.
- With "also target" on: a heal click both lands and switches the target, in
  combat and out; a bind whose conditions fail changes neither.
- Force each restriction scope with the `secret*RestrictionsForced` CVars and
  confirm no errors, including on the addon-author test dummies near The
  MOTHERLODE!! entrance.
- Run a full Mythic+ key with BugSack loaded and confirm a clean error log.

**Static analysis:** `luacheck` with `std = "lua51"` and the BigWigs WoW globals
list, plus `.luarc.json` pinning Lua 5.1 for the Ketho VS Code API extension.

## 18. Packaging and release

Tag-driven GitHub Actions, adapted from the workflow already proven in the
`wow-addons` repo: on a `v*` tag, verify the TOC `## Version` matches the tag,
zip the `HealMe/` folder, attach it to a GitHub release, and optionally upload
to CurseForge when `CF_PROJECT_ID` is configured. WowUp installs directly from a
GitHub Releases URL provided the zip contains the addon folder at its root,
which this layout satisfies.

Blizzard's addon policy applies: free, source visible, no obfuscation, no ads,
no donation solicitation.

## 19. Deliberately deferred

Not built now, with a clear seam if ever wanted:

- Per-frame-type binding overrides (different binds on the target frame than on
  raid frames). The binding record would gain a frame-type filter and `Secure`
  would apply per-group attribute sets; nothing else changes.
- A HealMe-drawn healing grid. It would consume `Secure` exactly as Blizzard's
  frames do, via `ClickCastFrames`.
- Blizzard-keybind-style bindings that fire without a frame under the cursor.
- Per-binding control of "also target" (§10). The record would gain an
  `alsoTarget` tri-state — inherit / on / off — and the compiler would read the
  effective value instead of the profile setting. One field and one line;
  nothing else moves.

Not built, ever, unless Blizzard reverses course: any condition requiring health
values, aura state, or combat log data (§3.3).
