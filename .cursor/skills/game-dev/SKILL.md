---
name: game-dev
description: Guides game development across engines and stacks—architecture, gameplay systems, performance, assets, testing, and common patterns (ECS, object pooling, state machines, event buses). Use when building or debugging games, game loops, scenes, sprites, physics, input, HUD, save systems, or when the user mentions game dev, Unity, Godot, Unreal, Phaser, or similar.
disable-model-invocation: true
---

# Game Dev

## Quick Start

Before writing code:

1. **Identify stack** — engine/framework, language, target platform, 2D vs 3D
2. **Find project conventions** — read existing scenes, prefabs, folder layout, naming
3. **Match patterns** — reuse existing managers, services, and event systems; don't introduce parallel abstractions
4. **Scope the change** — gameplay, rendering, audio, UI, networking, or tooling

If the engine is unclear, ask once. Default to engine-agnostic guidance unless the repo clearly uses one stack.

## Core Principles

- **Frame budget first** — know target FPS and platform limits before adding systems
- **Determinism where it matters** — physics, replays, netcode; isolate randomness behind seeded APIs
- **Data-driven when possible** — configs, ScriptableObjects, resources, JSON/TOML over hard-coded tuning
- **Separation of concerns** — input → intent → simulation → presentation → audio
- **Minimal diffs** — extend existing systems; avoid rewriting working gameplay for "cleaner" architecture

## Project Structure (adapt to engine)

```
assets/ or content/
  art/ audio/ fonts/
  prefabs/ or scenes/
  data/          # configs, balance tables, localization
src/ or scripts/
  core/          # game loop, time, events, save/load
  gameplay/      # player, enemies, abilities, AI
  ui/
  platform/      # input, achievements, ads, IAP
tests/ or specs/
```

Keep hot paths (update/tick) thin. Push heavy work to load time, async jobs, or fixed intervals.

## Game Loop Checklist

When implementing or debugging the loop:

```
- [ ] Fixed timestep for simulation (physics, AI) vs variable render
- [ ] Delta time used consistently; clamp spikes on tab focus / hitch
- [ ] Input sampled once per frame; no double-read across systems
- [ ] Update order documented (input → logic → physics → animation → render)
- [ ] Pause/time-scale handled in one place
```

## Common Systems

### State machines

Use explicit states for player, enemy AI, menus, and game flow (boot → menu → play → pause → game over).

- One owner per machine; transitions are named methods or events, not scattered booleans
- Enter/exit hooks for one-shot setup/teardown (enable collider, play anim, subscribe events)

### Object pooling

Pool frequently spawned/despawned objects (bullets, particles, damage numbers).

- Reset all mutable state on release; never assume defaults from construction
- Prefer pool interfaces over `Instantiate`/`Destroy` or `new`/GC in hot paths

### Event bus / signals

Decouple systems with typed events (player died, coin collected, wave started).

- Subscribe in `onEnable`/init; unsubscribe in `onDisable`/destroy
- Avoid global stringly-typed events when the project already has a typed pattern

### Save / load

- Version save format; migrate or fail gracefully
- Separate **settings** from **progress**
- Atomic writes (temp file + rename) on platforms that allow it

## Performance

Prioritize in order:

1. **Measure** — profiler, frame debugger, draw calls, GC spikes, physics cost
2. **Hot path** — allocations in update, LINQ/boxing in C#, per-frame `GetComponent`/queries
3. **Rendering** — batching, atlases, overdraw, unnecessary full-screen effects
4. **Loading** — async/streaming; avoid sync IO on main thread

Red flags to fix immediately:

- Allocating every frame (strings, lambdas, new lists, LINQ)
- `Find`/scene-wide searches in update
- Unbounded entity counts without pooling or culling
- Sync load of large assets during gameplay

## Input

- Map raw device input → **actions** (move, jump, fire), not key codes in gameplay code
- Support rebinding if the project already does; otherwise note as follow-up, don't half-implement
- Buffer coyote time / jump grace only when requested or already present in the codebase

## UI / HUD

- Separate **layout** from **data binding**
- Pause/menu should not leave simulation subscriptions dangling
- Scale for resolution/DPI using project UI framework conventions

## Testing & Debug

- **Deterministic repro** — seed, scene name, steps, expected vs actual
- **Debug overlays** — FPS, state name, hitboxes, nav paths (behind dev flag)
- **Playmode / headless tests** where the stack supports them; otherwise minimal pure-logic unit tests for rules (damage, scoring, inventory)

When fixing bugs, reproduce in isolation before refactoring unrelated systems.

## Engine Notes (read only the section that matches the repo)

### Unity (C#)

- Prefer `[SerializeField]` + private fields; cache component refs in `Awake`
- Use `FixedUpdate` for physics; `Update` for input and non-physics motion
- Coroutines for sequencing; `async`/UniTask only if already in project
- ScriptableObjects for data; avoid singletons unless the project already uses them consistently

### Godot (GDScript / C#)

- Scene tree ownership clear; use `_ready`, `_process`, `_physics_process` appropriately
- Signals for decoupling; autoloads sparingly and consistently named
- Resources (`.tres`) for data; keep node scripts focused

### Web (Phaser, Pixi, Three, Canvas)

- Respect rAF loop; avoid layout thrashing in DOM hybrid games
- Texture atlases; object pools for sprites/particles
- Separate game state from React/Vue UI if using a SPA shell

### Unreal (C++ / Blueprint)

- Follow module boundaries; hot paths in C++, designers in Blueprint when that's the project split
- Use interfaces/components over deep inheritance where the project already does

## Workflow

### New feature

1. Read similar existing feature end-to-end
2. List touched systems (input, sim, VFX, SFX, UI, save)
3. Implement smallest playable slice
4. Profile on target platform if performance-sensitive
5. Document non-obvious tuning constants in data files, not comments alone

### Bug fix

1. Reproduce with steps + seed/scene
2. Identify layer: input / simulation / presentation / asset
3. Fix root cause; avoid masking with extra flags unless intentional
4. Verify no regression in adjacent states (pause, respawn, scene reload)

## Output Format

When proposing changes:

```markdown
## Summary
[One sentence: what and why]

## Approach
[2–4 bullets: systems touched, pattern used]

## Risks
[Performance, save compat, multiplayer desync—only if relevant]

## Test plan
- [ ] Step to verify in editor or build
```

For reviews, classify findings:

- **Critical** — crash, data loss, desync, broken progression
- **Suggestion** — clarity, maintainability, minor perf
- **Nice to have** — polish, optional refactors

## Anti-Patterns

- God objects (`GameManager` doing everything) unless migrating incrementally
- Polling every entity every frame when events or spatial structures exist
- Premature ECS/full rewrite of working code
- Hard-coded magic numbers in gameplay scripts (use data)
- `Destroy`/allocate in tight loops without pooling

## Additional Resources

For extended patterns and checklists, see [reference.md](reference.md).
