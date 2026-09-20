# AR drift spectator show

The arena now starts an autonomous show immediately after placement. Joystick
and handbrake inputs are removed from this page; placement, size, repositioning
and home controls remain. Tracking loss/backgrounding pauses simulation time.
Repositioning starts a new show and clears smoke/tire marks from the old location.

`js/ar/ArenaAutopilot.js` adapts the free-roam AI in
[hajwala AIController.js](https://github.com/3wasfnjd/hajwala/blob/4c9e421b469118c353724944a3b1465a0c1c0fc0/js/AIController.js):
CRUISING / DRIFTING / DONUT / AVOIDANCE states, wrapped heading-error steering,
and rhythmic donut handbrake pulses. The source MIT notice is retained in
`HAJWALA_LICENSE.txt`.

This is an adaptation, not an unchanged copy: for a spectator show, a bounded
planar motion integrator replaces the free physics sphere. Low lateral grip
produces heading/velocity slip, while the existing vehicle visual animation,
smoke and tire-mark systems render the result. Timers use active simulation time
instead of wall-clock time; no stuck-watchdog teleport is used in normal motion.

The car's maximum model dimension is 0.30 m at 100%, down from 0.42 m (~29%).
Effects scale proportionally. Its actual loaded horizontal bounds determine a
rotation-independent footprint envelope. At each arena size the controller
reserves that envelope plus 0.10 m (scaled) inside a 1.30 m road radius. Inspection
of the normalized current arena GLB found raised barrier vertices (Y > .06 m)
at radii >= 1.374 m. Recheck the road radius if this asset is replaced.

Avoidance predicts motion 0.65 seconds ahead and brakes outward velocity before
the edge. A final radial constraint protects the whole vehicle footprint. Normal
seeded simulations are required to stay inside without activating this correction.

Run `node --test tests/*.test.mjs`. Tests include five-minute shows across three
arena sizes and three frame rates, scale/translation invariance, distinct drift
states, footprint containment, and the actual page's tracking/pause frame loop.
These checks establish numerical behavior, not real-phone rendering/tracking quality.
