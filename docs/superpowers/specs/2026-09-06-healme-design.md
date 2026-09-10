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

HealMe does not switch native click-casting off. Native binds through its
own secure header, beside HealMe's attributes, so a native spell binding keeps
firing on every frame whatever HealMe does, and ignores HealMe's frame scopes.
HealMe never edits that profile: `Native.lua` reads it, warns once at login
when spell, macro or pet bindings are present, shows the same on the Settings
tab, and opens Blizzard's window (`/healme native`) so the player clears them.

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
- A cooldown bar: a row of unit-less spell buttons anchored to Blizzard's raid or
  party frames, with cooldown swipes. See `2026-09-09-cooldown-bar-design.md`.

**Out of scope**

- Drawing any unit frames. HealMe rides frames that already exist.
- Health-, aura-, or combat-log-driven conditions (§3.3 — impossible).
- Hover-plus-keyboard bindings. Those belong in Blizzard's keybind UI.
- Bindings that fire without a frame under the cursor, except the cooldown bar's
  own buttons.
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
    Bar.lua
    Serialize.lua
    Native.lua
    SelfTest.lua
    Help.lua
    Widgets.lua
    Options.lua
    Minimap.lua
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
## Notes: Mouse click-casting and a raid-frame cooldown bar for healers.
## Author: <handle>
## Version: 0.1.0
## SavedVariables: HealMeDB
## IconTexture: Interface\AddOns\HealMe\Media\icon
## AddonCompartmentFunc: HealMe_OnAddonCompartmentClick
```

Anything declaring an `Interface` below `120000` does not load at all under
Midnight.

**HealMe ships no libraries.** The design originally called for the Ace3 stack,
vendored into `Libs/`. That was abandoned during implementation: the libraries
were sourced from addons already installed on the development machine, and one
of them shipped a fork that registers its GUI and config libraries under
suffixed names (`AceConfig-3.0-Z`), so `LibStub("AceConfig-3.0")` could never
resolve. Rather than re-source them, the two modules that used Ace3 were
rewritten on plain Blizzard API. Lifecycle, event dispatch, saved variables and
per-spec profiles are small enough to own outright; the options panel is built
from base frames. Nothing is vendored, so nothing can break because another
addon shipped a library under a different name.

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

A binding may carry a `frames` set naming which kinds of frame it fires on
(§13). That does not change the unit token: `Secure` still writes the same
compiled attributes, but on a frame outside the set it clears the binding's
attribute instead. `Registry` sorts each frame into one class at registration,
by its global name (player, target, focus, pet, party, raid, or other for
anything a third-party addon registers), and `Secure` stamps that class on the
frame as `healme-frame` so the wheel snippet can honour the same scope.

This applies to all five action kinds: `type="spell"` and `type="macro"` use
`@mouseover` / `unit="mouseover"`, and `type="target"`, `type="focus"`,
`type="togglemenu"` read the button's `unit` attribute, which is likewise the
literal string `"mouseover"`. Blizzard resolves that attribute through
`SecureButton_GetModifiedUnit`, which passes `mouseover` through untouched (§20).

*Risk:* this depends on the hovered frame actually setting the mouseover unit,
which requires it to be a real unit frame. Blizzard frames and every frame that
registers via `ClickCastFrames` are unit frames, so this should hold
universally. **Fallback if it does not:** a per-frame unit attribute path in
`Secure`, reading each frame's own `unit` attribute instead of the literal
`"mouseover"` token. This is a designed contingency, **not implemented**.
`Registry` does not currently read or store each frame's `unit` attribute, and
`Secure` has no per-frame code path at all — building either is deferred until
in-game testing (§16 item 1) shows it is actually needed. Speculative
combat-adjacent code that cannot be exercised on the desktop is worse than an
honest gap here.

## 8. Modules

Each module has one job and a stated dependency set. `Compiler.lua` calls no WoW
API at all, which is what makes the riskiest logic testable on the desktop.

| Module | Responsibility | Depends on |
|---|---|---|
| `Core.lua` | Lifecycle on an event frame, saved variables, per-spec profiles, slash command, addon compartment entry | none |
| `Bindings.lua` | Binding record validation, key signatures, conflict detection, import sanitising. Knows nothing about frames or secure code. | none |
| `Compiler.lua` | Pure: one binding record in, a list of `(attribute, value)` pairs out. No WoW API. | nothing |
| `Minimap.lua` | The minimap button and its account-wide position. | Options |
| `Registry.lua` | Frame discovery. Hooks Blizzard compact raid/party/player/target/focus frames; owns the `ClickCastFrames` global table and the `ClickCastHeader` secure header so third-party addons self-register. Does **not** read per-frame `unit` attributes; the §7 fallback is designed but not implemented. | — |
| `Secure.lua` | The only module that touches secure frames. Owns the secure header and its snippets, applies compiled attributes, manages the combat queue, manages wheel bindings. | Compiler, Registry |
| `Bar.lua` | The cooldown bar: secure spell slots, cooldown display, anchoring to the group frames. | Core |
| `Widgets.lua` | Constructors for the panel's controls and art, on Blizzard's own templates and atlases with plain fallbacks. | none |
| `Options.lua` | A standalone portrait window: tabs, a grouped binding list, the editor, the settings page and the share window. | Bindings, Widgets |
| `Serialize.lua` | Export/import strings, and the field-based codec that produces them. | none |

## 9. Data model

A binding record, stored in `HealMeDB.profiles[<name>]`:

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
    kind      = "spell" | "macro" | "target" | "focus" | "togglemenu",
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

The cooldown bar's spell list sits beside the bindings, so it swaps with the
profile:

```lua
bar = { "Tranquility", "Nature's Swiftness" }   -- ordered spell names, at most 12
```

Account-wide interface state lives outside the profiles in `HealMeDB.ui`:
the minimap button's angle and hidden flag, and the bar's placement,
`ui.bar = { side = "above" | "below", size = 36 }`. Where a control sits is a
habit of the interface, not of a binding set, and must not move on a spec
change. The companion spec `2026-09-09-cooldown-bar-design.md` §4 has the
bar's validation rules.

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
`ctrl-type1`, `alt-ctrl-shift-spell2`. Both halves are verified against
`Blizzard_FrameXML/SecureTemplates.lua` (§20):

- **Modifier prefix.** `SecureButton_GetModifierPrefix` builds the string by
  *prepending* shift, then ctrl, then alt, so the emitted order is always
  `alt-`, `ctrl-`, `shift-`. Emitting them in any other order silently fails to
  match.
- **Button suffix.** `SecureButton_GetButtonSuffix` returns `"1"` for
  `LeftButton`, `"2"` for `RightButton`, `"3"` for `MiddleButton`, and a
  lookup-table value for `Button4`–`Button31`, giving `"4"` and `"5"`. Any other
  button string falls through to `return "-" .. button`. **Wheel bindings
  therefore take the suffix `-wheelup` / `-wheeldown`, with a leading hyphen**,
  producing attribute names like `type-wheelup` and `shift-spell-wheeldown`.

**Attribute values**, by action kind:

- No conditions, `kind == "spell"` → `type=spell`, `spell=<name>`,
  `unit=mouseover`. Preferred over macro text where possible: no 255-character
  ceiling, marginally cheaper at click time, and Blizzard's native spell-error
  handling applies.
- Conditions present, `kind == "spell"` → `type=macro`,
  `macrotext=/cast [@mouseover,<conds>] <spell>`.
- `kind == "macro"` → `type=macro`, `macrotext=<author's text>` verbatim.
  Conditions are the author's problem; HealMe does not rewrite their macro.
