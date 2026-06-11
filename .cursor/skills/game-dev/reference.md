# Game Dev Reference

Extended patterns and checklists. Read only when the task needs deeper detail.

## ECS-oriented design (when appropriate)

Use when the project already uses ECS or needs many homogeneous entities (bullets, crowds, tiles).

- **Components**: pure data
- **Systems**: logic over queries; no hidden singleton state
- **Entities**: IDs only; avoid inheritance trees for composition-friendly gameplay

Don't force ECS onto small projects or engine-native OOP codebases.

## Spatial partitioning

When many entities need proximity queries:

- Uniform grid for 2D action games
- Quadtree/Octree for uneven density
- Broadphase + narrowphase for physics-heavy scenes

Profile before adding; brute force is fine under ~50 dynamic actors.

## Animation

- Drive gameplay hitboxes from animation events or synced timelines, not guessed frame counts
- Root motion only when animation team and physics agree on ownership
- State machine ↔ anim graph mapping should be one-directional and documented

## Audio

- Separate **one-shots**, **loops**, and **music** buses
- Pool voices for rapid SFX; cap polyphony for mobile
- Duck music on VO/dialog if the project has a mixer hierarchy

## Localization

- Externalize strings early; avoid concatenating translated fragments
- Font fallback for CJK/RTL if shipping multi-language
- Reserve UI space for expansion (~30% for DE/FI)

## Networking (if applicable)

- Server authoritative for gameplay outcomes; client prediction only where already established
- Serialize minimal state; interest management for large worlds
- Explicit tick rate and snapshot/interpolation strategy documented in code comments near net layer

## Mobile / console constraints

| Concern | Guideline |
|---------|-----------|
| Memory | Stream levels; unload unused atlases |
| Thermal | Reduce sustained CPU; adaptive quality |
| Battery | Lower idle FPS; pause sim when backgrounded |
| Input | Touch targets, dead zones, safe areas |
| Saves | Cloud conflict policy if using platform saves |

## Balance & tuning

- Keep tunables in spreadsheets or ScriptableObjects/Resources
- Log combat/economy decisions in changelogs for designers
- Feature flags for A/B without duplicate code paths

## Profiling checklist

```
- [ ] Baseline FPS and frame time p95 on min-spec device
- [ ] Worst scene / worst wave identified
- [ ] GC alloc per frame ≈ 0 in steady state
- [ ] Draw calls / batches within budget
- [ ] Load time for cold start measured
```

## Code review checklist (game-specific)

- [ ] No new per-frame allocations in gameplay hot paths
- [ ] Pause/time-scale respected by new systems
- [ ] Scene reload / respawn cleans subscriptions and timers
- [ ] Save format backward compatible or version bumped with migration
- [ ] Multiplayer: server/client responsibilities clear
- [ ] Cheats/dev keys behind `DEVELOPMENT_BUILD` or equivalent
