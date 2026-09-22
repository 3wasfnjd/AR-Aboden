# رماية عبودين

Open `gallery.html` from the home page. Choose mixed, stationary or moving targets.
The AR button starts the existing 8th Wall camera engine. Aim towards a clear
space in front of you, adjust scale/height if needed, and place the stage.
Placement uses a horizontal plane relative to the initial camera pose; this is
not semantic floor or furniture detection. Real-device tracking must be checked
on the intended phone/browser.

The camera-free preview is fully playable by clicking/tapping a target. A mouse
can also aim while Space or the trigger button fires. R reloads; Escape pauses.
In AR, aim with the centre reticle and press the trigger.

- Each round: 60 seconds, 24 shots, 6 shots per magazine.
- Fixed target: 10 points; centre: 25; moving duck: 35.
- Empty magazines reload automatically. Manual reload does not discard shots.
- Hit targets fold and temporarily stop accepting hits.
- The timer pauses when the page is hidden or the player presses Pause.
- Best scores are stored locally and separately for each target mode.
- No camera feed is recorded or uploaded by this experiment's code.

## Stage

There is no booth backdrop model. `js/gallery/stage.js` builds the counter/rack
scenery procedurally and loads only the target models (`duck-target.glb`,
`tin-can.glb`, `rifle.glb`); targets, target rails, scoring and UI stay
independent of each other.

See `assets/gallery/CREDITS.md` for source/license and adaptations.

## Verification

Browser checks cover target modes, bullseye scoring, ammunition, automatic
reload, round completion, restart, pause and responsive layouts. A simulated
tracker checks AR placement and camera-projection preservation; this is not a
substitute for physical-device AR verification.