- `kind == "target" | "focus" | "togglemenu"` → `type=<kind>`, `unit=mouseover`.
  Conditions, if any, wrap it as `type=macro` with
  `/target [@mouseover,<conds>]` and equivalents.

  **Use `togglemenu`, not `menu`.** `SECURE_ACTIONS.menu` dispatches to a
  `menu-function` attribute that nothing in Blizzard's codebase sets — it is a
  hook for a frame to supply its own menu, so `type="menu"` on a foreign frame
  does nothing at all. `SECURE_ACTIONS.togglemenu` derives the right unit popup
  from the resolved unit alone and works with `unit="mouseover"` (§20).

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
- **`kind == "target" | "focus" | "togglemenu"` are unaffected.** `target` already
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

The protocol is settled, matched against `Snakybo/Clicked` — Clique's
actively-maintained successor, which documents its own header as "mostly based
on Clique, mainly to ensure it will continue working with any addons that
integrate with Clique directly" (§20). Five requirements fall out of it, four of
which are easy to miss:

1. **The header** is
   `CreateFrame("Frame", "ClickCastHeader", UIParent, "SecureHandlerBaseTemplate,SecureHandlerAttributeTemplate")`,
   carrying `clickcast_register` and `clickcast_unregister` snippets. Each reads
   the `clickcast_button` attribute and re-exports it by writing an
   `export_register` / `export_unregister` attribute, which an insecure
   `HookScript("OnAttributeChanged")` picks up. That indirection is the whole
   trick: a snippet running mid-combat cannot call insecure code, so it parks
   the frame in an attribute and lets the insecure side collect it.

