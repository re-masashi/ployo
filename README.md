Running:

```
godot-mono --path game -- --host 7777 --dump &
godot-mono --path game -- --join 127.0.0.1 7777 --dump
```

Controls:

| Action | Input |
|---|---|
| Move | W A S D |
| Jump | Space |
| Sprint | Shift (not while carrying) |
| Crouch (gentle place) | Ctrl or C |
| Interact / grab / place / lift crew / hoist downed teammate / open brig door | E |
| Punch (empty hands) / aim throw | Right click |
| Throw item or crew | Left click |
| Rotate held item | Hold Alt + move mouse |
| Push / pull held item | Mouse wheel |
| Debug stun yourself (drops item) | T |
| Free / capture mouse | Esc |

Mechanics:

- stun crew with a punch or a thrown object, then press e to hoist them over your shoulder. hold right click while carrying to aim a throw, then left click to throw them overboard. idle crew occasionally rest and can be lifted too.
- crew that spot you carrying loot or a downed teammate turn hostile. if they catch you they drag you away, guard you for a while, then leave. friends can punch the guard to free you.
- if a crew member spots loot that has been moved off its original spot, they carry it back.
- crew treat marked restricted areas as off-limits and turn hostile if they see you inside one.
- repair engine / power / fuel / bilge pump by standing next to the marked system and holding e. failed power flickers the lights; a failed bilge pump floods the stern and eventually sinks the ship if left alone.
- press e on a downed teammate to hoist them over your shoulder, carry them at reduced speed, and press e at the med bay to revive and drop them.
- use the med bay (port side) to heal, the galley (aft) for food and a speed buff, and the vending machine (starboard side) to buy a random buff.
- drag or throw a stunned crew member into the brig (aft) and close the door to lock them away for a while.
- secure loot on the extraction pad, then survive until the pilot window opens to win. the run ends if the timer expires or the crew takes everyone down.

