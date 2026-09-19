# Arena ground placement

This rollout applies only to `arena.html`. Run the deterministic checks with:

```sh
node --test tests/ground-placement.test.mjs
```

The arena uses XR8 absolute scale (metres) and the camera pose supplied by XR8.
Placement/physics update inside the camera pipeline rather than a separate animation loop.

Before placement, require 800 ms of NORMAL tracking and a fresh downward ray hit
on XR8's estimated ground. The user can then tap “ثبّت هنا”; no feature count or
perfectly stationary reticle is required. Sparse, collinear, steep, or noisy points
are ignored rather than blocking placement. When a distributed ground patch is
available it refines height; otherwise the UI explicitly labels the floor as
estimated. Looking straight down is allowed. One FEATURE_POINT hit test per sample
supplements the world points (previously nine calls).

The one-second / 4 cm horizontal / 2 cm vertical check remains a stability hint,
not a prerequisite for an explicit tap. Both strict and manual locking still
reject stale input, missing candidates, and unavailable tracking. The earlier
mandatory feature-patch gate was removed after phone feedback: it could leave the
placement button disabled indefinitely despite normal tracking.

The final world position is copied once. Tracking loss pauses driving and clears
unplaced candidates; recovery does not reposition the locked arena. Repositioning
is explicit. The collision floor follows the model's centre asphalt height instead
of assuming the rendered road is exactly at the model origin.

This is ground validation, not a native persistent anchor or multi-plane detector.
XR8's camera/world estimate can still drift. Automated checks cannot establish
physical alignment, tracking quality, or frame rate on a phone.

## Phone acceptance checks

1. Scan a well-lit floor, then aim down. The preview and placement button should
   appear even with sparse feature points. Confirm an explicit tap places it
   without waiting for the stability hint. Invalid aim or tracking must disable it.
2. Place the arena and walk around it slowly. Check floor contact from several
   angles and whether the wheels meet the asphalt at different arena sizes.
3. Briefly cover the camera or switch tabs. Driving should pause. On recovery the
   arena must not silently be moved to a new location. Reposition if the world map
   itself has shifted.
4. Repeat on a plain floor, near furniture, and after explicit repositioning.
   Insufficient feature evidence should show an estimated preview, not deadlock.

For a short diagnostic buffer, append `?placementDebug` to the arena URL and inspect
`window.arPlacementDiagnostics`. It contains the last 240 pipeline frames with
camera pose, tracking status, patch support, and arena/anchor positions. It stays
in memory and is not uploaded. `window.arHitTestError` records a hit-test failure,
if one occurred. No debug buffer is collected without the query parameter.

API references: [absolute scale](https://www.8thwall.com/docs/api/engine/xrcontroller/configure/),
[hit tests](https://www.8thwall.com/docs/api/engine/xrcontroller/hittest/),
[tracking data](https://www.8thwall.com/docs/api/engine/xrcontroller/pipelinemodule/).
