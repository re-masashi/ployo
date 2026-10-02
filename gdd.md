# Ployo

friendslop survival simulation game where you're all stuck in a sinking ship and need to get home.

your objective is to cooperatively maneuver the ship, fix different issues in the ship, collect supplies and finish tasks and prevent the ship from exploding and just survive and get home.

the ship is procedurally generated. the maps are procedurally generated too.
parts of the ship fail. you hav to fix them. also have to refuel etc, fix elctricity, get food, etc.

you might need to steer the ship in certain directions to head home. sometimes you might need to take a different route in order to collect supplies.

## Dev Principles

build small, build complete, ship fast and ship a nice consistent experience.

## Core Loop

Spawn -> assess ship -> split tasks -> steer/repair/refuel -> survive events -> reach home. Fail = ship explodes/sinks. Win = dock at home port.

## Goals

initially we get procgen working.
then get the task-able things working.
then we get map + controls working.
for oceansim, ill figure something out.

## Multiplayer

ENet + GodotSteam

## OceanSim

render only near the player. fft maybe
fog or something or impostors for far away stuff.
prefer GPU driven oceansim.

## Scripting

C#
