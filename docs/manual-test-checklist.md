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

## Task 10 — mouse wheel bindings

- [ ] `/healme bind wheelup rejuvenation` prints a confirmation
- [ ] Hovering a raid frame and scrolling up casts Rejuvenation on that unit
- [ ] Scrolling up while NOT over a raid frame does its normal thing (scrolls
      the chat frame, zooms the camera) — the binding must not leak
- [ ] Move the cursor off the frame and scroll: still no cast
- [ ] `/healme bind wheeldown regrowth`; both directions work independently
- [ ] Hover a party member's frame, have them die while you hover, then scroll:
      no cast, no error (this is the unit-exists guard)
- [ ] Repeat the whole section in combat on a training dummy

Things this checklist is specifically watching for, beyond the literal
steps above:
- A wheel binding that never fires — caught by the wheelup/wheeldown steps
  actually landing the heal on the hovered unit, not just by the absence of
  an error. If `SetBindingClick` never ran (header attribute never set, or
  `WrapScript` never wired up `OnEnter`), scrolling over a frame will simply
  do nothing.
- A wheel binding that leaks — caught explicitly by the "scroll while NOT
  over a raid frame" step and the "move cursor off, then scroll" step. If
  `OnLeave` never clears the binding (or clears the wrong one because
  `UnwrapScript` allowed a duplicate handler to stack), the wheel keeps
  casting after the cursor has left the frame, and normal wheel behavior
  (camera zoom, chat scroll) stops working — both must be checked, since a
  leak can present as either "still casts" or "camera stopped zooming."
- The unit-exists guard failing silently — caught by the death-while-hovering
  step. If the `_onattributechanged` driver is missing or wired to the wrong
  attribute name, the frame hides on death without `OnLeave` firing, and the
  wheel stays bound to a heal on a unit that no longer exists; scrolling
  afterward should do nothing and must not error.
- A mid-combat write throwing or tainting the UI — caught by repeating the
  whole section on a training dummy in combat, same as the click-binding
  checklist above.

## Task 11 — options panel

- [ ] `/healme` with no arguments opens the panel
- [ ] The minimap button opens it too, and Escape closes it
- [ ] The window can be dragged, and stays where it is put
- [ ] "New binding" adds a row under the "Left click" header; selecting it
      shows the editor with the big icon and name header
- [ ] Create a new binding and confirm it appears dimmed with "disabled" in
      its gold subline and does not affect BUTTON1 (its default button) or any existing
      binding on that button. Then set a spell, tick Enabled, and confirm it
      starts working
- [ ] Setting button and spell produces a working click-cast without a reload
- [ ] Typing a nonexistent spell prints "rejected: no such spell: ..." and the
      field reverts
- [ ] Creating a second binding on the same button+modifiers prints
      "that combination is already used by: ..." and reverts
- [ ] Choosing "Open unit menu" hides the "Only when" section
- [ ] Clicking a button header collapses its group and the plus/minus flips;
      the count stays visible while collapsed
- [ ] The Bindings and Settings tabs switch pages; New binding and Delete only
      show on Bindings
- [ ] The window has the round portrait, gold title bar and dark stone
      background of a Blizzard panel, and the dropdowns match the game's own
- [ ] The "Also target" toggle on the Settings tab changes behaviour immediately: with it on, a
      heal click also switches your target
- [ ] Switching specialisation swaps the binding list, and the profile picker
      in the tab strip updates to match
- [ ] Picking another profile from the picker swaps the list and prints nothing
      odd
- [ ] Deleting a binding asks for confirmation and stops the bind firing
- [ ] Create a spell binding, then change its Action to "Run a macro" without
      entering macro text. Expect a rejection message AND the Action dropdown
      to snap back to "Cast a spell". If the dropdown stays on "Run a macro",
      the revert is broken.
- [ ] Create two bindings on the same button and modifiers, disable one, then
      re-enable it. Expect the conflict message and the binding to stay
      disabled.

## Task 12 — export and import

- [ ] Export on the Settings tab shows a string beginning "!HM1!"
- [ ] Copy it, switch to another profile, paste into Import: the bindings appear
      and immediately work
- [ ] Pasting rubbish prints "import failed: that does not look like a HealMe
      binding string"
- [ ] Truncating a valid string by a few characters prints "import failed: the
      binding string is damaged or incomplete" rather than erroring
- [ ] Import a string that contains a deliberately broken binding (e.g. an
      unknown button or a duplicate key): confirm the skipped count appears in
      the message ("imported N bindings (M skipped: invalid or duplicate)")
      and the broken binding does not show up in the list

## Conditional bindings