2. **Enable the inputs.** A frame does not report middle-click, buttons 4 and 5,
   or the wheel unless told to. Every registered frame needs
   `frame:RegisterForClicks("AnyUp")` and `frame:EnableMouseWheel(true)`. Both
   are combat-locked, so both go through the queue.

3. **Preserve a pre-existing `ClickCastFrames`.** Another addon may have
   populated the global before HealMe loads. Capture the old table, install the
   metatable, then replay every entry through registration. Skipping this loses
   every frame registered by an addon that loaded first.

4. **Shim the `Clique` global.** Many older frame addons hardcode Clique support
   rather than using `ClickCastFrames`. Define `Clique = { header = ClickCastHeader }`
   with a `Clique:UpdateRegisteredClicks(frame)` method forwarding into
   registration, wrapped in `xpcall` to `geterrorhandler()`.

5. **Refuse to co-exist.** Clique and Clicked both claim the same global header.
   If either is enabled, show a message and do not install the header. Two
   addons fighting over `ClickCastHeader` is not a state worth debugging.

## 12. Mouse wheel

The wheel is not a click, so it cannot be bound by attributes. Instead the wheel
is bound *to* a click on a hidden proxy button, only while the cursor is over a
registered frame.

`Secure` creates one hidden `SecureActionButtonTemplate` **proxy button** that
carries the wheel bindings' attributes. Because wheel binds resolve through
`@mouseover` like everything else, this is a *single global button*, not one per
frame.

Binding and unbinding happen in restricted snippets wrapped onto each frame by
the header itself — `ClickCastHeader:WrapScript(frame, "OnEnter", setup)` and
`WrapScript(frame, "OnLeave", clear)`, each preceded by `UnwrapScript` so
re-registration cannot stack duplicates. `SecureHandlerBaseTemplate` supplies
`WrapScript`; no separate `SecureHandlerEnterLeaveTemplate` frame is needed.

- **setup** snippet → for each wheel binding,
  `self:SetBindingClick(true, <keybind>, <proxy>, <identifier>)`, where
  `<keybind>` is e.g. `MOUSEWHEELUP` or `SHIFT-MOUSEWHEELDOWN` and
  `<identifier>` is the virtual click name `wheelup` / `wheeldown` that produces
  the `-wheelup` attribute suffix (§10). Before binding, it clears any bindings
  left by a previously hovered frame.
- **clear** snippet → `self:ClearBinding(<keybind>)` for each.

`SetBindingClick` inside a restricted snippet is the only way to bind keys
during combat; the insecure `SetOverrideBinding*` APIs are blocked in combat.

**Stale-binding guard.** If the hovered unit stops existing — it dies and the
frame hides, the raid reshuffles — `OnLeave` may never fire, leaving the wheel
bound to a heal on nobody. The header registers an attribute driver
`RegisterAttributeDriver(header, "unit-exists", "[@mouseover,exists] true; false")`
and an `_onattributechanged` snippet that clears the bindings when the value
turns `false` and the tracked button is no longer under the mouse or visible.
Without this the wheel silently misbehaves after a death, which is exactly when
a healer is least able to diagnose it.

## 13. Options panel

A standalone movable window opened by `/healme`, by the minimap button, or
from the addon compartment. Escape closes it.

It is built on Blizzard's own templates and art so it reads as a built-in
panel, laid out after the Housing dashboard: a `PortraitFrameTemplate` window
with the HealMe icon in the ring, the dashboard's `TabSystemTemplate` top tabs
under the title bar, its dark scene atlas and gold filigree corners on the
content area, `WowStyle1Dropdown` pickers and the slim modern scrollbar. Group
headers use the quest log's collapse-bar atlas and plus/minus icons; icons sit
in the dashboard's bevelled gold frame; headings carry its ornate divider. No
widget library is involved. Every atlas name and anchor was taken from
Blizzard's UI source rather than guessed, and each is set through a helper
that checks `C_Texture.GetAtlasInfo` first, so a missing atlas leaves a gap
rather than a white square. The dropdown and tab system are constructed under
`pcall` with plain fallbacks, so a renamed template costs the look rather than
the addon.

Layout:

- The tab strip holds **Bindings**, **Bar**, **Settings**, **Profiles** and
  **Help** on the left and the **profile picker** on the right, which
  switches profiles the same way `/healme profile <name>` does.
