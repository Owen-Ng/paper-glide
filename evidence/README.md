# Simulator evidence

Each `evidence/<commit>/` folder is produced by the macOS workflow from that commit's `.xcresult` attachments. The PNGs in the folder are the screenshots. `MANIFEST.txt` lists their sizes.

`hook-*` files use the `-paperGlideEndScore` launch argument. That is a test hook. The clock does not run, and the first tap calls `endRun(withScore:)`. Those images prove the menus, the new-best label, the share sheet, and Home. They are not a flight.

`sim-*` files use `-paperGlideSeed 1` and `-paperGlideGuidedStride 0.2`. Each Glide tap applies one real upward impulse and then advances the real physics, scoring, and collision simulation by 0.2 seconds. Coast advances that same simulation with no impulse. The test chooses tap or coast from the live plane height and the upcoming window center. The score is not forced. `sim-frame-*` is the frame sequence of that run. This is still not on-device feel: the stride is stepped by the test, not by a finger on a free-running 60 Hz clock.
