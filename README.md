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
| Lock / unlock the brig door | F |
| Restart run (after it ends) | R |
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
- drag or throw a stunned crew member into the brig (aft), close the door, and press f to lock them in.
- put out fires, patch leaks, reset breakers, refuel, and clear debris by holding e at the marked task stations. releasing early resets progress and makes noise.
- secure loot on the extraction pad. after about 11 minutes the pilot arrives and waits 3 minutes; reach the loot goal and get it to the pad before he leaves to win.
- the danger bar rises while too many systems are failed or while the bilge is flooding. clear systems fast and deal with leaks. the run ends if danger maxes out, the pilot leaves without the loot, or the crew takes everyone down.
- the SHIP STATUS panel on the right lists system and task state; when the run ends a report explains what went wrong and what to try next. press r to run it again.