- **Bindings** is two columns over the scene. The left is a translucent plate
  holding the binding list grouped by mouse button, quest-log style: a
  collapsible header per button with a count, and spellbook-style rows
  beneath showing the action's icon, its name in white, and a gold subline of
  modifiers and conditions. Disabled bindings are dimmed and say so in the
  subline. New binding and Delete sit under the list. The right column leads
  with a header straight on the scene, the way the dashboard names the house:
  the icon at 58px in its gold frame, the action name large, the ornate rule,
  the combination in gold, and an Enabled checkbox at the right. Beneath it a
  plate carries the form (button, modifiers, action, spell or macro text) and
  an "Only when" section with the three condition dropdowns. Beside the spell
  field a **Spellbook** picker lists the player's active spells from
  `C_SpellBook`, grouped by spellbook tab as submenus with each spell's icon
  inline; choosing one fills the field and saves through the same validation
  as typing. Passives, off-spec spells and flyouts are left out. The field
  stays the value, so a spell the book does not list can still be typed.
  Below it, **On frames** is a checkbox menu of frame kinds; the button reads
  "All frames" or the ticked kinds. Every kind ticked is stored as no limit,
  and Validate refuses an empty set, so the last box cannot be unticked.
- **Bar** mirrors Profiles: a list of the cooldown bar's spells with icons,
  a spellbook picker and a name field with Add under it, and a plate for the
  selected spell with Move up, Move down and Remove (through the confirm
  popup). Under that, **Placement**: Side and Size dropdowns, stored
  account-wide. A spell the current spec does not know shows red with a
  dimmed icon and keeps its slot. See `2026-09-09-cooldown-bar-design.md` §7.
- **Help** is one plate of quest-log style headers, one per topic from
  `Help.lua`, a plain data file of titles and paragraphs. One topic is open
  at a time; the first opens by default.
- **Settings** is one plate with sectioned headings: **"Also target"** (§10),
  **"Show minimap button"**, and Export and Import, which open the share
  window, a portrait window of the same style with a selectable text box.
- **Profiles** mirrors Bindings: a list of profiles with binding counts and
  active and spec markers, a name field with New profile under it, and a
  plate for the selected profile with Switch to, Copy into active, Delete,
  and Rename, plus Reset for the active profile. Core supplies create,
  switch, rename, delete and a summary; the active profile cannot be
  deleted, and errors show on the plate rather than in chat. Under that,
  **Automatic switching for <spec>**: three dropdowns, solo, party and raid,
  each naming a profile or "Default". Rules live in `HealMeDB.rules` keyed
  by the spec's default profile name. `Core:AutoSwitch` re-resolves on
  login, on spec change and on `GROUP_ROSTER_UPDATE`, which covers a party
  converting to a raid; a slot naming a deleted profile falls back to the
  default, and rename and delete retarget the rules. A profile picked by
  hand holds until the next such change.

**A new binding is created disabled.** It lands on plain left click with no
spell, and if it were live it would overwrite an existing left-click binding
with a cast of nothing on the next compile.

**Every setter that can produce an invalid record reverts on rejection.** The
setter stashes the previous value, applies the change, and restores it if
validation or conflict detection refuses. A rejected edit must never persist
into saved variables.

The combo-capture control this section originally called for — arm a button,
press the combination you want — was not built. A capture widget has to swallow
clicks inside a panel that is itself click-driven, and the dropdown reaches the
same state in one more click. Recorded as follow-up rather than dropped.

## 14. Profiles

Profiles live in `HealMeDB.profiles`, keyed by character, realm and
specialisation, with automatic switching on `PLAYER_SPECIALIZATION_CHANGED`
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

## 16. Open questions

**Resolved 2026-09-06** (findings folded into the sections above; sources in §20):

- ~~Modifier prefix order and button suffix mapping~~ → §10. Order is
  `alt-ctrl-shift-`; wheel suffixes carry a leading hyphen.
- ~~The `ClickCastHeader` snippet protocol~~ → §11, §12. Also surfaced four
  requirements the design had missed: `RegisterForClicks`/`EnableMouseWheel`,
  preserving a pre-existing `ClickCastFrames`, the `Clique` global shim, and the
  `unit-exists` stale-binding guard.
- ~~Target client build~~ → 12.1.0.69587, `lastAddonVersion 120100`, read from
  the local install. `## Interface: 120007, 120100` is correct.

**Still open**, each answered by doing rather than reading:

1. **Whether `mouseover` resolves reliably on every registered frame** (§7).
   To be verified in-game. The per-frame `unit` fallback is designed but
   **not implemented** — `Registry` does not capture each frame's `unit`
   attribute, and `Secure` has no per-frame code path. If in-game testing
   shows `mouseover` failing on some frame, build the fallback at that point,
   not before.
2. **Whether a desktop Lua 5.1 interpreter is available** on the dev machine for
   the compiler tests. If not, the tests ship anyway and run in CI.
