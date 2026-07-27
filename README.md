# Ant Colony Simulator — Design Brief

**Engine:** Godot 4.x · GDScript, strict typing
**Status:** Working specification

---

## 1. Concept

A logic sandbox. The player does not control ants — they design the *rules* ants follow, then watch a colony live or die by that design.

**The spine of the game:**

> An ant can only act on information physically available at its own body. The entire puzzle is turning that information into a direction and an action.

Every other system serves that constraint. Vision is short and directional. Smell is contact-based, not ranged. There is no global map, no shared knowledge, no pathfinding. If a colony coordinates, it is because the player built a mechanism out of pheromones and local contact that *causes* coordination to emerge.

Behaviour is authored in a node graph. The graph is a **design-time artefact only** — it compiles to a flat program that the simulation executes. Nothing in the editor exists at runtime.

---

## 2. Design Pillars

1. **Local information only.** No ant knows anything it did not sense at its own position.
2. **Emergence over primitives.** Trail-following is not an action; it is what happens when a player wires odour sensing into a walk vector. If a behaviour can be built from parts, it does not get its own button.
3. **Cost is visible and deterministic.** Every design has a measurable computational price, reported in stable abstract units, never wall-clock time.
4. **Reproducible.** Same seed plus same behaviour equals same outcome, every run, every machine.
5. **Sandbox first.** Multiple colonies with different logic can be dropped on one seed and left to compete.
6. **Built to grow.** New queryable values are expected continuously. Adding one must touch exactly one registration site.

---

## 3. Simulation Architecture

### 3.1 Determinism

Non-negotiable. Scoring, replay, and colony-versus-colony comparison all depend on it.

- Fixed timestep, `1/60 s`. The sim advances by integer ticks; wall-clock is never read inside simulation logic.
- Per-ant PCG RNG seeded from `(world_seed, colony_id, ant_id)`. No shared global RNG stream.
- Ants iterate in stable index order. Never iterate a `Dictionary` where order affects outcome.
- The diffusion field steps on a fixed tick cadence independent of frame rate.
- Fast-forward changes how many ticks run per frame, never the size of a tick.
- Float operations stay in `float32` where they touch the field, consistently, so results do not drift between the display path and the headless path.

### 3.2 Data layout

Ants are **indices, not objects**. A colony owns parallel packed columns:

```
position_x, position_y, heading, energy, health, carry_mass,
action, action_elapsed, target_id, caste, alive
```

`PackedFloat32Array` for continuous values, `PackedInt32Array` for discrete ones. `Ant` becomes a thin **view/debug wrapper** over an index — useful for the editor's test panel and for inspecting one ant in-game, never used as storage. It must not be a `Node` in the hot path.

Rendering is `MultiMeshInstance2D` with per-instance transforms written directly from the position columns.

Spatial queries go through a uniform-grid broadphase rebuilt or incrementally maintained each tick. Never an O(n²) scan.

### 3.3 Layer separation

```
Editor  ──────────►  Compiler  ──────────►  Runtime
ConditionNodeData    flat program           SoA columns,
tree                 (packed arrays)        field, broadphase
```

The runtime must never dereference a `ConditionNodeData`. This is a hard architectural boundary; violating it forfeits every performance property in §8.

### 3.4 Tick order

```
1.  Field step            (if due — 20 Hz cadence)
2.  Broadphase rebuild
3.  Sense population      (sparse, demand-driven — only keys the program reads)
4.  Colony-hoisted subtrees   (once per colony, not per ant)
5.  Per-ant program evaluation → exclusive action selection
6.  Concurrent emitter evaluation → pheromone deposition
7.  Action execution
8.  Movement integration
9.  Death and spawn resolution
10. Colony bookkeeping (stores, population, score metrics)
```

Emitters run at step 6 so deposition reflects the *same* tick's decision, and the field picks it up at the next field step.

---

## 4. The Behaviour Graph

### 4.1 What a behaviour document is

One document per caste. A document contains:

- A set of **rules**, each pairing a condition with an exclusive action.
- A set of **concurrent emitters**, each pairing a condition with a pheromone channel and rate.
- The node trees feeding all of the above.

Nodes may also sit on the canvas **unwired** — dropped from the library or detached — and join the tree only when the player drags a wire from an output port into a gate or the output rail. Unwired nodes are inert but preserved on save, which makes them usable as scratch space.

### 4.2 Node kinds

| Kind | Ops | Result type |
|---|---|---|
| `logic` | and, or, not, xor | bool |
| `compare` | lt, gt, eq, le, ge, ne | bool |
| `timing` | delay, hold, pulse, cooldown, latch | bool |
| `memory` | previous, hold_value, ema, min_over, max_over, delta | matches input |
| `query` | distance, count, exists, mass, direction, offset | float / bool / vector |
| `vector` | const, from_angle, add, sub, scale, rotate, normalize, length, angle, dot | vector / float |
| `property` | — | typed variable read |
| `literal` | — | float |

