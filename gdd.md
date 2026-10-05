# Ployo

friendslop game.
you and your friends are on a sinking ship carrying valuables.
most of the people have left the ship. you need to pull a heist and get the things to a part in the deck of the ship as your getaway pilot comes after a certain amount of time.  

you also need to cooperatively maneuver the ship, fix different issues in the ship, collect supplies and finish tasks and prevent the ship from exploding and survive till the getaway pilot gets there.

the ship is procedurally generated. the maps are procedurally generated too.
parts of the ship fail. you hav to fix them. also have to refuel etc, fix elctricity, get food, etc.

however, the heist is primary. other stuff is secondary. but when the ship is actively sinking, you need to address that immediately.

everyone has not headed back so sometimes people might confront you while you're stealing.

in essence, it would be:

REPO (the stealing) x Lethal Company (the timed extraction loop thing)
without the horror.


## Dev Principles

build small, build complete, ship fast and ship a nice consistent experience.

## Core Loop

```
spawn -> assess ship -> split tasks -> find loot
      -> interact with crew (hiding, confronting, throwing them off the ship, etc) -> fix ship when it's dying
      -> carry loot to extraction -> pilot arrives -> flee
```

win: loot is at the extraction point when the pilot arrives.
lose: ship sinks, ship explodes, or you miss the pilot's window.

runs: 15-25 mins

## Design Heierarchy

1- heist
2- ship systems
3- crew

## The Heist

ship contains valuable cargo scattered across rooms.
cargo is heavy. you carry one item. you move at 60% speed.
carrying makes you vulnerable. you can't fight. you can't repair. you can't sprint.
cargo must be carried to the extraction point on the deck.
getaway pilot arrives at a fixed time. not negotiable.
pilot waits 2 mins or something. then leaves.
whatever is at extraction when the pilot lands = saved. everything else = lost.

## The Crew

behaviors:
- idle: 
- suspicious: heard or saw something. investigates.
- hostile:caught you stealing. chases, shouts or swings wrench.
- stunned: you hit them, tripped them, threw something
- carried: you picked them up
- gone: thrown off deck :joycat: :v:

you can also lock them away in a room temporarily

reactions:
- noise: they turn towards loud noise in audible range.
- missing loot: walk past a spot where some loot was. suspicion spikes.
- seeing you carry loot or in a restricted area: hostile immediately

when your'e caught:
- crew swings a wrench. hit -> 2 sec stun.
- stunned while carrying -> drop the crate.
- crew picks up the root, returns it to its original spot.
- stunned without a crate -> crew grabs you, drags you to a random distant room, drops you inside, closes the door, stands guarding outside for 10 to 20 sec. can be prevented if your friends hit them while youre grabbed.
- you wake up. find another way out, wait, or call a teammate.

if you get stunned too often or your health runs too low, you need to be taken to med bay. 

### Throwing Them Offboard

- crew must be stunned or resting to be lifted.
- hoist onto shoulder. move slower while carrying.
- press throw. they arc through the air.
- if not near open air, they bounce and get stunned again.
- if they are past the boundary, they vanish into the sea/ocean.

a fixed number of them spawn at the beginning. they dont multiply. some abandon ship and leave as the run progresses.

## Other Stuff

some places have vending machines. you can have drinks by kicking them.
some give you stats, ohters give you different stats etc.
some blur your vision some give you speed etc.

## Goals

get multiplayer working
get movement, pickup etc mechanics working with multiplayer.
get procgen working.
then get the task-able things working.
then we get map + controls working.
for oceansim, ill figure something out.

## Multiplayer

ENet + GodotSteam

## OceanSim

render only near the player. fft maybe
fog or something or impostors for far away stuff.
prefer GPU driven oceansim.

## ProcGen

REPO like tiled procgen
