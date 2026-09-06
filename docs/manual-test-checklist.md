# HealMe manual test checklist

Automated tests cover `Compiler`, `Bindings`, and `Serialize`. Everything that
touches the WoW API is verified here. Run the whole list before tagging a
release; run the section named by a task after finishing that task.

Setup: `/console scriptErrors 1`, and install BugSack + BugGrabber.

## Task 1 — the addon loads

- [ ] `/healme` prints "HealMe: loaded, version 0.1.0"
- [ ] The addon appears in the addon compartment; clicking it prints the same
- [ ] `/reload` produces no Lua errors

## Task 7 — saved variables and profiles

- [ ] `/reload` produces no Lua errors
- [ ] `/healme status` prints version, a profile named "<Character> - <Spec>",
      "bindings: 0", "also target: false"
- [ ] Switch specialisation; `/healme status` reports the other spec's profile
- [ ] Switch back; the original profile returns
- [ ] Log out and back in; the profile is remembered

## Task 8 — frame registration

- [ ] `/reload` in a raid or party produces no Lua errors
- [ ] `/dump ClickCastHeader ~= nil` prints true
- [ ] `/dump Clique.header ~= nil` prints true
- [ ] `/run local n=0 for f in HealMeNS.Registry:IterateFrames() do n=n+1 end print(n)`
      prints a count greater than zero, and larger in a raid than solo
- [ ] Enable Clique or Clicked, reload: HealMe prints the conflict message and
      does not install the header

In-game, solo: `/reload`, then run each `/dump` and `/run` above.
Expected: `true`, `true`, and a frame count of at least 4 (player, target,
focus, pet frames exist even solo; target/focus frames register regardless of
whether a unit is selected). Join a 5-player group and re-run: the count must
rise.

## Task 9 — click-casting works

Requires a healing spec and a party member or a friendly NPC.

- [ ] `/healme bind button2 rejuvenation` prints "bound BUTTON2 to rejuvenation"
- [ ] `/healme status` reports "bindings: 1"
- [ ] Right-clicking a party member's raid frame casts Rejuvenation on them
- [ ] Right-clicking does NOT open the unit context menu any more
- [ ] `/healme bind button4 regrowth`, then button 4 on a raid frame casts it
      (this is the check that RegisterForClicks is doing its job)
- [ ] Enter combat, `/healme bind button3 swiftmend`: no Lua error, and the bind
      does not work yet
- [ ] Leave combat: the button-3 bind now works, with no reload
- [ ] `/healme clear`, then right-click a raid frame: nothing is cast

In-game, in a party:

```
/healme bind button2 rejuvenation
```

Expected: `HealMe: bound BUTTON2 to rejuvenation`. Then right-click a party
member's frame — Rejuvenation is cast on them.

The combat check matters most: pull a training dummy, run
`/healme bind button3 swiftmend` while in combat, confirm no error appears,
confirm button 3 does nothing, then drop combat and confirm button 3 starts
working without a reload.

Things this checklist is specifically watching for, beyond the literal
steps above:
- A binding that silently does nothing (wrong attribute name or macro text
  from Compiler) — caught by the Rejuvenation cast actually landing on the
  targeted party member, not just by the absence of an error.
- A binding that fires on the wrong unit — caught by watching *who* receives
  the heal, not just that a cast bar appears.
- Buttons 4/5 or the mouse wheel not responding at all — caught by the
  button-4 regrowth step; if `RegisterForClicks`/`EnableMouseWheel` were
  never called, this step fails silently (nothing happens, no error) rather
  than throwing, so it must be checked explicitly every time this module
  changes.
- A mid-combat write throwing or tainting the UI — caught by the swiftmend
  bind-while-in-combat step: no error should appear, the bind should have no
  effect until combat ends, and it must start working the instant combat
  drops with no `/reload` required. Any Lua error here, or any bind that
  needs a reload to start working, means the queue/flush logic is broken.