### 4.3 Type system

Three types: `bool`, `float`, `vector` (`Vector2`).

Coercion rules, applied consistently everywhere:

- **bool → float:** `true` is `1.0`, `false` is `0.0`.
- **float → bool:** truthy when not approximately zero.
- **vector → anything scalar:** *not permitted.* Take a `length` or an `angle` first.

Vectors are deliberately excluded from comparison and from logic gates. A vector has no ordering and no meaningful truthiness, and silently coercing one produces behaviour the player cannot reason about. A comparison or gate handed a vector goes undefined rather than guessing.

### 4.4 Undefined propagation

A node that cannot produce an answer — missing inputs, wrong input types, an unresolved variable — evaluates to **undefined** and propagates undefined to every ancestor. It does not substitute a default.

This is important for authoring. A half-built subtree reads as undefined in the editor (shown as `?` rather than `TRUE`/`FALSE`), so the player sees *"this isn't finished"* instead of *"this is false."* Those two states look identical at runtime and mean completely different things.

At compile time, an undefined node is a **compile error**, not a warning. A rule that can never fire is a bug, and shipping it silently wastes the player's debugging time.

### 4.5 Evaluation semantics

Within a single tick, a subtree is evaluated **exactly once**, no matter how many parents reference it. Two properties depend on this:

- **Timing and memory nodes are stateful.** Evaluating one twice in a tick advances its timer twice, producing durations that do not match what the player specified.
- **Sense queries are expensive.** Re-running a vision query per reference would multiply cost by fan-in.

In the editor this is enforced by a shared per-pass cache keyed by node id, discarded and rebuilt each frame. In the compiled runtime it falls out of the flat topological ordering: each slot is written once per tick, in dependency order.

### 4.6 Logic nodes

`and`, `or`, `not`, `xor`. Variadic except `not`, which takes one input.

- `and` — true when every input is true. Empty input list is undefined, not vacuously true.
- `or` — true when any input is true.
- `not` — inverts its single input.
- `xor` — true when an odd number of inputs are true.

Any input that is undefined or of vector type makes the gate undefined.

**Short-circuit evaluation is a compile-time decision, not a runtime one.** The compiler may reorder an `and`'s inputs so cheap tests run before expensive ones and skip the rest on the first false — but only when no skipped subtree contains a `timing` or `memory` node, because those must advance every tick regardless. This reordering is one of the larger free wins available and it must be reported to the player as such.

### 4.7 Comparison nodes

`lt`, `gt`, `eq`, `le`, `ge`, `ne`. Exactly two operands. Both are coerced to float; either being a vector makes the node undefined.

`eq` and `ne` use approximate comparison, not exact bit equality. Exact float equality is a trap in a simulation where values are integrated over time, and a player writing `energy == 50` should not be silently betrayed.

### 4.8 Timing nodes

Boolean state machines. Each takes an input and an optional reset input, plus a duration in seconds.

| Op | Behaviour | Duration used |
|---|---|---|
| `delay` | Output turns true only after the input has been continuously true for this long. Debounce. | yes |
| `hold` | Output turns true with the input and stays true this long after it drops. Reset ends it early. | yes |
| `pulse` | A rising input fires one burst of this length, then waits for the input to drop and rise again. | yes |
| `cooldown` | Output can turn true only once per interval, however often the input fires. | yes |
| `latch` | The first true input sticks. Only the reset input clears it. | no |

Timing state is **runtime-only and never serialised**. A document loaded from disk starts with every timer at zero.

### 4.9 Memory nodes

Timing nodes remember a *boolean*. Memory nodes remember a *value*. Required for temporal reasoning about sensed quantities, and for surviving the sensory dropouts described in §6.5.

| Op | Behaviour |
|---|---|
| `previous` | The input's value from N ticks ago (N configurable, default 1) |
| `hold_value` | Latches the input's value when a gate input goes true; holds until re-triggered |
| `ema` | Exponential moving average with a configurable half-life |
| `min_over` / `max_over` | Rolling extremum over a time window |
| `delta` | Current input minus its value one sample ago |

Output type matches input type; a memory node over a vector holds vectors.

Like timing nodes, memory nodes are **per-ant stateful** and therefore excluded from colony-scope hoisting and from short-circuit skipping (§4.6, §8.4). Window-based ops (`min_over`, `max_over`) carry a per-ant ring buffer, so their window length has a real memory cost that must be reflected in the benchmark and capped.

### 4.10 Query (sense) nodes

