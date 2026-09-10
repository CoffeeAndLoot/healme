# Cooldown Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A row of clickable spell buttons with cooldown swipes, anchored above or below Blizzard's raid or party frames, contents per profile.

**Architecture:** A new `Bar` module owns one container frame and twelve `SecureActionButtonTemplate` slots; `Core` stores the spell list per profile and the placement in the account-wide `ui` table; `Serialize` gains a `c^<spell>` record; `Options` gains a "Bar" tab built from existing widgets. Pure helpers (anchor choice, layout, validation) are unit-tested on the desktop; frames are checked in-game through the checklist and self-test.

**Tech Stack:** Lua 5.1, Blizzard WoW API (Midnight 12.1+), no libraries. Tests via the repo harness run through `lupa`. Lint via luacheck and lua-language-server.

**Spec:** `docs/superpowers/specs/2026-09-09-cooldown-bar-design.md`

## Global Constraints

- Plain Lua 5.1 against the Blizzard API, **no libraries**.
- Never write a secure attribute, Show/Hide a secure button's parent, or reparent outside an `InCombatLockdown()` guard; queue and flush on `PLAYER_REGEN_ENABLED`.
- Cooldown values from `C_Spell.GetSpellCooldown` are passed **untouched** into `Cooldown:SetCooldown`; never compared or used in arithmetic.
- Do not lowercase spell names anywhere.
- Every new WoW global goes in both `.luacheckrc` (`read_globals`) and `.luarc.json`.
- luacheck and lua-language-server stay at zero findings; `max_line_length = 120`.
- Every editor setter stashes the previous value and reverts on validation failure.
- Destructive UI actions go through `Widgets.Confirm`.
- Commit after each task. Another agent (Codex) commits to this repo: re-read a file before editing it.
- Versions live only in `HealMe/HealMe.toc`; this plan does not bump it (releasing is the user's call).

## Commands

Tests:

```
python -c "import lupa.lua51 as L; lua=L.LuaRuntime(unpack_returned_tuples=True); print(lua.execute(open('test/run.lua').read().replace('os.exit(harness.run())','return harness.run()')))"
```

Expected on success: the final line reads `N passed, 0 failed` and the printed return value is `0`.

Lint (PowerShell):

```
$env:PATH = "$HOME\AppData\Local\Programs\Lua\bin;$env:PATH"
$env:LUA_PATH = "$HOME\.luarocks\share\lua\5.4\?.lua;$HOME\.luarocks\share\lua\5.4\?\init.lua;;"
lua "$HOME\.luarocks\share\lua\5.4\luacheck\main.lua" HealMe test --no-color --no-cache
lua-language-server --check D:\healme --checklevel=Warning --check_out_path=$env:TEMP\lls.json
```

Expected: luacheck prints `Total: 0 warnings / 0 errors`; the language server writes an empty `{}` (or a file with no diagnostics).

## File Structure

- Create `HealMe/Bar.lua` — the module: pure helpers at the top (`AnchorTarget`, `Layout`, `Validate`, `Sanitize`), frame code below (`Initialize`, `Apply`, `RefreshCooldowns`).
- Create `test/test_bar.lua` — tests for the pure helpers.
- Modify `HealMe/Core.lua` — profile default gains `bar = {}`; `ui.bar` seeded; accessors `Core:Bar()`, `Core:AddBarSpell`, `Core:RemoveBarSpell`, `Core:MoveBarSpell`; `CopyProfileFrom` copies the list; `ApplyAll` calls `Bar:Apply`; `OnLogin` initialises the bar.
- Modify `HealMe/Serialize.lua` — `c^<spell>` records, `Import` tolerates a missing `bar`.
- Modify `HealMe/Options.lua` — a "Bar" tab; import copies the bar list; export includes it.
- Modify `HealMe/SelfTest.lua` — one check for the bar; round trip carries the bar.
- Modify `HealMe/Help.lua` — one topic.
- Modify `HealMe/HealMe.toc`, `test/run.lua`, `.luacheckrc`, `.luarc.json` — registration.
- Modify `docs/manual-test-checklist.md`, `docs/superpowers/specs/2026-09-06-healme-design.md`, `README.md` — docs.

---

### Task 1: Profile and UI data for the bar

**Files:**
- Modify: `HealMe/Core.lua` (`defaultProfile` ~line 28, `SetProfile` ~line 112, `CopyProfileFrom` ~line 157, `OnAddonLoaded` ~line 460, accessors ~line 391)
- Test: `test/test_profiles.lua`

**Interfaces:**
- Produces: `profile.bar` (array of spell name strings), `HealMeDB.ui.bar = { side = "above"|"below", size = 36 }`, `Core:Bar()` → the array, `Core:AddBarSpell(name)` → `ok, err`, `Core:RemoveBarSpell(index)` → `ok`, `Core:MoveBarSpell(index, delta)` → `ok`. The add/remove/move methods call `NotifyChanged`.
- Consumes: `ns.Bar.Validate(list, name, spellExists)` from Task 2 when present; falls back to a local check when `ns.Bar` is absent (the profiles test loads Core alone).

- [ ] **Step 1: Write the failing tests**

Append inside the `return function(h)` body of `test/test_profiles.lua`, after the existing `env.geterrorhandler` line, a spell stub:

```lua
    env.C_Spell = {
        GetSpellInfo = function(name)
            local known = { Tranquility = true, Halo = true, ["Nature's Swiftness"] = true }
            return known[name] and { spellID = 1 } or nil
        end,
    }
```

And add a new describe block at the end of the file, before the final `end`:

```lua
    h.describe("Core cooldown bar", function()
        h.it("seeds an empty bar on a profile and placement in ui", function()
            local c = fresh()
            h.eq(#c:Bar(), 0)
            h.eq(env.HealMeDB.ui.bar.side, "above")
            h.eq(env.HealMeDB.ui.bar.size, 36)
        end)

        h.it("fills a missing bar on an old profile", function()
            local c = fresh()
            env.HealMeDB.profiles["Old"] = { bindings = {}, settings = {} }
            c:SetProfile("Old")
            h.eq(#c:Bar(), 0)
        end)

        h.it("adds known spells in order and refuses unknown or duplicate ones", function()
            local c = fresh()
            h.truthy(c:AddBarSpell("Tranquility"))
            h.truthy(c:AddBarSpell("Halo"))
            h.eq(c:Bar()[1], "Tranquility")
            h.eq(c:Bar()[2], "Halo")
            local ok, err = c:AddBarSpell("Halo")
            h.falsy(ok)
            h.truthy(err:find("already"), err)
            ok, err = c:AddBarSpell("Made Up")
            h.falsy(ok)
            h.truthy(err:find("unknown"), err)
            ok = c:AddBarSpell("")
            h.falsy(ok)
        end)

        h.it("removes and reorders", function()
            local c = fresh()
            c:AddBarSpell("Tranquility")
            c:AddBarSpell("Halo")
            c:AddBarSpell("Nature's Swiftness")
            h.truthy(c:MoveBarSpell(3, -1))
            h.eq(c:Bar()[2], "Nature's Swiftness")
            h.eq(c:Bar()[3], "Halo")
            h.falsy(c:MoveBarSpell(1, -1))
            h.falsy(c:MoveBarSpell(3, 1))
            h.truthy(c:RemoveBarSpell(1))
            h.eq(#c:Bar(), 2)
            h.eq(c:Bar()[1], "Nature's Swiftness")
            h.falsy(c:RemoveBarSpell(9))
        end)

        h.it("copies the bar with the profile", function()
            local c = fresh()
            c:CreateProfile("Source")
            c:AddBarSpell("Halo")
            c:SwitchProfile("Coffee - Suramar")
            c:CopyProfileFrom("Source")
            h.eq(c:Bar()[1], "Halo")
            c:Bar()[1] = "Changed"
            h.eq(env.HealMeDB.profiles["Source"].bar[1], "Halo")
        end)
    end)
```

Note: `fresh()` calls `Core:SetProfile` but not `OnAddonLoaded`, so `ui.bar` is seeded in `SetProfile`'s path too (see Step 3). Read `fresh()` before editing; if it already builds `HealMeDB.ui`, keep that shape.

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command. Expected: failures mentioning `attempt to call method 'Bar'` (a nil value) in the new block, everything else passing.

- [ ] **Step 3: Implement in Core**

In `defaultProfile()`:

```lua
local function defaultProfile()
    return {
        bindings = {},
        bar = {},
        settings = {
            alsoTarget = false,
        },
    }
end
```

In `Core:SetProfile`, after `profile.bindings = profile.bindings or {}`:

```lua
    profile.bar = profile.bar or {}
```

Add a helper near the top of the file (after `defaultProfile`) and call it from both `OnAddonLoaded` (after the minimap seeding) and `SetProfile` (first line after the early return), so tests that never run `OnAddonLoaded` still see it:

```lua
-- Bar placement is a habit of the interface, like the minimap angle, so it
-- lives in the account-wide ui table rather than in a profile.
local function seedUI()
    HealMeDB.ui = HealMeDB.ui or {}
    local bar = HealMeDB.ui.bar or {}
    HealMeDB.ui.bar = bar
    if bar.side ~= "below" then
        bar.side = "above"
    end
    if type(bar.size) ~= "number" then
        bar.size = 36
    end
end
```

In `Core:CopyProfileFrom`, after the `copy.settings.alsoTarget = ...` line:

```lua
    for i = 1, #(source.bar or {}) do
        copy.bar[i] = source.bar[i]
    end
```

Accessors, after `Core:Settings()`:

```lua
function Core:Bar()
    return self.db.profile.bar
end

-- Adding goes through the bar's own rules (known spell, no duplicates,
-- slot cap). The module is absent on the desktop runner's Core-only test,
-- so fall back to the same checks inline.
function Core:AddBarSpell(name)
    local list = self:Bar()
    local ok, err
    if ns.Bar and ns.Bar.Validate then
        ok, err = ns.Bar.Validate(list, name, function(s) return Core:SpellExists(s) end)
    else
        if type(name) ~= "string" or name == "" then
            ok, err = false, "pick a spell"
        elseif not self:SpellExists(name) then
            ok, err = false, "unknown spell: " .. name
        else
            ok = true
            for i = 1, #list do
                if list[i] == name then
                    ok, err = false, name .. " is already on the bar"
                end
            end
        end
    end
    if not ok then
        return false, err
    end
    list[#list + 1] = name
    self:NotifyChanged()
    return true
end

function Core:RemoveBarSpell(index)
    local list = self:Bar()
    if not list[index] then
        return false
    end
    table.remove(list, index)
    self:NotifyChanged()
    return true
end

function Core:MoveBarSpell(index, delta)
    local list = self:Bar()
    local target = index + delta
    if not list[index] or not list[target] then
        return false
    end
    list[index], list[target] = list[target], list[index]
    self:NotifyChanged()
    return true
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command. Expected: `N passed, 0 failed`.

- [ ] **Step 5: Lint and commit**

Run both lint commands; expect zero findings.

```bash
git add HealMe/Core.lua test/test_profiles.lua
git commit -m "Store the cooldown bar's spells per profile and its placement in ui"
```

---

### Task 2: Bar module, pure helpers

**Files:**
- Create: `HealMe/Bar.lua`
- Create: `test/test_bar.lua`
- Modify: `test/run.lua` (module list and suite list)
- Modify: `HealMe/HealMe.toc` (load order)

**Interfaces:**
- Produces: `ns.Bar` with `MAX_SLOTS = 12`, `GAP = 4`, `SIZES = { 24, 32, 36, 40, 48, 64 }`, `Bar.AnchorTarget(inRaid, inParty, raidStyleParty)` → frame global name or nil, `Bar.Layout(count, size, gap)` → `width, offsets`, `Bar.Validate(list, name, spellExists)` → `ok, err`, `Bar.Sanitize(list)` → cleaned array (strings only, no blanks, no duplicates, at most `MAX_SLOTS`; unknown spells are kept so an import from another spec keeps its slots).
- Consumes: nothing.

- [ ] **Step 1: Write the failing tests**

Create `test/test_bar.lua`:

```lua
return function(h, m)
    local Bar = m.Bar
    if not Bar then return end

    h.describe("Bar.AnchorTarget", function()
        h.it("uses the raid container in a raid", function()
            h.eq(Bar.AnchorTarget(true, true, false), "CompactRaidFrameContainer")
            h.eq(Bar.AnchorTarget(true, true, true), "CompactRaidFrameContainer")
        end)

        h.it("picks the party frame by style in a party", function()
            h.eq(Bar.AnchorTarget(false, true, true), "CompactPartyFrame")
            h.eq(Bar.AnchorTarget(false, true, false), "PartyFrame")
        end)

        h.it("hides when solo", function()
            h.eq(Bar.AnchorTarget(false, false, false), nil)
            h.eq(Bar.AnchorTarget(false, false, true), nil)
        end)
    end)

    h.describe("Bar.Layout", function()
        h.it("lays slots out left to right with a gap", function()
            local width, offsets = Bar.Layout(3, 36, 4)
            h.eq(width, 116)
            h.eq(offsets[1], 0)
            h.eq(offsets[2], 40)
            h.eq(offsets[3], 80)
        end)

        h.it("is empty for no slots", function()
            local width, offsets = Bar.Layout(0, 36, 4)
            h.eq(width, 0)
            h.eq(#offsets, 0)
        end)

        h.it("defaults the gap", function()
            local width = Bar.Layout(2, 10)
            h.eq(width, 20 + Bar.GAP)
        end)
    end)

    h.describe("Bar.Validate", function()
        local exists = function(name) return name == "Halo" or name == "Tranquility" end

        h.it("accepts a known spell not yet on the bar", function()
            h.truthy(Bar.Validate({}, "Halo", exists))
            h.truthy(Bar.Validate({ "Tranquility" }, "Halo", exists))
        end)

        h.it("refuses blanks, unknowns and duplicates", function()
            h.falsy(Bar.Validate({}, "", exists))
            h.falsy(Bar.Validate({}, nil, exists))
            local ok, err = Bar.Validate({}, "Nope", exists)
            h.falsy(ok)
            h.truthy(err:find("unknown"), err)
            ok, err = Bar.Validate({ "Halo" }, "Halo", exists)
            h.falsy(ok)
            h.truthy(err:find("already"), err)
        end)

        h.it("refuses a full bar", function()
            local list = {}
            for i = 1, Bar.MAX_SLOTS do list[i] = "Spell " .. i end
            local ok, err = Bar.Validate(list, "Halo", exists)
            h.falsy(ok)
            h.truthy(err:find("full"), err)
        end)

        h.it("skips the existence check without a checker", function()
            h.truthy(Bar.Validate({}, "Anything"))
        end)
    end)

    h.describe("Bar.Sanitize", function()
        h.it("keeps strings in order, drops blanks, junk and duplicates", function()
            local out = Bar.Sanitize({ "Halo", "", 7, "Halo", "Tranquility", false })
            h.eq(#out, 2)
            h.eq(out[1], "Halo")
            h.eq(out[2], "Tranquility")
        end)

        h.it("caps at the slot count", function()
            local list = {}
            for i = 1, Bar.MAX_SLOTS + 3 do list[i] = "Spell " .. i end
            h.eq(#Bar.Sanitize(list), Bar.MAX_SLOTS)
        end)

        h.it("returns an empty list for a non-table", function()
            h.eq(#Bar.Sanitize(nil), 0)
            h.eq(#Bar.Sanitize("x"), 0)
        end)
    end)
end
```

In `test/run.lua`, add to `modules` after `Secure`:

```lua
    { "Bar",       "HealMe/Bar.lua" },
```

and to `suites` after `test_registry.lua`:

```lua
    "test/test_bar.lua",
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command. Expected: an error that `HealMe/Bar.lua` cannot be opened (the runner skips missing modules, so the suite may silently skip: confirm by checking the pass count did not grow). Either way, proceed.

- [ ] **Step 3: Create the module with the pure helpers**

Create `HealMe/Bar.lua`:

```lua
local _, ns = ...
ns = ns or {}

local Bar = {}
ns.Bar = Bar

-- A row of spell buttons glued to Blizzard's raid or party frames so a
-- healer's long cooldowns sit where their eyes already are. Every button is
-- a plain spell cast with no unit: Tranquility, Halo, Divine Hymn. The
-- spell list is per profile; where the bar sits is an account-wide habit.
--
-- The helpers above the frame code are pure and unit-tested on the desktop.

Bar.MAX_SLOTS = 12
Bar.GAP = 4
Bar.SIZES = { 24, 32, 36, 40, 48, 64 }
Bar.DEFAULT_SIDE = "above"
Bar.DEFAULT_SIZE = 36

---------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------

-- The global name of the frame the bar rides, or nil to hide. Raid wins
-- over party; a party picks by whether raid-style party frames are on.
function Bar.AnchorTarget(inRaid, inParty, raidStyleParty)
    if inRaid then
        return "CompactRaidFrameContainer"
    end
    if inParty then
        return raidStyleParty and "CompactPartyFrame" or "PartyFrame"
    end
    return nil
end

-- Container width and each slot's x offset for `count` square slots.
function Bar.Layout(count, size, gap)
    gap = gap or Bar.GAP
    local offsets = {}
    for i = 1, count do
        offsets[i] = (i - 1) * (size + gap)
    end
    local width = 0
    if count > 0 then
        width = count * size + (count - 1) * gap
    end
    return width, offsets
end

-- Whether `name` may be appended to `list`. `spellExists` is optional so
-- the check can run without a client.
function Bar.Validate(list, name, spellExists)
    if type(name) ~= "string" or name == "" then
        return false, "pick a spell"
    end
    if #list >= Bar.MAX_SLOTS then
        return false, "the bar is full (" .. Bar.MAX_SLOTS .. " slots)"
    end
    for i = 1, #list do
        if list[i] == name then
            return false, name .. " is already on the bar"
        end
    end
    if spellExists and not spellExists(name) then
        return false, "unknown spell: " .. name
    end
    return true
end

-- An imported list, cleaned: strings only, no blanks, no duplicates, at
-- most MAX_SLOTS. Unknown spells are kept on purpose: a string from another
-- spec should keep its slots and simply show them empty here.
function Bar.Sanitize(list)
    local out, seen = {}, {}
    if type(list) ~= "table" then
        return out
    end
    for i = 1, #list do
        local name = list[i]
        if type(name) == "string" and name ~= "" and not seen[name]
                and #out < Bar.MAX_SLOTS then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    return out
end

return Bar
```

Add `Bar.lua` to `HealMe/HealMe.toc` after `Secure.lua`:

```
Secure.lua
Bar.lua
Serialize.lua
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command. Expected: the pass count rose by 12 and `0 failed`.

- [ ] **Step 5: Lint and commit**

Run both lint commands; expect zero findings.

```bash
git add HealMe/Bar.lua HealMe/HealMe.toc test/test_bar.lua test/run.lua
git commit -m "Add the Bar module's pure helpers: anchor choice, layout, validation"
```

---

### Task 3: Serialize the bar

**Files:**
- Modify: `HealMe/Serialize.lua` (`Import` ~line 36, codec comment ~line 50, `codec.encode` / `codec.decode` ~line 195)
- Modify: `HealMe/Options.lua` (import handler ~line 1105, export payload ~line 1151)
- Modify: `HealMe/SelfTest.lua` (`checkRoundTrip` ~line 261)
- Test: `test/test_serialize.lua`

**Interfaces:**
- Produces: export strings carry one `c^<spell>` record per bar entry after the `s` record; `decode` returns `profile.bar` (always a table); `Import` guarantees `profile.bar` is a table.
- Consumes: `ns.Bar.Sanitize` (Task 2) in the Options import handler.

- [ ] **Step 1: Write the failing tests**

In `test/test_serialize.lua`, add to the `Serialize.codec` describe block, after the "decodes a string from before the frames field" test:

```lua
        h.it("round-trips the bar in order after the settings record", function()
            local text = real.encode({
                bindings = {},
                settings = { alsoTarget = false },
                bar = { "Tranquility", "Nature's Swiftness" },
            })
            h.eq(text, "s^0~c^Tranquility~c^Nature's Swiftness")
            local back = real.decode(text)
            h.eq(#back.bar, 2)
            h.eq(back.bar[1], "Tranquility")
            h.eq(back.bar[2], "Nature's Swiftness")
        end)

        h.it("escapes separators in a bar spell name", function()
            local back = real.decode(real.encode({ bindings = {}, settings = {}, bar = { "A^B~C" } }))
            h.eq(back.bar[1], "A^B~C")
        end)

        h.it("decodes a string from before the bar as an empty bar", function()
            local back = real.decode("s^0~b^BUTTON1^^spell^Rejuvenation^^^^^1")
            h.eq(#back.bar, 0)
        end)
```

And in the `Serialize` (envelope) describe block, after "round-trips a profile":

```lua
        h.it("guarantees a bar table on import", function()
            local text = Serialize.Export({ bindings = {}, settings = {} }, codec)
            local result = Serialize.Import(text, codec)
            h.eq(type(result.bar), "table")
        end)
```

Check how `real` is defined in that file (it is `Serialize.codec`) and that the string-literal expectation matches the existing `s^0` prefix behaviour before running.

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command. Expected: the four new tests fail (`back.bar` is nil).

- [ ] **Step 3: Implement**

In `Serialize.Import`, after the `decoded.settings = ...` line:

```lua
    decoded.bar = type(decoded.bar) == "table" and decoded.bar or {}
```

Extend the codec comment block:

```lua
--   settings: s^alsoTarget
--   bar spell: c^spell            one per cooldown-bar slot, in order
```

In `codec.encode`, after the bindings loop:

```lua
        local bar = profile.bar or {}
        for i = 1, #bar do
            records[#records + 1] = "c" .. FIELD_SEP .. escape(bar[i])
        end
```

In `codec.decode`, initialise `bar = {}` in the profile table and add a branch:

```lua
        local profile = { bindings = {}, settings = { alsoTarget = false }, bar = {} }
```

```lua
            elseif fields[1] == "c" then
                local name = unescape(fields[2] or "")
                if name ~= "" then
                    profile.bar[#profile.bar + 1] = name
                end
```

In `HealMe/Options.lua`, export payload (inside `Options:ShowShare`, the `mode == "export"` branch):

```lua
        s.box:SetText(ns.Serialize.Export({
            bindings = ns.Core:Bindings(),
            settings = ns.Core:Settings(),
            bar = ns.Core:Bar(),
        }, ns.Serialize.codec))
```

Import handler, inside the `W.Confirm` callback after the `alsoTarget` line:

```lua
                    ns.Core.db.profile.bar = ns.Bar.Sanitize(profile.bar)
```

Also change the confirm's text so the player knows the bar is replaced too. Replace the string that ends `"from this string?"` with:

```lua
                    .. " with the " .. #profile.bindings .. " from this string? The cooldown bar is replaced too.", function()
```

Update the hint in the same function (the `mode == "import"` branch): `"Paste a string here. It replaces every binding and the cooldown bar in this profile."`

In `HealMe/SelfTest.lua`, `checkRoundTrip`, include the bar in the profile it exports:

```lua
    local profile = { bindings = Core:Bindings(), settings = Core:Settings(), bar = Core:Bar() }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command. Expected: `0 failed`.

- [ ] **Step 5: Lint and commit**

Run both lint commands; expect zero findings.

```bash
git add HealMe/Serialize.lua HealMe/Options.lua HealMe/SelfTest.lua test/test_serialize.lua
git commit -m "Carry the cooldown bar through export and import"
```

---

### Task 4: Bar frames, apply, cooldowns, anchoring

**Files:**
- Modify: `HealMe/Bar.lua` (append below the pure helpers, before `return Bar`)
- Modify: `HealMe/Core.lua` (`Core:ApplyAll` ~line 425, `Core:OnLogin` ~line 496)
- Modify: `.luacheckrc`, `.luarc.json`
- Modify: `docs/superpowers/specs/2026-09-09-cooldown-bar-design.md` (§5 flush wording, §4 empty-slot wording)

**Interfaces:**
- Produces: `Bar:Initialize()` (creates frames once, registers events, applies), `Bar:Apply()` (queues in combat), `Bar:RefreshCooldowns()`, `Bar:SlotCount()` → number of visible slots (for the self-test).
- Consumes: `Core:Bar()`, `Core:UISettings().bar`, `Core:SpellExists`, the pure helpers from Task 2.

- [ ] **Step 1: Write a throwaway smoke test**

Frames cannot run on the desktop, but a permissive `CreateFrame` stub catches nil errors in the build path. Create `scratch_bar_smoke.lua` in the scratchpad directory (not the repo):

```lua
-- Throwaway: loads Bar.lua with every frame method a no-op and drives
-- Initialize / Apply / RefreshCooldowns to catch nil errors.
local function stubFrame()
    return setmetatable({}, { __index = function(t, k)
        if k == "IsShown" then return function() return true end end
        if k == "GetWidth" then return function() return 100 end end
        return function() return t end
    end })
end
local G = setmetatable({}, { __index = _G })
G.CreateFrame = function() return stubFrame() end
G.UIParent = stubFrame()
G.CompactRaidFrameContainer = stubFrame()
G.InCombatLockdown = function() return false end
G.IsInRaid = function() return true end
G.IsInGroup = function() return true end
G.geterrorhandler = function() return function(e) error(e) end end
G.EditModeManagerFrame = { UseRaidStylePartyFrames = function() return true end }
G.EventRegistry = { RegisterCallback = function() end }
G.GameTooltip = stubFrame()
G.C_Spell = {
    GetSpellInfo = function(name) return name == "Halo" and { spellID = 120517 } or nil end,
    GetSpellTexture = function() return 1234 end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0, isActive = false } end,
    GetSpellCharges = function() return nil end,
    IsSpellUsable = function() return true, false end,
}
G._G = G
local ns = { Core = {
    Bar = function() return { "Halo", "Missing" } end,
    UISettings = function() return { bar = { side = "below", size = 36 } } end,
    SpellExists = function(_, n) return n == "Halo" end,
} }
local chunk = assert(loadfile("HealMe/Bar.lua"))
setfenv(chunk, G)
local Bar = chunk("HealMe", ns)
Bar:Initialize()
Bar:Apply()
Bar:RefreshCooldowns()
assert(Bar:SlotCount() == 2, "slot count")
print("smoke ok")
```

Run it from the repo root through lupa:

```
python -c "import lupa.lua51 as L; lua=L.LuaRuntime(unpack_returned_tuples=True); lua.execute(open(r'<scratchpad>\scratch_bar_smoke.lua').read())"
```

Expected now: an error, since `Bar.Initialize` does not exist yet.

- [ ] **Step 2: Implement the frame code**

Append to `HealMe/Bar.lua` before `return Bar`:

```lua
---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local FALLBACK_ICON = 134400 -- INV_Misc_QuestionMark

local container
local buttons = {}
local applyQueued = false

local function errorhandler(err)
    return geterrorhandler()(err)
end

local function safecall(func, ...)
    -- WoW's Lua passes extra arguments through xpcall, unlike stock 5.1.
    ---@diagnostic disable-next-line: redundant-parameter
    return xpcall(func, errorhandler, ...)
end

local function placement()
    return ns.Core:UISettings().bar
end

local function spellID(name)
    if not ns.Core:SpellExists(name) then
        return nil
    end
    local info = C_Spell.GetSpellInfo(name)
    return info and info.spellID or nil
end

local function createButton(i)
    local b = CreateFrame("Button", "HealMeBarButton" .. i, container, "SecureActionButtonTemplate")
    -- Both edges, so the cast honours the player's key-down setting as
    -- Blizzard's own buttons do.
    b:RegisterForClicks("AnyUp", "AnyDown")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)

    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints()

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.count:Hide()

    b:SetScript("OnEnter", function(self)
        if self.spellID and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    b:Hide()
    return b
end

-- Display only. Start, duration and modRate go straight into the cooldown
-- frame, which accepts Secret Values; nothing here compares them. Mirrors
-- ActionButton_ApplyCooldown in Blizzard_ActionBar/Shared/ActionButton.lua.
local function refreshButton(b)
    if not b.spellID then
        b.cooldown:Clear()
        b.count:Hide()
        return
    end

    local info = C_Spell.GetSpellCooldown(b.spellID)
    if info and info.isActive then
        b.cooldown:SetCooldown(info.startTime, info.duration, info.modRate)
    else
        b.cooldown:Clear()
    end

    local charges = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(b.spellID)
    if charges and charges.maxCharges and charges.maxCharges > 1 then
        b.count:SetText(charges.currentCharges)
        b.count:Show()
    else
        b.count:Hide()
    end

    if C_Spell.IsSpellUsable then
        local usable, noMana = C_Spell.IsSpellUsable(b.spellID)
        if usable then
            b.icon:SetVertexColor(1, 1, 1)
        elseif noMana then
            b.icon:SetVertexColor(0.5, 0.5, 1)
        else
            b.icon:SetVertexColor(0.4, 0.4, 0.4)
        end
    end
end

function Bar:RefreshCooldowns()
    for i = 1, #buttons do
        if buttons[i]:IsShown() then
            safecall(refreshButton, buttons[i])
        end
    end
end

local function raidStyleParty()
    if EditModeManagerFrame and EditModeManagerFrame.UseRaidStylePartyFrames then
        local ok, on = pcall(EditModeManagerFrame.UseRaidStylePartyFrames, EditModeManagerFrame)
        if ok then
            return on and true or false
        end
    end
    return CompactPartyFrame and CompactPartyFrame:IsShown() or false
end

local function anchor(count)
    local name = Bar.AnchorTarget(IsInRaid(), IsInGroup(), raidStyleParty())
    local target = name and _G[name]
    container:ClearAllPoints()
    if not target or count == 0 then
        container:Hide()
        return
    end
    if placement().side == "below" then
        container:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -Bar.GAP)
    else
        container:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 0, Bar.GAP)
    end
    container:Show()
end

-- The one entry point. Writes attributes, so it queues in combat and runs
-- on PLAYER_REGEN_ENABLED. A slot whose spell this spec does not know keeps
-- its place, greyed, with no attribute: clicking it does nothing.
function Bar:Apply()
    if not container then
        return
    end
    if InCombatLockdown() then
        applyQueued = true
        return
    end
    applyQueued = false

    local list = ns.Core:Bar()
    local size = placement().size or Bar.DEFAULT_SIZE
    local width, offsets = Bar.Layout(#list, size)

    for i = 1, Bar.MAX_SLOTS do
        local b = buttons[i]
        local name = list[i]
        local id = name and spellID(name)
        if id then
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", name)
        else
            b:SetAttribute("type", nil)
            b:SetAttribute("spell", nil)
        end
        b.spellID = id
        if name then
            b.icon:SetTexture(id and C_Spell.GetSpellTexture(id) or FALLBACK_ICON)
            b.icon:SetDesaturated(id == nil)
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("LEFT", container, "LEFT", offsets[i], 0)
            b:Show()
        else
            b:Hide()
        end
    end

    container:SetSize(math.max(width, 1), size)
    anchor(#list)
    self:RefreshCooldowns()
end

function Bar:SlotCount()
    local n = 0
    for i = 1, #buttons do
        if buttons[i]:IsShown() then
            n = n + 1
        end
    end
    return n
end

function Bar:Initialize()
    if container then
        return
    end
    container = CreateFrame("Frame", "HealMeBar", UIParent)
    container:Hide()
    for i = 1, Bar.MAX_SLOTS do
        buttons[i] = createButton(i)
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    events:RegisterEvent("SPELL_UPDATE_CHARGES")
    events:RegisterEvent("SPELL_UPDATE_USABLE")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if applyQueued then
                safecall(Bar.Apply, Bar)
            end
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            -- The anchor target may have changed; Apply re-anchors and
            -- queues itself if this lands mid-fight.
            safecall(Bar.Apply, Bar)
        else
            safecall(Bar.RefreshCooldowns, Bar)
        end
    end)
    self.events = events

    -- Edit Mode moves the raid frames; follow them when it closes.
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            safecall(Bar.Apply, Bar)
        end, Bar)
    end

    self:Apply()
end
```

In `HealMe/Core.lua`, `Core:ApplyAll`:

```lua
function Core:ApplyAll()
    if ns.Secure and ns.Secure.ApplyAll then
        ns.Secure:ApplyAll()
    end
    if ns.Bar and ns.Bar.Apply then
        ns.Bar:Apply()
    end
end
```

In `Core:OnLogin`, after the `ns.Secure` block and before `ns.Options`:

```lua
    if ns.Bar and ns.Bar.Initialize then
        ns.Bar:Initialize()
    end
```

Add to `.luacheckrc` `read_globals`, on a new line after the `"IsInRaid", "IsInGroup", "GetRealmName",` line:

```lua
    "CompactRaidFrameContainer", "CompactPartyFrame", "PartyFrame", "EventRegistry",
```

Add the same four names to `.luarc.json`'s `diagnostics.globals` array.

- [ ] **Step 3: Run the smoke test and the suite**

Run the smoke command. Expected: `smoke ok`. Run the test command. Expected: `0 failed`. Delete the scratch file when done (it lives outside the repo).

- [ ] **Step 4: Amend the spec for two details settled here**

In `docs/superpowers/specs/2026-09-09-cooldown-bar-design.md`:

- §4, replace "leaves its slot empty with no icon; the button carries no attribute and clicking it does nothing" with "keeps its slot, greyed with a question-mark icon; the button carries no attribute and clicking it does nothing".
- §5 "Applying", replace "`Secure:FlushQueues` calls it on `PLAYER_REGEN_ENABLED`" with "the bar's own event frame calls it on `PLAYER_REGEN_ENABLED`, keeping the module self-contained".

- [ ] **Step 5: Lint and commit**

Run both lint commands; expect zero findings.

```bash
git add HealMe/Bar.lua HealMe/Core.lua .luacheckrc .luarc.json docs/superpowers/specs/2026-09-09-cooldown-bar-design.md
git commit -m "Draw the cooldown bar: secure slots, cooldown swipes, anchored to the group frames"
```

---

### Task 5: The Bar tab

**Files:**
- Modify: `HealMe/Options.lua` (state locals ~line 51, `buildWindow` ~line 1041, `Options:Initialize` ~line 1344, new page builder and refresh placed after the Profiles page section)

**Interfaces:**
- Consumes: `Core:Bar()`, `Core:AddBarSpell`, `Core:RemoveBarSpell`, `Core:MoveBarSpell`, `Core:SpellExists`, `Core:UISettings().bar`, `Bar.SIZES`, `Bar:Apply()`, `Widgets.ListRow / Panel / ScrollFrame / EditBox / Button / SpellbookPicker / Icon / Heading / Dropdown / Note / Confirm / ActionIcon`.
- Produces: tab order `Bindings, Bar, Settings, Profiles, Help`; `ui.pages` in the same order.

- [ ] **Step 1: Write a throwaway smoke test**

Frames only. In the scratchpad create `scratch_options_smoke.lua`, a permissive stub that loads `Widgets.lua` then `Options.lua` with a shared `ns`, stubs `ns.Core` (`Bar`, `Bindings`, `Settings`, `ProfileNames`, `ProfileSummaries`, `SpellExists`, `UISettings`, `RegisterListener`, `SpecName`, `Rules`, `profileName`), `ns.Bar` (`SIZES`, `Apply`), `ns.Native`, `ns.Help`, `ns.SelfTest`, `ns.MinimapButton`, and calls `Options:Initialize()`, `Options:Open()`, then `Options:SelectTab(2)` and `Options:Refresh()`. Model the frame stub on the one in Task 4 but let `CreateFontString`, `CreateTexture`, `GetText`, `HasFocus`, `IsShown`, `GetWidth` return sensible values (`""`, `false`, `true`, `300`). The exact stub is throwaway; its job is to reach the Bar page's build and refresh without a nil error. Expected before implementation: `Options:SelectTab(2)` refreshes the Settings page, so nothing fails yet; the check is that after implementation, tab 2 is the Bar page and `refreshBar` runs clean.

- [ ] **Step 2: Implement the page**

Add state next to `selectedProfile`:

```lua
local selectedBar = nil
local barError = nil
```

Add a new section after the Profiles page's `refreshProfiles` and before the Settings page section:

```lua
---------------------------------------------------------------------------
-- Bar page
---------------------------------------------------------------------------

local SIDE_LABEL = { above = "Above the frames", below = "Below the frames" }
local SIDE_ORDER = { "above", "below" }

local function barAction(ok, err)
    barError = (not ok and err) or nil
    Options:Refresh()
end

local function newBarRow(index)
    local content = ui.barContent
    local row = W.ListRow(content, content:GetWidth(), ROW_HEIGHT, 32)
    row:SetScript("OnClick", function(self)
        selectedBar = self.index
        barError = nil
        Options:Refresh()
    end)
    ui.barRows[index] = row
    return row
end

local function buildBarPage(f)
    local page = CreateFrame("Frame", nil, f.content)
    page:SetAllPoints()
    page:Hide()
    ui.barPage = page

    ------------------------------------------------------------ list
    local list = W.Panel(page)
    list:SetPoint("TOPLEFT", MARGIN, -MARGIN)
    list:SetPoint("BOTTOMLEFT", MARGIN, MARGIN + 34)
    list:SetWidth(LIST_WIDTH)

    local scroll = W.ScrollFrame(list, LIST_WIDTH - 22)
    ui.barContent = scroll.content
    ui.barRows = {}

    ui.barEmpty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ui.barEmpty:SetPoint("CENTER")
    ui.barEmpty:SetWidth(220)
    ui.barEmpty:SetText("Nothing on the bar yet.\nPick a spell below to add one.")

    -- Adding: the spellbook picker or a typed name, then Add. Under the
    -- list, where New profile sits on the other tab.
    local function add(name)
        local ok, err = ns.Core:AddBarSpell(name)
        if ok then
            ui.barName:SetText("")
            selectedBar = #ns.Core:Bar()
        end
        barAction(ok, err)
    end

    ui.barName = W.EditBox(page, 118, function() end)
    ui.barName:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 6, -8)
    ui.barAdd = W.Button(page, "Add", 54, function() add(ui.barName:GetText()) end)
    ui.barAdd:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -8)
    ui.barPick = W.SpellbookPicker(page, 86, add)
    if ui.barPick then
        ui.barPick:SetPoint("LEFT", ui.barName, "RIGHT", 6, 0)
    end

    ------------------------------------------------------------ selection
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT", list, "TOPRIGHT", 24, 0)
    header:SetPoint("RIGHT", -MARGIN, 0)
    header:SetHeight(62)

    ui.barIcon = W.Icon(header, 58)
    ui.barIcon:SetPoint("TOPLEFT", 0, -4)

    ui.barTitle = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    ui.barTitle:SetPoint("TOPLEFT", ui.barIcon, "TOPRIGHT", 14, -4)
    ui.barTitle:SetPoint("RIGHT", 0, 0)
    ui.barTitle:SetJustifyH("LEFT")
    ui.barTitle:SetWordWrap(false)

    ui.barState = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    ui.barState:SetPoint("TOPLEFT", ui.barTitle, "BOTTOMLEFT", 0, -10)
    ui.barState:SetJustifyH("LEFT")

    local plate = W.Panel(page)
    plate:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    plate:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)

    ui.barPlateEmpty = plate:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ui.barPlateEmpty:SetPoint("TOP", 0, -40)
    ui.barPlateEmpty:SetWidth(280)
    ui.barPlateEmpty:SetText("Pick a spell on the left to move or remove it.")

    ui.barError = plate:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ui.barError:SetPoint("BOTTOMLEFT", 20, 4)
    ui.barError:SetPoint("RIGHT", -20, 0)
    ui.barError:SetHeight(24)
    ui.barError:SetJustifyH("LEFT")
    ui.barError:SetTextColor(1, 0.45, 0.35)

    local X = 30
    local y = -24

    ui.barUp = W.Button(plate, "Move up", 100, function()
        if selectedBar and ns.Core:MoveBarSpell(selectedBar, -1) then
            selectedBar = selectedBar - 1
        end
        barAction(true)
    end)
    ui.barUp:SetPoint("TOPLEFT", X, y)
    ui.barDown = W.Button(plate, "Move down", 100, function()
        if selectedBar and ns.Core:MoveBarSpell(selectedBar, 1) then
            selectedBar = selectedBar + 1
        end
        barAction(true)
    end)
    ui.barDown:SetPoint("LEFT", ui.barUp, "RIGHT", 8, 0)
    ui.barRemove = W.Button(plate, "Remove", 100, function()
        local name = ns.Core:Bar()[selectedBar or 0]
        if not name then
            return
        end
        W.Confirm("Remove " .. name .. " from the bar?", function()
            ns.Core:RemoveBarSpell(selectedBar)
            selectedBar = nil
            barAction(true)
        end)
    end)
    ui.barRemove:SetPoint("LEFT", ui.barDown, "RIGHT", 8, 0)
    y = y - 40
    ui.barWidgets = { ui.barUp, ui.barDown, ui.barRemove }

    ------------------------------------------------------------ placement
    -- Placement belongs to the interface, not the selection, so it shows
    -- whenever the tab does, like the rules section on Profiles.
    ui.barPlacement = W.Heading(plate, "Placement", 260)
    ui.barPlacement:SetPoint("TOPLEFT", X, y - 30)
    y = y - 66

    local function setSide(value)
        local bar = ns.Core:UISettings().bar
        local previous = bar.side
        bar.side = value
        if value ~= "above" and value ~= "below" then
            bar.side = previous
            return
        end
        ns.Bar:Apply()
        Options:Refresh()
    end
    local function setSize(value)
        local bar = ns.Core:UISettings().bar
        local previous = bar.size
        bar.size = tonumber(value)
        if not bar.size then
            bar.size = previous
            return
        end
        ns.Bar:Apply()
        Options:Refresh()
    end

    local sizeLabels = {}
    for i = 1, #ns.Bar.SIZES do
        sizeLabels[ns.Bar.SIZES[i]] = ns.Bar.SIZES[i] .. " px"
    end

    local sideLabel = plate:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sideLabel:SetPoint("TOPLEFT", X + 4, y)
    sideLabel:SetText("Side")
    ui.barSide = W.Dropdown(plate, 180, SIDE_ORDER, SIDE_LABEL,
        function() return ns.Core:UISettings().bar.side end, setSide)
    ui.barSide:SetPoint("LEFT", sideLabel, "LEFT", 60, 0)
    y = y - 34

    local sizeLabel = plate:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sizeLabel:SetPoint("TOPLEFT", X + 4, y)
    sizeLabel:SetText("Size")
    ui.barSize = W.Dropdown(plate, 180, ns.Bar.SIZES, sizeLabels,
        function() return ns.Core:UISettings().bar.size end, setSize)
    ui.barSize:SetPoint("LEFT", sizeLabel, "LEFT", 60, 0)
    y = y - 40

    local note = W.Note(plate, "The bar sits on Blizzard's raid or party frames and hides when they are "
        .. "not on screen, including while solo. Buttons cast with no target: use it for "
        .. "raid cooldowns such as Tranquility or Halo. Spells this spec does not know stay "
        .. "greyed until you switch back.", 460)
    note:SetPoint("TOPLEFT", X + 4, y)
end

local function refreshBar()
    local list = ns.Core:Bar()
    local y = 0
    for i = 1, #list do
        local row = ui.barRows[i] or newBarRow(i)
        local known = ns.Core:SpellExists(list[i])
        row.index = i
        row.name:SetText(list[i])
        if known then
            row.name:SetTextColor(1, 1, 1)
            row.detail:SetText("Slot " .. i)
            row.detail:SetTextColor(1, 0.82, 0)
        else
            row.name:SetTextColor(1, 0.45, 0.35)
            row.detail:SetText("Not known by this spec")
            row.detail:SetTextColor(1, 0.45, 0.35)
        end
        row.icon:SetIcon(W.ActionIcon({ kind = "spell", spell = list[i] }))
        row.icon:SetDimmed(not known)
        row:SetSelected(i == selectedBar)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:Show()
        y = y + ROW_HEIGHT
    end
    for i = #list + 1, #ui.barRows do ui.barRows[i]:Hide() end
    ui.barContent:SetHeight(math.max(1, y))
    ui.barEmpty:SetShown(#list == 0)

    if selectedBar and not list[selectedBar] then
        selectedBar = nil
    end
    local name = selectedBar and list[selectedBar]

    for i = 1, #ui.barWidgets do ui.barWidgets[i]:SetShown(name ~= nil) end
    ui.barPlateEmpty:SetShown(name == nil)
    ui.barIcon:SetShown(name ~= nil)
    ui.barTitle:SetShown(name ~= nil)
    ui.barState:SetShown(name ~= nil)
    ui.barError:SetText(barError or "")
    ui.barError:SetShown(barError ~= nil)
    ui.barSide:Refresh()
    ui.barSize:Refresh()

    if not name then
        return
    end
    ui.barTitle:SetText(name)
    ui.barIcon:SetIcon(W.ActionIcon({ kind = "spell", spell = name }))
    ui.barState:SetText("Slot " .. selectedBar .. " of " .. #list)
    ui.barUp:SetEnabled(selectedBar > 1)
    ui.barDown:SetEnabled(selectedBar < #list)
end
```

In `buildWindow`, change the tab names and add the page build:

```lua
    ui.tabs = W.Tabs(f, { "Bindings", "Bar", "Settings", "Profiles", "Help" }, function(index)
```

```lua
    buildBindingsPage(f)
    buildBarPage(f)
    buildProfilesPage(f)
    buildSettingsPage(f)
    buildHelpPage(f)
```

In `Options:Initialize`, the pages list in tab order:

```lua
    ui.pages = {
        { frame = ui.bindingsPage, refresh = function() refreshList() refreshEditor() end },
        { frame = ui.barPage, refresh = refreshBar },
        { frame = ui.settingsPage, refresh = refreshSettings },
        { frame = ui.profilesPage, refresh = refreshProfiles },
        { frame = ui.helpPage, refresh = refreshHelp },
    }
```

Search the file for any other place that assumes tab indexes (for example a "go to Settings tab" call using `SelectTab(2)`) and update the index. `grep -n "SelectTab\|Select(" HealMe/Options.lua HealMe/Core.lua HealMe/Minimap.lua`.

Also check `Widgets.Tabs`: five tabs at `minTabWidth = 100` fit the 814 px window; the fallback strip is `#names * 104` wide and also fits.

- [ ] **Step 3: Run the smoke test and the suite**

Run the smoke script; expected `smoke ok` (or whatever final print it makes) with no nil errors on tab 2. Run the test command; expected `0 failed`.

- [ ] **Step 4: Lint and commit**

Run both lint commands; expect zero findings (watch for an unused `y` or `note` local; assign the note's return or drop the local).

```bash
git add HealMe/Options.lua
git commit -m "Add the Bar tab: add, reorder, remove spells and set placement"
```

---

### Task 6: Self-test, help, docs

**Files:**
- Modify: `HealMe/SelfTest.lua` (new `checkBar`, called from `SelfTest.Run` after `checkNative`)
- Modify: `HealMe/Help.lua` (new topic after "Actions besides spells")
- Modify: `docs/manual-test-checklist.md` (new section before "Diagnostics")
- Modify: `docs/superpowers/specs/2026-09-06-healme-design.md` (§4, §8, §19)
- Modify: `README.md` (feature list)

**Interfaces:**
- Consumes: `Bar:SlotCount()`, `Core:Bar()`.

- [ ] **Step 1: Add the self-test check**

In `HealMe/SelfTest.lua`, after `checkNative`:

```lua
local function checkBar(r)
    local Bar, Core = ns.Bar, ns.Core
    if not Bar or not Bar.SlotCount then
        r("warn", "cooldown bar module missing")
        return
    end
    local want = #Core:Bar()
    local have = Bar:SlotCount()
    local container = _G["HealMeBar"]
    if not container then
        r("fail", "cooldown bar container missing")
        return
    end
    r(have == want and "pass" or "fail", "cooldown bar shows " .. have .. " of " .. want .. " slots")
    if want > 0 and not container:IsShown() then
        r("warn", "cooldown bar is hidden: no Blizzard raid or party frames on screen")
    end
end
```

Call it in `SelfTest.Run` right after `checkNative(r)`:

```lua
    checkNative(r)
    checkBar(r)
    checkRoundTrip(r)
```

`_G` is standard Lua, already allowed by luacheck's `lua51` std.

- [ ] **Step 2: Add the Help topic**

In `HealMe/Help.lua`, insert after the "Actions besides spells" entry:

```lua
    {
        title = "The cooldown bar",
        body = {
            "The " .. gold("Bar") .. " tab puts a row of spell buttons on top of, or under, "
                .. "Blizzard's raid or party frames, so long cooldowns such as Tranquility or "
                .. "Halo sit where you are already looking. Each button shows the cooldown and "
                .. "casts when clicked.",
            "Buttons cast with no target, so they suit raid-wide cooldowns. A spell that "
                .. "needs a target still goes to your current target, the same as pressing it "
                .. "on an action bar.",
            "The bar is part of the profile, so it swaps with your specialisation. "
                .. gold("Side") .. " and " .. gold("Size") .. " are shared by every profile. "
                .. "The bar hides while solo and with raid frames from another addon.",
        },
    },
```

- [ ] **Step 3: Add the checklist section**

In `docs/manual-test-checklist.md`, before `## Diagnostics`:

```markdown
## Cooldown bar

What this section is watching for: attribute writes in combat, a bar that
loses its raid frames, and a spell list that does not follow the profile.
The bar hides on purpose while solo and when Blizzard's group frames are not
on screen.

- [ ] Bar tab: pick Tranquility (or any raid cooldown) from Spellbook; it
      appears in the list with its icon. Add a second spell.
- [ ] Adding the same spell again is refused with a message under the plate
- [ ] Typing a made-up name and pressing Add is refused
- [ ] Join a party or raid: the bar appears above the group frames, left
      edges aligned, one button per spell
- [ ] *(self-test)* "cooldown bar shows N of N slots"
- [ ] Side: Below moves it under the frames; Size changes the buttons
- [ ] Open Edit Mode, drag the raid frames, exit: the bar follows
- [ ] Hover a button: the spell tooltip shows
- [ ] Click a button out of combat: the spell casts
- [ ] Pull a mob, click a button: it casts, and the swipe and countdown run
- [ ] While in combat, open the Bar tab and add a spell: the new button
      appears only after combat ends, with no Lua error
- [ ] Select a spell, Move up / Move down: the bar reorders
- [ ] Remove: the popup asks first; the bar shrinks
- [ ] Switch specialisation: the bar changes with the profile; a spell the
      new spec lacks shows greyed with a question mark and a red row
- [ ] Leave the group: the bar hides. Rejoin: it returns
- [ ] Export, then import into another profile: the bar comes along and the
      confirm text says so
- [ ] `/reload` in a raid: no Lua errors, bar in place
```

- [ ] **Step 4: Amend the main design spec**

In `docs/superpowers/specs/2026-09-06-healme-design.md`:

- §4 "In scope", add a bullet: `- A cooldown bar: a row of unit-less spell buttons anchored to Blizzard's raid or party frames, with cooldown swipes. See `2026-09-09-cooldown-bar-design.md`.`
- §4 "Out of scope", change `- Bindings that fire without a frame under the cursor.` to `- Bindings that fire without a frame under the cursor, except the cooldown bar's own buttons.`
- §8 "Modules", add a line for `Bar` matching the surrounding style: `Bar` — the cooldown bar: secure spell slots, cooldown display, anchoring to the group frames.
- §19 "Deliberately deferred", add: `- Free-floating placement of the cooldown bar for third-party raid frames.`

Read the surrounding text first and match its formatting exactly.

- [ ] **Step 5: README feature line**

In `README.md`'s feature list (the bullets under "Why not the built-in click-casting?"), add:

```markdown
- A cooldown bar for raid-wide spells, glued above or below your raid frames
```

- [ ] **Step 6: Run the suite, lint, commit**

Run the test command; expected `0 failed`. Run both lint commands; expect zero findings.

```bash
git add HealMe/SelfTest.lua HealMe/Help.lua docs/manual-test-checklist.md docs/superpowers/specs/2026-09-06-healme-design.md README.md
git commit -m "Cover the cooldown bar in the self-test, help, checklist and docs"
```

---

### Task 7: In-game verification

**Files:** none changed unless a check fails.

- [ ] **Step 1: Copy the addon into the game and run the checklist's "Cooldown bar" section.** Report each line's result to the user. Any failure goes through superpowers:systematic-debugging before a fix, and the fix gets its own commit.

- [ ] **Step 2: Run `/healme selftest`** out of combat in a group and confirm 0 failed.
