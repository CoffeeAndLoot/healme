local _, ns = ...
ns = ns or {}

local SelfTest = {}
ns.SelfTest = SelfTest

-- An in-game check of everything that can be verified without secure
-- privilege: the art and templates the panel needs, the registry, the
-- bindings themselves, the attributes actually sitting on each frame, the
-- wheel wiring, native click-casting, and the export round trip. Prints a
-- line per check and a summary. Whether a click casts is still the
-- checklist's job; this covers everything up to that point.

local TEMPLATES = {
    "PortraitFrameTemplate", "InsetFrameTemplate", "UIPanelButtonTemplate",
    "UICheckButtonTemplate", "InputBoxTemplate", "WowStyle1DropdownTemplate",
    "TabSystemTemplate", "TabSystemTopButtonTemplate", "MinimalScrollBar",
    "SecureActionButtonTemplate", "SecureHandlerBaseTemplate",
    "SecureHandlerAttributeTemplate",
}

---------------------------------------------------------------------------
-- Pure comparison, unit-tested
---------------------------------------------------------------------------

-- The attributes a frame of `class` should carry given the compiled set,
-- each entry tagged with its binding's frame scope as Secure leaves it.
function SelfTest.ExpectedAttributes(attrs, class)
    local expected = {}
    for i = 1, #attrs do
        local attr = attrs[i]
        if ns.Bindings.FrameAllowed(attr, class) then
            expected[attr.name] = attr.value
        end
    end
    return expected
end