Sense queries use a three-part key: `<subject>.<scope>.<measure>`.

**Subjects:** food, ant, enemy, nestmate, colony, object, corpse
**Scopes:** reach, visible, any
**Measures:** distance, count, exists, mass, direction, offset

| Measure | Type | Meaning |
|---|---|---|
| `exists` | bool | Anything matching in scope |
| `count` | float | How many |
| `distance` | float | To the nearest match |
| `mass` | float | Of the nearest match |
| `direction` | vector | Unit vector toward the nearest match |
| `offset` | vector | Full vector to the nearest match |

**Vector senses are always ant-relative.** A behaviour that works on one map means the same thing on another. `Vector2.ZERO` is the canonical "nothing found", which keeps `length(direction) > 0` an honest emptiness test in the same way an at-the-limit distance does.

Not every subject/scope/measure combination is meaningful, so families declare an explicit validity table (§8.6) rather than exposing the full cross product.

Olfaction is **not** a scope. It has its own node family, described in §6.4.

### 4.11 Vector nodes

| Op | Inputs | Result | Notes |
|---|---|---|---|
| `const` | — | vector | A literal typed in. Degrees measured clockwise from east. |
| `from_angle` | float | vector | Degrees to a unit vector |
| `add` | vector, vector | vector | Sum |
| `sub` | vector, vector | vector | First minus second |
| `scale` | vector, float | vector | Stretch by a number |
| `rotate` | vector, float | vector | Turn by degrees |
| `normalize` | vector | vector | Same direction, length 1. Zero stays zero. |
| `length` | vector | float | 0 means nothing was sensed |
| `angle` | vector | float | Degrees from east, −180 to 180 |
| `dot` | vector, vector | float | Positive when broadly aligned, negative when opposed |

Inputs are read in wiring order and must match the declared signature exactly. Anything missing or mistyped leaves the node undefined rather than being coerced into something plausible.

Vector nodes are the primary tool for building `WALK` directions — blending an odour gradient with an obstacle-avoidance vector and a wander component is the canonical intermediate-player construction.

### 4.12 Property and literal nodes

**Property** reads a named variable from the schema (§8.6). Its type comes from the registry, not from the node.

**Literal** is a typed constant. Literals are **constant-folded at compile time** and cost nothing at runtime.

### 4.13 Gates, nesting, and the output rail

A **gate** is any node that accepts children — logic, compare, timing, memory, and multi-input vector nodes. Leaves (property, literal, zero-input queries) are not gates and cannot be entered.

The editor is **navigable rather than flat**. The player enters a gate to see its interior, with a breadcrumb trail back out, so a large behaviour stays readable at any depth. The **output rail** represents the document's result; wiring a node into the rail attaches it to the current focus gate.

Two structural rules the editor enforces:

- **No cycles.** A node cannot be wired into its own branch. Behaviour evaluation is a DAG, always.
- **Only gates accept inputs.** Wiring into a leaf is rejected with an explanation rather than silently ignored.

### 4.14 The condition library

Any selection of nodes can be saved as a named **package** and reused. Placed instances carry a link back to the package.

Editing a linked instance offers three resolutions:

- **Update everywhere** — the edit becomes the new package definition and propagates to every instance.
- **Save as new** — this instance detaches into a new package; other uses are untouched.
- **Keep as a one-off** — this instance unlinks and becomes a plain subtree.

This is the main authoring affordance for managing complexity, and it composes with structural dedup (§8.2): reusing a package rather than rebuilding equivalent logic makes the shared cost explicit to the player *and* automatically free at runtime.

Packages persist to `user://condition_library.json` with a format version. Library format migrations are separate from behaviour-document schema migrations (§8.6) and both must be handled.

### 4.15 Live tracing and the test panel

The editor evaluates continuously against a panel of settable variables, so the player sees every node's current value live: booleans as true/false colouring, numbers and vectors as readouts, undefined as `?`.

The variable panel is generated from the registry (§8.6) and grouped by category — Action, Vitals, Cargo, Senses, Odour, Colony, Custom. Sliders derive their ranges from registry metadata.

This panel is the reason `Ant.write_state()` exists in its current form: it fills a plain dictionary keyed exactly like the schema, so the same values drive both the live simulation and the editor's test harness. That property must survive the move to demand-driven population (§8.6) — the test panel simply requests the full key set where the runtime requests a subset.

### 4.16 Migrations from the current implementation

The following are changes to code that already exists:

| Change | Reason |
|---|---|
| Remove the `smell` scope and `OLFACTORY_RANGE` | Olfaction is contact-based (§6.3) |
| Remove `pheromone` as a query subject | Replaced by the odour channel family (§6.4) |
| Vision becomes a cone | §6.2 |
| Add the `memory` node kind | §4.9 |
| Replace the per-node result `Dictionary` in the runtime path | §8.1 |
| Move subject/scope/measure lists out of `const` arrays into the registry | §8.6 |
| Replace `AntSchema.default_for()`'s silent fallback with a broken-node state | §8.6 |
| `Ant` stops extending `Node` | §3.2 |

---

## 5. Actions

### 5.1 Exclusive actions and concurrent emitters

The "do this" side splits into two categories.

**Exclusive actions** — exactly one at a time.

**Concurrent emitters** — pheromone release. Any number active simultaneously, each with its own condition, running *alongside* whatever exclusive action is selected.

Real ants lay trail while walking. If emission occupied the exclusive slot, an ant could not walk and lay a trail in the same tick, which would make trail-laying nearly unauthorable and remove the central mechanic. Emission is a gland, not a behaviour.

### 5.2 Exclusive action set

| Action | Parameters | Notes |
|---|---|---|
| `IDLE` | — | Minimal upkeep. The fallback when nothing matches. |
| `WALK` | `direction: Vector2`, `speed: float` | The workhorse. Direction is ant-relative. The ant turns toward the vector at a capped turn rate, so instant reversal is impossible. |
| `REST` | — | Regain energy. Fast at the nest with food in store, slow in the field. Consumes colony stores when at the nest. |
| `EAT` | — | Convert carried food, or food within reach, into personal energy. |
| `PICK_UP` | `target: entity` | Food or object within reach. Fails if already carrying or over carry mass. |
| `DROP` | — | Release carried item at the current position. |
| `BITE` | `target: entity` | Deal `bite_damage` to an entity within reach. |
| `FEED` | `target: entity` | Trophallaxis — transfer energy or food to a nestmate within reach. |
| `ANTENNATE` | `target: entity` | Probe a nestmate within reach, exposing a slice of its state to this ant for a short window. The only ant-to-ant information channel besides pheromone. |
| `SPAWN` | `caste: id` | Queen only. Consumes colony stores. |

**Deliberately absent: a trail-following action.** Following a trail is `WALK` with a direction derived from odour sensing, and building that derivation *is the puzzle*. Shipping it as a primitive hands the player the answer.

### 5.3 Action parameters are graph values

Actions have **typed input sockets** fed by the same node trees that feed conditions. `WALK` takes a `Vector2` and a `float`. `PICK_UP` takes an entity reference from a query node.

This unifies both halves of the system: the player is always building expressions, and an action is an expression with a side effect.

### 5.4 Per-action properties

Defined in a data table, one row per action:

- **Duration** — instantaneous, fixed, or continuous-until-interrupted.
- **Interruptible** — can a higher-priority rule preempt it mid-execution? `PICK_UP` should commit; `WALK` should not. Without this, ants thrash between actions every tick.
- **Minimum commit ticks** — a floor even on interruptible actions, preventing oscillation between two rules that alternate truth each tick.
- **Energy cost per tick.**
- **Preconditions** — what must hold for it to succeed at all.
- **Failure behaviour** — what happens when preconditions fail: fall through to the next rule, or consume the tick.

### 5.5 Action feedback

The graph must be able to read what happened, or the player cannot author recovery logic:

- `is_idle`, `is_walking`, `is_resting`, … — one bool per action, exactly one true
- `action_elapsed` — seconds in the current action
- `last_action` — the previous exclusive action
- `last_action_failed` — true for one tick after a failed attempt
- `carry_mass`, `is_carrying_food`

### 5.6 Open: arbitration

**Unresolved.** When several rules are simultaneously true and only one exclusive action can run, what wins? This determines whether behaviours compile to a prioritised rule list or something richer, so it shapes the compiler and must be settled before compiler work begins.

Candidates:

1. **Ordered list, first match wins.** Simple, predictable, teaches priority thinking. The player reorders by dragging. Cheapest to evaluate — early-out on the first true condition.
2. **Explicit priority values.** More flexible, harder to reason about, invites tie-break ambiguity.
3. **Utility scoring.** Each rule produces a float; highest wins. Expressive, much harder to debug, and defeats early-out because every rule must be evaluated.
4. **Subsumption layers.** Higher layers override lower ones. Matches the robotics literature; possibly too abstract.

Option 1 interacts well with the cost model: a well-ordered rule list is genuinely cheaper to run, which is a real lesson worth teaching rather than an arbitrary rule.

---

## 6. Senses

### 6.1 Reach

Contact range, ~10 world units. Full subject and measure set. Cheap — the broadphase cell lookup dominates.

### 6.2 Vision

A **cone**, not a circle: ~60 world units range, ±60° half-angle from heading by default. Both are caste stats (§11.2). Same subjects and measures as reach.