3. **`RegisterForClicks("AnyUp")` versus `("AnyDown")`** (§11). `AnyUp` is the
   conservative default: it leaves click-drag behaviour intact. `AnyDown` is
   more responsive and is what Blizzard moved action buttons to. Shipping
   `AnyUp`, revisiting after real raid use; it is a one-line profile setting if
   it turns out to matter.
4. **The `## Author:` value** (§5). Placeholder pending a name.

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
- Round-trip: `Serialize.Export(profile)` → `Import` → identical table,
  including the bar's `c^` records and a pre-bar string decoding to an empty
  bar.
- `Bar` pure helpers: anchor target for every group state, slot layout,
  add-validation (blank, unknown, duplicate, full), import sanitising, size
  clamping.
- `Core` bar accessors: seeding on old profiles and old `ui`, add, remove,
  move, copy with the profile.

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

### In-game self-test

`SelfTest.lua` answers `/healme selftest` and the Settings tab's Run
self-test button. It checks what is readable without secure privilege: the
atlases and templates the panel needs, the registry and frame classes, spell
validity, conflicts, profile rules, the wheel wiring, native click-casting,
the export round trip, and above all the attributes actually on every
registered frame against what the compiler and each binding's scope say
should be there. With nothing enabled it applies a throwaway Target binding
on Alt+Ctrl+Shift+Button 5, verifies it, and removes it. It refuses to run
in combat. Whether a click casts remains the checklist's job.

## 18. Packaging and release

Versions are calendar dates: `YYYY.MM.DD`, zero-padded, with a `.2` suffix
for a second release on one day. The TOC `## Version` is the only place the
number is written; `Core.version` reads it through `C_AddOns.GetAddOnMetadata`
at load and falls back to "dev" outside the client.

Tag-driven GitHub Actions, adapted from the workflow already proven in the
`wow-addons` repo: on a `v*` tag, verify the TOC `## Version` matches the tag,
zip the `HealMe/` folder, attach it to a GitHub release with a changelog of
the commits since the previous tag, and publish the same zip to Wago Addons
when the `WAGO_API_TOKEN` secret exists and the TOC carries an `X-Wago-ID`.
The retail patch label is read from Wago's live list at release time. A tag
containing `beta` or `alpha` publishes at that stability. WowUp installs directly from a
GitHub Releases URL provided the zip contains the addon folder at its root,
which this layout satisfies.

Blizzard's addon policy applies: free, source visible, no obfuscation, no ads,
no donation solicitation.

## 19. Deliberately deferred

Not built now, with a clear seam if ever wanted:

- A HealMe-drawn healing grid. It would consume `Secure` exactly as Blizzard's
  frames do, via `ClickCastFrames`.
- Blizzard-keybind-style bindings that fire without a frame under the cursor.
- Per-binding control of "also target" (§10). The record would gain an
  `alsoTarget` tri-state — inherit / on / off — and the compiler would read the
  effective value instead of the profile setting. One field and one line;
  nothing else moves.
- Free-floating placement of the cooldown bar for third-party raid frames.

Not built, ever, unless Blizzard reverses course: any condition requiring health
values, aura state, or combat log data (§3.3).

## 20. Sources

Read directly, not recalled, on 2026-09-06.

- **`Blizzard_FrameXML/SecureTemplates.lua`**, `Gethe/wow-ui-source` @ `live` —
  `SecureButton_GetModifierPrefix` (lines 70-93), `SecureButton_GetButtonSuffix`
  (lines 95-117), `SecureButton_GetModifiedUnit` (143+), and the `SECURE_ACTIONS`
  table (260+) confirming `spell`, `macro`, `target`, `focus`, `togglemenu`, and
  the `menu` / `menu-function` trap.
- **`Clicked/UnitFrames/ClickCastHeader.lua`** and
  **`Clicked/UnitFrames/ClickCastFrames.lua`**, `Snakybo/Clicked` — the
  `ClickCastHeader` protocol, the `export_register` indirection, `WrapScript`
  enter/leave wiring, the `unit-exists` attribute driver, the `Clique` global
  shim, and the combat queues. GPLv3; HealMe matches the protocol's shape as
  every click-cast addon must, and does not copy its implementation.
- **Local client** `D:\World of Warcraft\.build.info` — build 12.1.0.69587; and
  `_retail_\WTF\Config.wtf` — `lastAddonVersion 120100`.
- **`D:\wow-addons\WOW-ADDON-GUIDE.md`** and the `GuildPlaybook` addon and
  release workflow in that repo — TOC format, Secret Values, packaging.
