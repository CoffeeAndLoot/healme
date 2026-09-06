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