The cone is what makes heading matter. An ant facing the wrong way is blind to what is beside it, so scanning, sweeping, and deliberate orientation become behaviours worth authoring rather than free information.

Implementation: filter by radius in the broadphase first, then reject by angle. The angular test is the cheap half and runs on a much smaller candidate set.

Line-of-sight occlusion by terrain is post-v1.

### 6.3 Olfaction is contact-based

**There is no smell range.** An ant cannot smell *at* a distant object, because that is not what olfaction is. Molecules diffuse outward from a source and an ant detects them only when they arrive at its receptors.

Consequences, all intentional:

- The ant learns *concentration here*, not *distance to source*.
- It cannot identify what emitted an odour beyond the channel identity.
- A distant strong source is indistinguishable from a nearby weak one.
- Reaching a source requires hill-climbing over space and time — which is the puzzle.

### 6.4 Three-site sampling

Three receptor sites, fixed in ant-local space:

| Site | Position |
|---|---|
| Left antenna | `+antenna_angle` from heading, `antenna_length` forward |
| Right antenna | `−antenna_angle` from heading, `antenna_length` forward |
| Centre | Head / mouthparts, at or just forward of the body centre |

Each samples the field at its own world position with bilinear interpolation.

**Centre must be a genuine third site, not the mean of left and right.** The mean of two symmetric antennae equals the value at their midpoint, which lies *on* the heading axis — one axial point, and therefore no forward derivative. Three *non-collinear* points determine a plane, and a plane is a full 2D gradient. Biologically this is sound: maxillary palps carry chemoreceptors.

Defaults: `antenna_angle` 30°, `antenna_length` ~5 world units (inside reach range). Both are caste stats — wider antennae give a longer lateral baseline and better lateral discrimination.

**Exposed variables, per channel:**

| Variable | Type | Notes |
|---|---|---|
| `odor.<ch>.left` | float | Left antenna concentration |
| `odor.<ch>.right` | float | Right antenna concentration |
| `odor.<ch>.centre` | float | Centre site concentration |
| `odor.<ch>.bias` | float | `right − left`, normalised. Lateral steering signal (*osmotropotaxis*). |
| `odor.<ch>.gradient` | Vector2 | Plane fit over all three sites, ant-relative |

**The gradient solve is nearly free.** Because the three sites are fixed in ant-local space, the plane-fit matrix is a compile-time constant — precompute its inverse once. Runtime is three field lookups, six multiply-adds, and a rotation by heading. Sampling dominates; the solve does not.

Olfaction's efficiency levers are therefore **channel count** and **sample cadence**, not gradient convenience. Sampling six channels costs six times sampling one. And because the field steps at 20 Hz (§7.3), sampling every sim tick is 3× waste — a real, teachable inefficiency the caching system already exposes.

### 6.5 Receptor response

**This is not difficulty tuning. It corrects an over-capability.**

A float grid sampled at three points is far *better* than real olfaction, not a faithful version of it. Real chemoreceptors have a hard detection floor — molecule arrival is discrete, and below some concentration zero molecules reach the receptor in a given window. They saturate. They respond logarithmically. The perfect-float version is the unrealistic one.

It matters because **real ant behaviour exists as a workaround for unreliable sensing.** Casting, spiral search, trail reinforcement, recruitment, tandem running — colonies evolved all of it precisely *because* gradient information is bad. A perfect gradient reduces food-finding to a three-node solution and deletes the reason every richer behaviour exists.

There is also a hard numerical argument. Concentration falls off steeply with distance; at range, the difference between two sites 5 units apart is ~1e-12 relative. In `float32` that is rounding error and denormals. Without a detection floor, steering directions get computed from floating-point garbage. The threshold is required for numerical sanity independent of any design goal.

The model:

- **Detection threshold.** Below `ODOR_MIN`, a site reads exactly zero.
- **Logarithmic response.** Reported value is `log(1 + C/ODOR_MIN)` — sensitive to relative change at low concentration, saturating near a strong source.
- **Optional per-level noise.** Seeded from `(world_seed, ant_id, tick)` so determinism holds. Off by default; a difficulty parameter.

Memory nodes remain essential for the interesting cases: smoothing threshold dropouts, remembering where a trail was lost, detecting that the ant is circling.

---

## 7. The Molecular Diffusion Field

### 7.1 Model

Diffusion–decay with optional advection:

```
∂C/∂t = D∇²C − λC − u·∇C + S
```

`C` concentration, `D` diffusivity, `λ` decay rate, `u` wind velocity, `S` sources.

### 7.2 Storage

