# HealMe — Cooldown Bar Design

Companion to `2026-09-06-healme-design.md`. That spec stays the authority on
click-casting; this one adds a single new subsystem and names the lines in the
main spec it amends (§4 scope, §8 modules, §9 data model, §19 deferred).

## 1. What this is

A small row of spell buttons glued to the top or bottom edge of Blizzard's
raid frames. Each button shows a spell's icon, cooldown swipe, and charge
count, and casts the spell when clicked. It exists so a healer's long
cooldowns (Tranquility, Halo, Divine Hymn, Revival) sit where their eyes
already are, instead of down on the action bars.

## 2. What it is not

- **Not unit-based.** Every button is a plain `type=spell` cast on nothing.
  No `mouseover`, no `target`, no conditions. Spells that need a target still
  cast at the current target, as they would from any action bar, but the bar
  does nothing to pick one.
- **Not an action bar replacement.** No paging, no keybinds, no drag from the
  spellbook, no macros, no items. A dozen slots at most.
- **Not a raid-frame addon.** It anchors to frames Blizzard draws. If those
  frames are absent, it hides.

The main spec's scope line "bindings that fire without a frame under the
cursor" is amended: the bar is exactly that, and is the one sanctioned place
for it.

## 3. Constraints that shape it

The hard constraints in the main spec §3 apply unchanged:

- Buttons are `SecureActionButtonTemplate`. Attribute writes, Show/Hide, and
  reparenting go through `Secure`'s combat queue. Never direct.
- Cooldown data comes from `C_Spell.GetSpellCooldown` and
  `C_Spell.GetSpellCharges`, and is passed **untouched** into
  `Cooldown:SetCooldown(start, duration, modRate)`. That is what Blizzard's own
  `ActionButton_ApplyCooldown` does (`Blizzard_ActionBar/Shared/ActionButton.lua`,
  `live`, read 2026-09-09). The cooldown frame accepts Secret Values; HealMe
  never compares or does arithmetic on them. `isActive` is used only as a
  truthy check, as Blizzard does.
- Usability dimming reads `C_Spell.IsSpellUsable` and sets a vertex colour.
  Display only.

## 4. Data model

Per profile, so the bar swaps with specialization like bindings do:

```lua
profile.bar = { "Tranquility", "Nature's Swiftness" }   -- ordered spell names
```

Spell names are validated exactly like a binding's spell: `C_Spell.GetSpellInfo`
must return a result, and case is preserved. An unknown name is refused by the
editor, not silently dropped. A name that later stops resolving (talent swap,
spec change) leaves its slot empty with no icon; the button carries no
attribute and clicking it does nothing.

Layout is a habit, not a spec thing, so it lives in the shared UI table:

```lua
HealMeDB.ui.bar = {
  side = "above",   -- "above" | "below"
  size = 36,        -- button edge in pixels, 24..64
}
```

`Core` seeds both with defaults the same way it seeds `alsoTarget` and the
minimap fields. `Core:CopyProfileFrom` copies the bar list.

### Serialization

The export codec gains one record type:

```
c^<spell>
```

one per bar spell, in order, after the `s` settings record. Strings from
before this field decode with an empty bar. `Serialize.Import` accepts a
missing `bar` as `{}`.

## 5. Module: `Bar.lua`

Loads after `Secure` and before `Options` in the TOC. Publishes `ns.Bar`.

### Frames

- One container `Frame`, `HealMeBar`, parented to `UIParent`.
- Up to `Bar.MAX_SLOTS = 12` child buttons, `HealMeBarButton1..12`, each a
  `SecureActionButtonTemplate` with:
  - an icon `Texture` (`SetTexture` from `C_Spell.GetSpellTexture`),
  - a `CooldownFrameTemplate` child for the swipe and Blizzard's countdown
    numbers,
  - a `FontString` for charge count, hidden when the spell has no charges,
  - `RegisterForClicks("AnyUp", "AnyDown")` so the cast honours the player's
    `ActionButtonUseKeyDown` setting the way Blizzard buttons do,
  - `OnEnter` / `OnLeave` showing `GameTooltip:SetSpellByID`.
- Buttons are laid out left to right, `size` square with a fixed 4 px gap;
  unused slots are hidden. Container width follows the used count.

Buttons are created once at load. Bar contents only change which attributes
and textures each slot carries.

### Applying

`Bar:Apply()` is the one entry point and is called from `Core:NotifyChanged`
alongside `Secure:ApplyAll`. Under `InCombatLockdown()` it sets a flag and
returns; `Secure:FlushQueues` calls it on `PLAYER_REGEN_ENABLED`. Out of
combat it:

1. Reads the active profile's `bar` list and `HealMeDB.ui.bar`.
2. For each slot `i`: if `bar[i]` resolves, writes `type=spell`,
   `spell=<name>`, stores the spell ID on the button, sets the icon, shows
   the button. Otherwise clears the attributes and hides it.
3. Resizes the container and re-anchors it (§6).
4. Refreshes cooldowns for every visible slot.

### Refreshing