`Compiler`'s unit tests prove the right macro TEXT is produced for each
condition; they cannot prove Blizzard's own macro engine honours that text
at click time. This section is the only place that gets checked. Requires
a healing spec, a friendly party member (or NPC) alive and reachable, a
hostile target, and a way to see a corpse (a dead party member, or your own
corpse after a training-dummy death).

Before starting: confirm the spell used at each step is known and the test
target is in range. A bind that does nothing because the target is out of
range or the spell is on cooldown looks identical to a condition correctly
declining — do not mistake one for the other. If a step ever seems to fail,
first retest on an in-range target with the spell off cooldown before
concluding the condition is broken.

- [ ] Bind a friendly-only (`help`) heal. Cast on a party member: it fires.
      Click a hostile target with the same bind: nothing is cast, no error.
- [ ] Bind a hostile-only (`harm`) spell. Click a hostile target: it fires.
      Click a friendly target: nothing is cast, no error.
- [ ] Bind an alive-only (`nodead`) heal. Cast on a living party member: it
      fires. Click a corpse with the same bind: nothing is cast, no error.
- [ ] Bind a dead-only (`dead`) resurrection spell. Click a living party
      member: nothing is cast, no error. Click a corpse: it fires.
- [ ] Bind an out-of-combat (`nocombat`) spell. Out of combat, it fires.
      Enter combat (pull a training dummy) and click again: nothing is
      cast, no error. Leave combat and click again, with no `/reload`: it
      fires again immediately.
- [ ] Bind a spell with two conditions at once (e.g. friendly AND alive).
      Confirm both are required by testing a case that satisfies only one
      — a hostile living target, and a friendly corpse — and confirming
      neither casts. Then confirm a friendly, living target does cast.
- [ ] Enable "Also target", then bind a conditional heal (e.g. friendly-only)
      to a button. Click a target for which the condition fails (a hostile
      unit): confirm BOTH that nothing is cast AND that your target does
      not change. This is the guarantee that the cast and the target-switch
      share one condition clause; if the target line were evaluated on its
      own, a declined heal could still retarget you.

Things this section is specifically watching for, beyond the literal steps
above:
- A condition that is silently ignored, so the spell fires on every unit
  regardless of the clause — caught only by the negative half of each step
  above (the click that should do nothing). A step that only checks the
  positive case would pass even if `Compiler` emitted no condition at all.
- A condition that inverts (fires exactly when it should not) — also only
  caught by pairing the positive and negative checks on the same bind.
- The `nocombat` transition specifically: a bind that requires a `/reload`
  to start working again after combat ends means the condition was baked
  into a stale macro rather than re-evaluated live, which defeats the
  point of a secure conditional macro.
- A combined-condition bind that fires when only one of the two conditions
  holds — caught by testing both partially-satisfying cases, not just the
  fully-satisfying one.
- "Also target" leaking past a failed condition — caught explicitly by the
  last step. A retarget on a declined heal is worse than a silent no-op:
  it changes your target without you asking for it, mid-fight.

## Release checklist

Run this section last, after every task section above has passed, before
pushing a version tag.

- [ ] Every earlier section in this file passes
- [ ] Force each restriction scope and confirm no errors:
      `/console secretCombatRestrictionsForced 1`, then the challenge mode,
      encounter and PvP equivalents, testing click-casts under each
- [ ] Test on the addon-author dummies near The MOTHERLODE!! entrance
- [ ] Run a full Mythic+ key with BugSack loaded; the error log is clean
- [ ] Install a third-party frame addon (Grid2, Cell, or ElvUI) and confirm its
      frames register and click-cast
- [ ] Uninstall it and confirm HealMe still works on Blizzard frames

## Minimap button

What this section is watching for: a button that cannot be moved, cannot be
hidden, or forgets where it was put. Its position and hidden flag are stored
account-wide rather than per profile, so changing specialisation must not move
it.

- [ ] A HealMe button sits on the minimap ring after login
- [ ] Clicking it opens the bindings panel; clicking again closes it
- [ ] Hovering shows a tooltip naming the addon
- [ ] Dragging moves it around the ring and it stays where released
- [ ] `/reload` and it is still in the same place
- [ ] Unticking "Show minimap button" in the panel hides it immediately
- [ ] `/reload` while hidden and it stays hidden
- [ ] Re-ticking brings it back in the same position
- [ ] Change specialisation: the button does NOT move and does NOT reappear if
      it was hidden

## Diagnostics

These exist because `WrapScript` leaves no readable mark on a frame, so whether
the wheel handlers were attached cannot be seen any other way.

- [ ] `/healme diag` reports registered and wheel-wrapped frame counts, and they
      match
- [ ] `/healme diag` reports the compiled attribute count, which should be three
      per enabled spell binding
- [ ] `/healme simulate` prints PASS. It deregisters and re-registers the player
      frame, driving the same path a raid frame created after login takes; a
      FAIL here is the raid-frame wheel bug