- Uniform grid, cell size ~8 world units (a few body lengths), tunable per level.
- One `PackedFloat32Array` per channel, double-buffered (ping-pong read/write).
- A 2048×2048 map at 8 units/cell is 256×256 = 65,536 floats per channel = 256 KB. Eight channels ≈ 2 MB. Acceptable.

### 7.3 Update loop

Runs at a **fixed cadence decoupled from the sim tick** — 20 Hz, one field step per three sim ticks.

1. **Scatter sources** — accumulate emissions into the write buffer.
2. **Diffuse** — separable 1D passes, horizontal then vertical. O(2n) per cell rather than O(n²) for wide kernels.
3. **Decay** — multiply by `exp(−λ·dt)`.
4. **Advect** — deferred. Semi-Lagrangian backtrace when wind lands. Leaving the slot in the loop costs nothing: advection reads and writes the same buffers as diffusion and changes no sensing, behaviour, or schema code, so it can be added later without disturbing anything built before it.
5. **Prune** — clamp values below `EPSILON` to zero.

**Stability constraint:** explicit diffusion in 2D requires `D·dt/dx² ≤ 0.25`. Clamp `D` at level load and warn, rather than letting the field diverge.

### 7.4 Active-tile optimisation

This is what makes the field cheap. Most of the map is empty most of the time.

- Partition the grid into tiles (16×16 cells).
- Maintain a per-channel active bitmask.
- A tile is active if any cell exceeds `EPSILON`, or if it neighbours an active tile — a one-tile halo, so diffusion can spread outward into fresh territory.
- Process only active tiles. Deactivate when a tile's maximum falls below threshold.

Typical load in a running colony should be a small fraction of the grid.

### 7.5 Channels

**World channels** — emitted by the map, readable by everyone:

- `food_odor` — continuous from food items, proportional to remaining mass
- `corpse_odor` — from dead ants, decaying
- `nest_odor` — a permanent beacon from each nest; the "home" gradient

**Colony channels** — player-defined, private to the emitting colony. Cap at **8 per colony**. Each declares:

- Name and display colour
- Diffusivity `D` and decay rate `λ`
- Emission conditions (concurrent emitters, §5.1) with a rate expression

**Foreign-pheromone aggregate** — a read-only channel exposing the *summed* concentration of all rival colonies' private channels. A scout can detect *that* a trail exists without decoding what it means. This enables counter-play without letting colonies read each other's protocols.

### 7.6 Field cost is charged to the emitter

Field update cost — `active_tiles × active_channels` — is added to the emitting colony's budget (§9). Spraying pheromone across the whole map is expensive, exactly as it should be. This ties the physics directly to the efficiency score rather than treating the field as free background simulation.

---

## 8. Compilation, Caching, and Schema

### 8.1 The compile step

The editor's `ConditionNodeData` tree compiles to a flat program:

- Topologically sorted node list; results in a flat slot array indexed by integer.
- Opcodes and operand indices in `PackedInt32Array`; slot values in `PackedFloat32Array` plus a bitset for booleans.
- Literals constant-folded away.
- **No per-node `Dictionary` allocation.** The editor's `{"value", "type", "is_bool"}` envelope is correct for live tracing and fatal at scale — it allocates once per node per evaluation.

Compilation also produces the diagnostics the player sees: undefined nodes, unreachable rules, unresolved variables, dedup counts, hoisting decisions.

### 8.2 Structural dedup (hash-consing)

**This, not runtime caching, is what makes shared subchains free.** At compile time, hash each subtree by structure — kind, op, parameters, and child hashes. Identical subtrees collapse to a single slot, evaluated once per tick regardless of how many rules reference them.

Report the dedup count. Watching a cost figure drop by three quarters after consolidating duplicated logic is the core feedback loop of the efficiency game, and it rewards exactly the authoring habit the library system encourages.

### 8.3 Versioned invalidation by channel

Version the **sources**, not the nodes. Each compiled node carries a **dependency mask** over variable channels, computed once at compile time. Each channel holds a version counter, bumped when written. A cached slot is valid iff no channel in its mask has advanced since the cache stamp.

Channels rather than individual variables, because refresh cadences genuinely differ:

| Channel | Changes | Cacheable |
|---|---|---|
| Vitals (energy, health) | every tick | no — the check costs more than the recompute |
| Self action state | on transition | yes, cheap |
| Reach senses | on movement | yes |
| Vision | on movement or turn | yes |
| Odour samples | on field step (20 Hz) | yes — three sim ticks per change |
| Colony state | on colony event | yes, **and shareable** |

### 8.4 Colony-scope hoisting

A subtree whose dependency mask is *entirely* colony-scoped can be evaluated **once per tick for the whole colony** rather than once per ant. The compiler detects this automatically from the mask; the player does not annotate anything.

