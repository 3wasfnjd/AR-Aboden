# Arena ground placement

This rollout applies only to `arena.html`. Run the deterministic checks with:

```sh
node --test tests/ground-placement.test.mjs
```

The arena uses XR8 absolute scale (metres) and the camera pose supplied by XR8.
Placement/physics update inside the camera pipeline rather than a separate animation loop.

Before placement, require 800 ms of NORMAL tracking, then one second of candidate
positions within a 4 cm horizontal / 2 cm vertical window. Distributed world points
and FEATURE_POINT hit tests must support a nearly horizontal patch near XR8's
estimated ground. Reject sparse, collinear, steep, or noisy evidence. Blank floors
may require scanning nearby textured ground before placement becomes available.

The final world position is copied once. Tracking loss pauses driving and clears
unplaced candidates; recovery does not reposition the locked arena. Repositioning
is explicit. The collision floor follows the model's centre asphalt height instead
of assuming the rendered road is exactly at the model origin.

This is ground validation, not a native persistent anchor or multi-plane detector.
XR8's camera/world estimate can still drift. Automated checks cannot establish
physical alignment, tracking quality, or frame rate on a phone.

## Phone acceptance checks

1. Scan a well-lit textured floor; hold the indicator on one location. Placement
   should remain disabled while sweeping continuously across the floor.
2. Place the arena and walk around it slowly. Check floor contact from several
   angles and whether the wheels meet the asphalt at different arena sizes.
3. Briefly cover the camera or switch tabs. Driving should pause. On recovery the
   arena must not silently be moved to a new location. Reposition if the world map
   itself has shifted.
4. Repeat on a plain floor, near furniture, and after explicit repositioning.
   A surface with insufficient evidence should ask for more scanning.

For a short diagnostic buffer, append `?placementDebug` to the arena URL and inspect
`window.arPlacementDiagnostics`. It contains the last 240 pipeline frames with
camera pose, tracking status, patch support, and arena/anchor positions. It stays
in memory and is not uploaded. `window.arHitTestError` records a hit-test failure,
if one occurred. No debug buffer is collected without the query parameter.

API references: [absolute scale](https://www.8thwall.com/docs/api/engine/xrcontroller/configure/),
[hit tests](https://www.8thwall.com/docs/api/engine/xrcontroller/hittest/),
[tracking data](https://www.8thwall.com/docs/api/engine/xrcontroller/pipelinemodule/).
