# Golden fixtures

These JSON files are the shared oracle for Paper Glide's rules. PaperGlideCore generates them. The Kotlin port reads the same files and does not edit them. A change to physics, scoring, gaps, or the difficulty ramp fails the Swift test until the files are regenerated on purpose.

## Regenerate

From the repo root, after a rules change:

```sh
swift run GenerateGoldenFixtures fixtures/golden
swift test --filter GoldenFixtureTests
```

Commit the JSON with the rules change. Do not hand-edit the numbers.

## Format version 1

Each file is one run. Field names are camelCase. `format` is `1`. Seeds are small integers that fit in a JSON number exactly (they are below 2^53).

| Field | Meaning |
| --- | --- |
| `timestep` | Fixed physics step, equal to `GameConfig.physicsStep` (`1/120` second). One recorded step is one call to `GameSession.step` with this dt. |
| `seed` | Seed for the window openings. |
| `tapSteps` | 1-based step indexes. A listed index queues one flap **before** the integration that produces that step. Step 0 is the state after the run begins and before any integration. |
| `tolerance` | Absolute tolerances. Positions, velocity, gap, scroll, and spacing use `1e-6`. Time uses `1e-9`. Score, phase, ids, and ramp step index are exact. |
| `config` | The standard world: gravity, flap, caps, plane size, opening, spacing, scroll, margins, and `physicsStep`. |
| `steps` | One record per step, including step 0. |

Each step:

- `flightTime`, `score`, `phase` (`playing` or `dead`)
- `plane.x`, `plane.y`, `plane.velocityY` (y-up)
- `scrollSpeed` and `spawnGapHeight` from the live run
- `ramp.stepIndex`, `ramp.gapHeight`, `ramp.scrollSpeed` from the difficulty ramp at that score
- `obstacles` sorted by `left`, then `id`. `spacingFromPrevious` is `left - previous.left`, and null on the first window. `gapHeight` is the opening that window was born with.

## Replay

1. Build the standard config from `config`.
2. Start a run with `seed`. Record step 0.
3. For `step` from 1 through the last index: if `step` is in `tapSteps`, queue one flap, then advance exactly one `timestep`.
4. Stop at the last recorded step (the run may already be dead).
5. Compare with the absolute tolerances in the file. Use 64-bit floats.

The ramp at score `s` is: step index `min(max(s, 0) / 5, 12)`, gap `max(168, baseGap - 5 * step)` when the base gap is at least 168, scroll `min(196, baseScroll + 4 * step)` when the base scroll is at most 196. The numbers in the file are the oracle if a port's formula and the file disagree.

## Files

- `no-tap-fall.json` — seed 1, no taps, falls until the run ends.
- `fixed-taps.json` — seed 3, taps at fixed steps.
- `pilot-ramp.json` — seed 11. Taps were chosen by the same rule as `GlidePilot` (tap when the plane is below the next opening's center) and then frozen in `tapSteps`. The run reaches a score of at least 5, so the ramp steps off its opening values. Replay the tap list. Do not re-run the pilot.