**Hard exclusion:** any subtree containing a `timing` or `memory` node is per-ant stateful and can never be hoisted or shared, regardless of its dependency mask.

### 8.5 Player-facing cache control

Expose refresh cadence per expensive channel: *"re-run vision every 4 ticks instead of every tick."* This is a lever players can reason about in game terms — a less alert ant is cheaper but slower to react — rather than an abstract invalidate button. The trade-off is real and visible in both score axes.

### 8.6 Schema extensibility

**Adding queryable values will be ongoing for the life of the project.** The system must absorb new variables without touching the editor UI, the runtime, the cache, or the benchmark. This is a structural requirement.

**One registry is the single source of truth.** Every variable and query family registers once, declaring all of:

| Field | Why it is mandatory |
|---|---|
| `key` or key pattern | Identity |
| `type` | bool / float / vector |
| `category` | Editor grouping |
| `default` | Value before first write |
| `ui_range` | Test-panel slider bounds |
| `channel` | **Cache invalidation (§8.3) breaks silently without it** |
| `cost` | **The benchmark (§9.1) under-reports silently without it** |
| `scope` | Per-ant or colony — drives hoisting (§8.4) |
| `resolver` | The `Callable` that produces the value |

`channel` and `cost` being *required* is the important part. An optional field gets forgotten, and a forgotten one produces a variable that is silently free and silently never invalidated — two bugs that will not surface until late.

**Everything else derives from the registry.** Editor dropdowns, inspector forms, the variable panel, and the subject/scope/measure option lists are generated, never hand-maintained. Adding a variable means one registration and nothing else.

The registry supports two entry shapes: **explicit singles** (`energy`, `health`) and **generative families** (the `<subject>.<scope>.<measure>` cross product, the `odor.<channel>.<site>` set). Families declare a validity table, since not every combination is meaningful.

**Names resolve to integer slots at compile time.** The runtime never performs a string lookup — no dictionary `get` per ant per tick. This is what makes the registry free to grow: three hundred registered variables cost nothing if a program references twelve.

**Sparse population.** The compiler knows exactly which keys a program reads and tells the senses provider to fill only those. Populating everything unconditionally is ruinous with a large registry and thousands of ants.

**Unknown variables fail loudly.** A silent default for an unrecognised key means a renamed or removed variable reads `0.0` forever in a saved document. Instead: behaviour documents carry a schema version, the registry keeps an alias table for renames, and anything unresolved compiles to a **broken node** — visible in the editor, blocking the run. Silent zero is the worst possible outcome for a player debugging a colony that "just doesn't work."

**Contract test.** A test iterates the registry and asserts every entry has a type, default, channel, cost, scope, and a resolver returning the declared type. Catches half-finished additions at build time.

---

## 9. Benchmarking

### 9.1 Deterministic cost model

The efficiency score is **never wall-clock**. Wall-clock varies by machine and by run, and conflates the player's logic with the renderer and the engine. The score is an abstract unit count, stable everywhere.

Indicative weights, subject to calibration:

| Operation | Cost |
|---|---|
| Literal | 0 — constant-folded |
| Property read | 1 |
| Logic gate | 1 per input |
| Compare | 1 |
| Timing node | 1 |
| Memory node | 1, plus window length for `min_over` / `max_over` |
| Odour sample — one site, one channel | 4 |
| Gradient solve — given three samples | 1 |
| Reach query | 2 per candidate |
| Vision query | 8 + 2 per candidate |
| Field update | active_tiles × channels |

### 9.2 Reported metrics

- **Logic cost** — per tick: total, mean per ant, peak
- **Cache hit rate**
- **Dedup count** — subtrees collapsed at compile
- **Hoisted subtrees** — evaluated colony-wide instead of per-ant
- **Short-circuit savings** — evaluations skipped by input reordering
- **Field cost** — active tiles × channels
- **Wall-clock** — a *secondary* readout only, never scored

### 9.3 Presentation

A live graph during playback plus a post-run summary against per-level par values.

**Cost must attribute down to individual rules and subtrees**, not just a colony total. The player has to be able to answer "which of my rules is expensive?" — a single aggregate number tells them they have a problem without telling them where, which is the least useful possible feedback.

---

## 10. Scoring and Outcomes

### 10.1 Outcome tiers

**CLEARED** — all resources harvested and all enemies destroyed. Scored on **time to clear** in sim seconds.

**DIED** — colony extinct before clearing. Scored on **colony lifespan** in sim seconds.

A cleared run always beats a died run. Within a tier the ordering is straightforward.

### 10.2 Two independent axes

Outcome performance and logic cost are reported **separately**, never collapsed into one number. The player must be able to tell which lever to pull. Both are shown against per-level par.

