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