Events: `SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_CHARGES`,
`SPELL_UPDATE_USABLE`, `PLAYER_ENTERING_WORLD`. Each walks the visible slots
and updates the swipe, charge text, and icon tint. None of these touch
protected state, so they run in combat.

## 6. Anchoring

The bar rides whichever Blizzard group frame is showing. A pure function
picks the target so it can be unit-tested:

```lua
-- Returns the global name of the frame to anchor to, or nil to hide.
Bar.AnchorTarget(inRaid, inParty, raidStyleParty)
```

| State                         | Target                     |
| ----------------------------- | -------------------------- |
| in a raid                     | `CompactRaidFrameContainer` |
| in a party, raid-style frames | `CompactPartyFrame`        |
| in a party, classic frames    | `PartyFrame`               |
| solo, or target frame missing | hide                       |

`side == "above"` anchors `BOTTOM` of the bar to `TOP` of the target;
`"below"` anchors `TOP` to `BOTTOM`. Horizontal alignment is `LEFT` to `LEFT`
so the bar starts where the frames start.

Re-anchor triggers: `GROUP_ROSTER_UPDATE`, `PLAYER_ENTERING_WORLD`, the
`EditMode.Exit` callback from `EventRegistry`, and any settings change. The
container is not protected, so `SetPoint` on it is legal in combat, but the
re-anchor still goes through the combat flag in §5 for consistency and
because Show/Hide of a parent of secure buttons is the kind of thing that
gets tightened without notice.

The "use raid-style party frames" state is read from
`EditModeManagerFrame:UseRaidStylePartyFrames()` when present, falling back
to `CompactPartyFrame:IsShown()`.

### Third-party raid frames

Not supported in this build. Grid2, VuhDo, ElvUI and friends draw their own
frames and the bar has nothing to glue to, so it hides. A free-floating,
draggable fallback goes in §10 deferred; the seam is `AnchorTarget` returning
a sentinel and `Apply` reading a saved point instead.

## 7. Options: the Bar tab

A new top tab, "Bar", between Bindings and Settings. Built from the existing
widgets:

- **Spell list.** `Widgets.ListRow` per slot: icon, name, up / down arrows,
  and a remove button. Remove goes through `Widgets.Confirm`. Reorder swaps
  entries in `profile.bar` and notifies.
- **Add.** `Widgets.SpellbookPicker`, the same control the binding editor
  uses. Picking a spell appends it, refusing duplicates and refusing when
  the list is full.
- **Side.** `Widgets.Dropdown` with `above` / `below`.
- **Size.** `Widgets.Dropdown` with 24, 32, 36, 40, 48, 64. A slider would be
  nicer and is not worth a new widget for six values.
- A `Widgets.Note` under the list saying the bar hides when Blizzard raid
  or party frames are not on screen.

Every setter stashes the previous value and reverts on validation failure,
per the existing editor rule.

## 8. Error handling

- Unknown spell name at add time: editor refuses, message under the picker.
- Spell stops resolving later: slot goes empty, no error, nothing logged. The
  Bar tab shows the row with a red name so the player can see why.
- Anchor target missing: bar hides; the Bar tab note covers it.
- Every event handler runs through the same `safecall` wrapper `Secure`
  uses, so a Blizzard API rename costs the bar, not the addon.

## 9. Testing

Unit (desktop, lupa):

- `Core` seeds `profile.bar` and `ui.bar` defaults; `CopyProfileFrom` copies
  the list.
- `Bar.Validate(name)` mirrors the spell check on bindings; duplicates and
  the twelve-slot cap are refused.
- `Serialize` round-trips a profile with a bar, and decodes a pre-bar string
  to an empty bar.
- `Bar.AnchorTarget` for each row of the table in §6.
- `Bar.Layout(count, size)` returns container width and per-slot offsets.

In-game (`docs/manual-test-checklist.md` gains a "Cooldown bar" section):

- Add two spells, see icons appear above the raid frames.
- Switch side to below; switch size; bar follows.
- Drag the raid frames in Edit Mode; bar follows on exit.
- Pull a mob; cooldown swipe and countdown show; click casts.
- Change spec; bar swaps with the profile.
- Join a raid mid-combat; bar re-anchors after combat drops.
- Leave group; bar hides.
- Disable a spell via talents; slot goes empty, no Lua error.

The self-test gains one line: the bar container exists and its slot count
matches the profile.

## 10. Deliberately deferred

- Free-floating placement for third-party raid frames (§6 seam).
- Drag from the spellbook onto the bar.
- Per-button unit (`target` / `focus` / `player`). The attribute set would
  gain `unit`; nothing else moves.
- Keybinds on bar slots. Blizzard's keybind UI owns that.
- Loss-of-control cooldown overlay and the proc glow. Display sugar.

## 11. Sources

Read directly on 2026-09-09.

- `Blizzard_ActionBar/Shared/ActionButton.lua`, `Gethe/wow-ui-source` @
  `live`: `ActionButton_UpdateCooldown` (lines 823-843) and
  `ActionButton_ApplyCooldown` (853-867) for the cooldown API shape and the
  fact that start / duration / modRate are passed through untouched.