### 10.3 Seeded maps

Every map is seeded; same seed plus same behaviour equals the same run. This is what makes the sandbox work:

- Run one design against many seeds to test generality rather than luck
- Run several *versions* of a design against one seed to compare directly
- Fast-forward or run headless in batch for quick iteration

### 10.4 Multi-colony competition

Multiple colonies with different behaviour documents on one seeded map, competing for the same finite resources. Each colony's private channels are invisible to rivals except through the foreign-pheromone aggregate (§7.5).

This is the sandbox's endgame: not "did my design work" but "did my design beat that one."

---

## 11. Colony, Castes, and Combat

### 11.1 Economy

- Food is harvested and carried to the nest, entering colony stores.
- Stores fuel two things: ants resting to recover energy, and the queen spawning.
- Ants that run out of energy die and become corpses, emitting `corpse_odor`.
- The queen is its own behaviour document, with colony-scoped variables and its own action set. Spawning triggers are player-defined: energy surplus thresholds, pheromone signals, enemy contact.

### 11.2 Player-defined castes

**Castes are authored by the player, not chosen from a fixed list.** A caste is a stat block plus its own behaviour document. Workers and soldiers do not share a graph with caste-check branches scattered through it.

Every stat is **clamped to a designer-set range** so a caste cannot be built that breaks the simulation or reads as absurd:

| Stat | Governs |
|---|---|
| `size` | Physical footprint, collision |
| `move_speed`, `turn_rate` | Locomotion |
| `max_health` | Survivability |
| `bite_damage` | Combat output |
| `max_carry_mass` | Hauling |
| `max_energy`, `metabolic_rate` | Endurance versus upkeep |
| `vision_range`, `vision_half_angle` | Sight cone (§6.2) |
| `antenna_angle`, `antenna_length` | Olfactory baseline (§6.4) |

**Spawn cost is derived from the stat block**, not set independently. A caste that maxes everything is legal but ruinously expensive in food, so the interesting design space is specialisation. Hard clamps prevent breakage; derived cost prevents dominance.

Clamp ranges live in a data table so they can be tuned without code changes, and levels may narrow them further.

### 11.3 Combat

Deliberately minimal. The system provides damage exchange and nothing else; **all tactics are player logic.**

- `BITE` on an entity within reach deals `bite_damage`.
- Health decreases; at zero the ant dies and becomes a corpse.
- No morale, no formation bonus, no flanking, no to-hit roll.

What makes combat interesting is entirely authored: emitting an alarm pheromone on taking damage, retreating below a health threshold, recruiting soldiers toward an alarm gradient, or — for a sophisticated player — evaluating an engagement expression such as *"nestmates in vision ≥ 3 AND my health > 60 AND enemy count ≤ 2"* before committing.

The schema must expose the readables that make this authorable: `health`, recent damage (via `memory.delta` on health, or a dedicated `damage_taken_recent`), enemy counts and directions in reach and vision, and nestmate counts for support estimation.

### 11.4 Enemy colonies use the same graph system

**Enemies are colonies with a behaviour document, authored the same way the player authors theirs.** No separate AI system exists.

This collapses three things into one: enemy design, the multi-colony sandbox (§10.4), and level authoring. A level's opposition is a shipped behaviour document, which means challenge levels can be framed as "beat this colony" — and the player can open the opponent's logic, study it, and counter it.

---

## 12. Coding Standards

Strict Godot 4.x typing throughout:

- Explicitly type all variables, parameters, lambdas, and return values.
- No implicit type inference — `:=` is not acceptable.
- Capture unused returns in `_`-prefixed variables.
- Never shadow built-in identifiers.
- Ants are indices or `RefCounted` — never `Node` in the hot path.
- Hash maps and manager singletons over per-entity nodes.
- Packed arrays over typed `Array` wherever the data is homogeneous and hot.
- One-way dependencies: `Ant` → `AntSchema` → editor. Nothing in the entity or schema layer reads the editor back.

---

## 13. Open Questions

| # | Item | Blocks |
|---|---|---|
| 1 | **Action arbitration model** (§5.6) | Compiler architecture — settle before compiler work starts |
| 2 | Receptor calibration: where `ODOR_MIN` sits, log curve shape, whether noise ships (§6.5) | Field and sensing tuning |
| 3 | Cost-model weight calibration (§9.1) | Benchmarking credibility |
| 4 | Caste stat clamp ranges and the spawn-cost formula derived from them (§11.2) | Colony balance |
| 5 | Memory node window cap for `min_over` / `max_over` (§4.9) | Per-ant memory budget |

Item 2 cannot be settled on paper. The detection floor determines whether trail-following is a puzzle or a formality, and it needs a prototype with a slider.
