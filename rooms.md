## core rooms (always spawn, at least one)

- engine room	(has cooling pipes etc)
- power room	(has a generator, breaker panel, fuse box etc)
- fuel bay and bilge	(fuel tanks, pump, valves, water gauge, etc. can flood or fuel pump can fail)
- galley	    (stove, fridge, water tank, pantry)
- storage  	(crates, shelves, tools. some for players. some stuff which "needs to reach home safe")

## support rooms (random spawn)

- morgue
- server room
- bathroom
- cafeteria
- passenger bedrooms
- crew quarters
- med bay (mabi later. carry a friend here n heal them)
- library

## layers

- l5  surface        <- open sky
- l4  upper deck
- l3  mid deck
- l2  lower deck
- l1  bilge          <- bottommost, water collects

### constraints

- fuel bay & bilge -> l1 
- engine room -> l1 or l2

everything else is flexible

### bias

| room | l1 bilge | l2 lower | l3 mid | l4 upper |
|---|---|---|---|---|
| power room | 0.3 | 0.8 | **1.5** | 1.0 |
| galley | 0.2 | 0.6 | 1.0 | **1.4** |
| storage | 0.8 | **1.2** | 1.2 | 1.0 |
| morgue | 1.2 | **1.4** | 0.8 | 0.4 |
| server room | 0.3 | 0.8 | **1.4** | 1.0 |
| bathroom | 0.4 | 0.8 | 1.0 | **1.3** |
| cafeteria | 0.2 | 0.5 | 1.0 | **1.5** |
| passenger bedrooms | 0.2 | 0.5 | 1.2 | **1.5** |
| crew quarters | 0.3 | 0.6 | 1.0 | **1.4** |
| med bay | 0.4 | 0.8 | 1.0 | **1.3** |
| library | 0.4 | 0.8 | 1.1 | **1.2** |

## fitting inside ship

each layer has a particular boundary (eg: bilge is thinner than l2) and the spawning happens within those bounds.
each layer adds atleast a staircase or ladders etc to upper layer (can have more than 1 too) 