-- Compares what a frame reports for each compiled attribute against what
-- it should hold. `getAttribute(name)` reads the frame. Returns a list of
-- { name, expected, actual }, empty when the frame is right.
function SelfTest.CompareFrame(attrs, class, getAttribute)
    local expected = SelfTest.ExpectedAttributes(attrs, class)
    local problems = {}
    local seen = {}
    for i = 1, #attrs do
        local name = attrs[i].name
        if not seen[name] then
            seen[name] = true
            local want = expected[name]
            local got = getAttribute(name)
            if got ~= want then
                problems[#problems + 1] = { name = name, expected = want, actual = got }
            end
        end
    end
    return problems
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------

local function frameName(frame)
    local ok, name = pcall(function() return frame:GetName() end)
    return (ok and name) or "(unnamed frame)"
end

local function checkEnvironment(r)
    local Widgets = ns.Widgets
    local atlases = {}
    for key, value in pairs(Widgets.ATLAS) do
        if key == "corner" then
            for i = 1, #value do atlases[#atlases + 1] = value[i][1] end
        else
            atlases[#atlases + 1] = value
        end
    end
    local missing = {}
    if C_Texture and C_Texture.GetAtlasInfo then
        for i = 1, #atlases do
            if not C_Texture.GetAtlasInfo(atlases[i]) then
                missing[#missing + 1] = atlases[i]
            end
        end
        r(#missing == 0 and "pass" or "warn", #atlases .. " atlases known"
            .. (#missing > 0 and (", missing: " .. table.concat(missing, ", ")) or ""))
    else
        r("warn", "cannot query atlases on this client")
    end

    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        local gone = {}
        for i = 1, #TEMPLATES do
            if not C_XMLUtil.GetTemplateInfo(TEMPLATES[i]) then
                gone[#gone + 1] = TEMPLATES[i]
            end
        end
        r(#gone == 0 and "pass" or "warn", #TEMPLATES .. " templates present"
            .. (#gone > 0 and (", missing: " .. table.concat(gone, ", ")) or ""))
    else
        r("warn", "cannot query templates on this client")
    end
end

local function checkRegistry(r)
    local Registry = ns.Registry
    if not Registry.header then
        r("fail", "secure header missing: the registry never initialised "
            .. "(another click-cast addon enabled?)")
        return false
    end
    r("pass", "secure header present")
    local shim = Clique and Clique.header == Registry.header
    r(shim and "pass" or "warn", shim and "Clique shim points at the header"
        or "Clique shim missing: older frame addons will not self-register")

    local count = Registry:Count()
    r(count > 0 and "pass" or "fail", count .. " frames registered")

    local expect = { PlayerFrame = "player", TargetFrame = "target", FocusFrame = "focus" }
    for name, class in pairs(expect) do
        local frame = _G[name]
        if not frame then
            r("warn", name .. " does not exist on this client")
        else
            local registered = false
            for f in Registry:IterateFrames() do
                if f == frame then registered = true end
            end
            local got = Registry:FrameClass(frame)
            if registered and got == class then
                r("pass", name .. " registered as " .. class)
            else
                r("fail", name .. (registered and (" classed as " .. got) or " not registered"))
            end
        end
    end

    local plates = 0
    for f in Registry:IterateFrames() do
        if f.namePlateFrame ~= nil then plates = plates + 1 end
    end
    r(plates == 0 and "pass" or "fail", plates .. " nameplates in the registry")
    return true
end

local function checkBindings(r)
    local Core, Bindings = ns.Core, ns.Bindings
    local list = Core:Bindings()
    local enabled, badSpells, clashes = 0, {}, {}
    for i = 1, #list do
        local record = list[i]
        if record.enabled ~= false then
            enabled = enabled + 1
            if record.action.kind == "spell" and not Core:SpellExists(record.action.spell) then
                badSpells[#badSpells + 1] = tostring(record.action.spell)
            end
            local clash = Bindings.FindConflict(list, record)
            if clash and clash.id > record.id then
                clashes[#clashes + 1] = Bindings.KeySignature(record.key)
            end
        end
    end
    r("pass", enabled .. " enabled of " .. #list .. " bindings")
    r(#badSpells == 0 and "pass" or "fail", #badSpells == 0 and "every spell is known"
        or ("unknown spells: " .. table.concat(badSpells, ", ")))
    r(#clashes == 0 and "pass" or "fail", #clashes == 0 and "no two enabled bindings share a combination"
        or ("shared combinations: " .. table.concat(clashes, ", ")))

    local dangling = {}
    for groupType, name in pairs(Core:Rules()) do
        if not HealMeDB.profiles[name] then
            dangling[#dangling + 1] = groupType .. " -> " .. tostring(name)
        end
    end
    r(#dangling == 0 and "pass" or "fail", #dangling == 0 and "profile rules point at real profiles"
        or ("rules pointing nowhere: " .. table.concat(dangling, ", ")))
    return enabled
end

-- Reads every compiled attribute back off every registered frame.
local function verifyFrames(r, label)
    local attrs = ns.Secure.attributes
    local frames, bad, shown = 0, 0, 0
    for frame in ns.Registry:IterateFrames() do
        frames = frames + 1
        local class = ns.Registry:FrameClass(frame)
        local problems = SelfTest.CompareFrame(attrs, class, function(name)
            return frame:GetAttribute(name)
        end)
        local stamped = frame:GetAttribute("healme-frame")
        if stamped ~= class then
            problems[#problems + 1] = { name = "healme-frame", expected = class, actual = stamped }
        end
        if #problems > 0 then
            bad = bad + 1
            if shown < 5 then
                shown = shown + 1
                local p = problems[1]
                r("fail", frameName(frame) .. " (" .. class .. "): " .. p.name .. " is "
                    .. tostring(p.actual) .. ", expected " .. tostring(p.expected)
                    .. (#problems > 1 and (" (+" .. (#problems - 1) .. " more)") or ""))
            end
        end
    end
    r(bad == 0 and "pass" or "fail", label .. ": " .. (frames - bad) .. " of " .. frames
        .. " frames carry exactly the attributes their scope allows")
end

local PROBE_KEY = { button = "BUTTON5", alt = true, ctrl = true, shift = true }

-- With nothing enabled there is nothing on the frames to verify, so apply a
-- throwaway Target binding on a combination nobody uses, verify it, and take
-- it away again. Out of combat this is the same write every edit makes.
local function probeApply(r)
    local Core, Bindings = ns.Core, ns.Bindings
    local list = Core:Bindings()
    local probe = {
        id = Bindings.NextId(list), enabled = true,
        key = PROBE_KEY, action = { kind = "target" },
    }
    if Bindings.FindConflict(list, probe) then
        r("warn", "no enabled bindings and Alt+Ctrl+Shift+Button 5 is taken; apply path not probed")
        return
    end
    list[#list + 1] = probe
    Core:NotifyChanged()
    verifyFrames(r, "probe binding")
    for i = #list, 1, -1 do
        if list[i] == probe then table.remove(list, i) end
    end
    Core:NotifyChanged()
    verifyFrames(r, "after removing the probe")
end

local function checkWheel(r)
    local Secure, Registry = ns.Secure, ns.Registry
    r(Secure.proxy and "pass" or "fail", Secure.proxy and "wheel proxy button exists"
        or "wheel proxy button missing")
    local setup = Registry.header and Registry.header:GetAttribute("healme_setup")
    r(setup and "pass" or "fail", setup and "wheel hover snippet installed"
        or "wheel hover snippet missing")
    local total, wrapped = 0, 0
    for frame in Registry:IterateFrames() do
        total = total + 1
        if Secure:IsWrapped(frame) then wrapped = wrapped + 1 end
    end
    r(wrapped == total and "pass" or "fail", wrapped .. " of " .. total .. " frames have wheel wrappers")
end

local function checkNative(r)
    local list = ns.Native.Bindings()
    if #list == 0 then
        r("pass", "Blizzard's click-casting holds no spell bindings")
    else
        r("warn", ns.Native.Warning(list))
    end
end

local function checkRoundTrip(r)
    local Serialize, Core = ns.Serialize, ns.Core
    local profile = { bindings = Core:Bindings(), settings = Core:Settings() }
    local text = Serialize.Export(profile, Serialize.codec)
    local back, err = Serialize.Import(text, Serialize.codec)
    if not back then
        r("fail", "export does not import: " .. tostring(err))
        return
    end
    local again = Serialize.Export(back, Serialize.codec)
    r(again == text and "pass" or "fail", again == text
        and ("export round-trips " .. #back.bindings .. " bindings")
        or "export changes after one round trip")
end

---------------------------------------------------------------------------
-- Runner
---------------------------------------------------------------------------

local COLOUR = { pass = "|cff40ff40PASS|r", fail = "|cffff4040FAIL|r", warn = "|cffffcc00WARN|r" }

function SelfTest.Run()
    local Core = ns.Core
    if InCombatLockdown and InCombatLockdown() then
        Core:Print("self-test waits for combat to end: attribute writes queue in combat")
        return false
    end

    local counts = { pass = 0, fail = 0, warn = 0 }
    local function r(status, text)
        counts[status] = counts[status] + 1
        Core:Print(COLOUR[status] .. " " .. text)
    end

    Core:Print("self-test, version " .. tostring(Core.version) .. ", profile " .. tostring(Core.profileName))
    checkEnvironment(r)
    if checkRegistry(r) then
        local enabled = checkBindings(r)
        if enabled > 0 then
            verifyFrames(r, "live bindings")
        else
            probeApply(r)
        end
        checkWheel(r)
    else
        checkBindings(r)
    end
    checkNative(r)
    checkRoundTrip(r)

    Core:Print(string.format("self-test done: %d passed, %d failed, %d warnings",
        counts.pass, counts.fail, counts.warn))
    return counts.fail == 0
end

return SelfTest
