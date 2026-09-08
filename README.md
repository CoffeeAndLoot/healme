# HealMe

Click-casting for World of Warcraft healers. Bind spells to mouse buttons and
the mouse wheel, then heal by clicking unit frames instead of targeting and
pressing a key.

Retail only, Midnight 12.1 or later.

## Why not the built-in click-casting?

Retail has shipped native click-casting since 10.1.5. HealMe exists for what it
cannot do:

- Mouse wheel bindings
- Binding sets that swap with your specialisation
- Conditional bindings — friendly only, hostile only, alive, dead, in or out of
  combat
- Third-party unit frames, through the community `ClickCastFrames` protocol
- Export and import, so you can share or version-control your bindings

HealMe replaces native click-casting rather than supplementing it. Native
bindings keep firing beside HealMe's, so clear the spells from Blizzard's
Click Casting window; HealMe warns at login while any remain, and
`/healme native` opens that window.

## Use

`/healme` opens the options panel. Add a binding, pick a button and a spell,
and click a unit frame.

"Also target" makes a casting click switch your target too, so your action bar
follows your mouse.

HealMe will not run alongside Clique or Clicked; all three claim the same
click-casting frames. Disable the others first.

## What it will never do

Pick who to heal. Under Midnight's Secret Values system, addons cannot read
health or aura state to make decisions — that information is deliberately opaque.
HealMe wires up buttons; you aim them.

## Licence

MIT. See LICENSE.
