local _, ns = ...
ns = ns or {}

-- The Help tab's content: a list of topics, each a title and paragraphs.
-- Plain data so it can be edited without touching the panel. Gold marks a
-- control's name as it appears on another tab; nothing else is coloured.

local G = "|cffffd100" -- gold, the game's own highlight colour
local R = "|r"

local function gold(text)
    return G .. text .. R
end

ns.Help = {
    {
        title = "Getting started",
        body = {
            "HealMe casts on whichever unit frame is under your cursor when you click it, "
                .. "so you heal by pointing at people instead of targeting them first.",
            "On the " .. gold("Bindings") .. " tab press " .. gold("New binding") .. ". "
                .. "Pick a mouse button, tick any modifier keys to hold, choose the spell from "
                .. gold("Spellbook") .. " or type its name, then tick " .. gold("Enabled") .. ". "
                .. "The binding works immediately; there is nothing to reload.",
            "A new binding starts disabled and lands on plain left click. Give it a button, "
                .. "modifiers and a spell before enabling it, or it would take over left click "
                .. "with a cast of nothing.",
            "Two bindings cannot share the same button and modifiers. HealMe tells you which "
                .. "one already holds the combination.",
        },
    },
    {
        title = "Actions besides spells",
        body = {
            gold("Run a macro") .. " runs macro text of your own on the hovered unit. Use "
                .. "@mouseover in it, or it will act on your target instead.",
            gold("Target") .. " and " .. gold("Set focus") .. " do what they say. "
                .. gold("Open unit menu") .. " shows the right-click menu, which is how you "
                .. "keep the menu on a button you have not bound to a heal.",
            gold("Also target when casting") .. ", on the " .. gold("Settings") .. " tab, "
                .. "makes every casting click also switch your target, so your action bar "
                .. "follows your mouse.",
        },
    },
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
                .. "The bar hides while solo and with raid frames from another addon. In a "
                .. "raid it lines up with the left edge of the raid container, which is the "
                .. "main-tank column when you show one.",
            "Like the game's action bars, every button swipes briefly on the global "
                .. "cooldown after any cast. A spell your current spec does not know keeps its "
                .. "slot, greyed, until you switch back. If a chat line ever says a bar display "
                .. "is off for the session, the game refused a value; the buttons still cast, "
                .. "and the line is worth pasting into a bug report.",
        },
    },
    {
        title = "Conditions",
        body = {
            "Each binding can be limited to " .. gold("Friendly only") .. " or "
                .. gold("Hostile only") .. " units, to units that are " .. gold("Alive only")
                .. " or " .. gold("Dead only") .. ", and to " .. gold("In combat") .. " or "
                .. gold("Out of combat") .. ". A binding whose conditions fail does nothing "
                .. "on that click.",
            "Conditions are evaluated by the game itself at the moment you click, using the "
                .. "same rules as macro conditionals. That is why they are limited to what a "
                .. "macro can express.",
            "Health and buffs cannot be conditions. Since Midnight the game hides combat "
                .. "state from addons as secret values, so no addon can check whether someone "
                .. "is below half health or carries a dispellable debuff. HealMe wires up "
                .. "buttons; you aim them.",
        },
    },
    {
        title = "Which frames a binding works on",
        body = {
            gold("On frames") .. " limits a binding to kinds of frame: your player portrait, "
                .. "the target and focus frames, your pet, the party frames, the raid frames, "
                .. "or frames drawn by other addons. Leave every kind ticked and the binding "
                .. "works everywhere.",
            "A common use is keeping a heal off your own portrait so right-click still opens "
                .. "your menu there, while it casts on party and raid frames.",
            "The party frame includes you. If you appear in it, a binding scoped to Party "
                .. "will cast on that copy of you. The Player kind is only the portrait with "
                .. "the level ring.",
            "Frames from other unit-frame addons all count as one kind, since they "
                .. "reshuffle their units too often to sort any finer.",
        },
    },
    {
        title = "Profiles and automatic switching",
        body = {
            "A profile is a set of bindings. HealMe makes one per character and "
                .. "specialisation and switches between them as you change spec. The "
                .. gold("Profiles") .. " tab lists them with their binding counts; the picker in "
                .. "the top strip switches by hand.",
            "Make your own with " .. gold("New profile") .. ". " .. gold("Copy into active")
                .. " replaces the active profile's bindings with the selected one's, "
                .. gold("Rename") .. " and " .. gold("Delete") .. " do as they say, and "
                .. gold("Reset to empty") .. " clears the active profile. The active profile "
                .. "cannot be deleted; switch away first.",
            gold("Automatic switching") .. " names the profile your current spec uses solo, "
                .. "in a party and in a raid. It applies when your spec or group changes, "
                .. "including a party being converted to a raid. A profile you pick by hand "
                .. "stays until the next such change.",
        },
    },
    {
        title = "Mouse wheel",
        body = {
            "Wheel up and wheel down can be bound like buttons. They only fire while your "
                .. "cursor is over a unit frame; everywhere else the wheel zooms the camera "
                .. "as usual.",
            "The wheel is not a click, so HealMe binds it only while you hover a frame and "
                .. "releases it when you leave. If a frame vanishes under your cursor the "
                .. "binding is released as well.",
        },
    },
    {
        title = "Blizzard's own click-casting",
        body = {
            "The game has its own click-casting, in the spellbook under "
                .. gold("Click Casting") .. ". It runs beside HealMe, not under it: a spell "
                .. "bound there fires on every frame no matter what HealMe's bindings or "
                .. "frame scopes say.",
            "Clear the spells from that window and keep HealMe as the only thing casting. "
                .. "HealMe prints a reminder at login while any remain, shows the same on the "
                .. gold("Settings") .. " tab, and " .. gold("Open Click Casting")
                .. " takes you there.",
        },
    },
    {
        title = "Sharing bindings",
        body = {
            gold("Export") .. " on the " .. gold("Settings") .. " tab produces a string you can "
                .. "paste anywhere. " .. gold("Import") .. " replaces every binding in the active "
                .. "profile with the ones in a string, after asking. Bindings the game does "
                .. "not recognise, such as a spell from another class, are skipped and counted.",
            "Frame scopes travel with the string. Strings from older versions import with "
                .. "every binding on all frames.",
        },
    },
    {
        title = "Bugs, questions and updates",
        body = {
            "HealMe lives on GitHub at github.com/CoffeeAndLoot/healme. New versions are "
                .. "published there as releases, and WowUp can install and update from that "
                .. "page.",
            "Found a bug or want something added? Open an issue there. The " .. gold("Settings")
                .. " tab has the link in a box you can copy with Ctrl+C. Before reporting, run "
                .. gold("Run self-test") .. " on that tab and paste its output into the "
                .. "report; it tells us most of what we would otherwise have to ask.",
            "The game cannot open a web page itself, which is why the link is a box to copy "
                .. "rather than a button.",
        },
    },
    {
        title = "Slash commands",
        body = {
            "/healme opens this window. /healme status prints the version, profile, "
                .. "binding and bar counts and the frame count. /healme profile lists profiles; /healme profile <name> "
                .. "switches to one, creating it if needed.",
            "/healme native opens the game's click-casting window. /healme diag prints "
                .. "how the wheel is wired. /healme clear removes every binding from the "
                .. "active profile.",
        },
    },
}

return ns.Help
