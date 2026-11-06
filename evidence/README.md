# Simulator evidence

Each `evidence/<commit>/` folder is produced by the macOS workflow from that commit's `.xcresult` attachments. The PNGs in the folder are the screenshots. `MANIFEST.txt` lists their sizes.

`hook-*` files use the `-paperGlideEndScore` launch argument. That is a test hook. The clock does not run, and the first tap calls `endRun(withScore:)`. Those images prove the menus, the new-best label, the share sheet, and Home. They are not a flight.

`sim-*` files use `-paperGlideSeed 1` and `-paperGlideGuidedStride 0.1`. Each Glide tap applies one real flap (an assigned upward speed) and then advances the real physics, scoring, and collision simulation by 0.1 seconds. Coast advances that same simulation with no flap. The test taps when the plane is below the next opening's center, which is the same rule as `GlidePilot` in the core package. After the score reaches 1 it only coasts, so the run ends in a real collision. The score is not forced. `sim-frame-*` is the frame sequence. This is still not on-device feel: the stride is stepped by the test, not by a finger on a free-running 60 Hz clock. A 0.2 second stride with the same rule was too coarse for the previous impulse; that was the autopilot, not an impossible gap.
