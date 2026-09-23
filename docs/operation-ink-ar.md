# Operation Ink AR integration

This experiment adapts combat-system ideas and balancing values from:

- `byteab/operation-ink` / **Operation Safe Return**
- Source code license: MIT
- Copyright (c) 2026 Ehsan Sarshar

The AR-Aboden integration is a fresh XR8/mobile implementation rather than a copy of the original mission runtime. It reuses the MIT-licensed weapon balance and AI-state concepts (patrol, suspicious, combat, search/reposition).

## Enemy character model

The AR enemy presentation uses the **Character Soldier** from Quaternius' Toon Shooter Game Kit, released under CC0 1.0. The runtime currently loads the web-optimized `soldier_t.glb` derivative published by the open-source Tiny Strike project. Tiny Strike documents that this GLB is derived from the Quaternius CC0 asset and processed for web use.

The integration keeps its own invisible hit proxies for head/torso/arms/legs, scales the rendered GLB to a 1.20 m target height (25% smaller than the previous 1.60 m setting), and scales the hit proxies and fallback muzzle with it. It aligns the standing pose's lowest bound with the detected AR floor and locks each enemy root to the captured floor Y while AI movement changes only X/Z.

Enemy roots and the GLB both face +Z. Every live AI state turns toward the current tracked phone position independently of its movement direction. The GLB muzzle is attached to the selected weapon's barrel tip so traces follow its animated hand and scale. Combat, movement, and wave/reload timers pause when tracking is lost; the user must touch again to resume automatic fire after tracking returns.

Animation clips used when present: `Idle`, `Walk`, `Idle_Shoot`, `Walk_Shoot`, and `Death`. The primitive soldier remains as a fallback if the external GLB cannot be loaded.

## Enemy movement

Spawns and movement stay in a forward sector relative to the phone's horizontal viewing direction: 1.8–5.8 m forward, with lateral distance capped at 65% of forward distance. Spawn spread also respects the camera's horizontal field of view. Each soldier independently chooses short paths, speed changes and pauses; walking animation timing follows its individual speed. Separation checks prevent walking through another soldier. The old shared circular patrol and player-encircling reposition are removed. All living soldiers keep facing the phone.

If a camera turn puts a soldier behind the view, it re-enters ahead from outside the view rather than circling behind the user. The captured floor height stays fixed. When the phone points straight down, movement keeps the last usable horizontal heading.

## Paintball mode

Player shots are blue paintballs and enemy shots are orange. Balls travel from the weapon muzzle; segment raycasts detect contact during flight, so damage and impact feedback occur on arrival. Paintballs retain the weapon's damage at launch, even if the player switches weapons during flight. Enemy balls target the tracked phone and can be dodged; invincible test mode remains enabled.

Stains last six seconds on soldiers or the captured floor. Soldier stains are aligned to the visible mesh and follow a nearby bone. Real walls/furniture are not collision surfaces because this experiment only captures the ground plane. Phone hits show a brief orange stain near the screen edge.

`PaintballEffects.js` renders balls and spray droplets in one instanced draw. Limits: 48 balls, 80 droplets, 24 stains. Stains fade out, and reset/dispose clears all paint effects. Projectiles pause while tracking is unavailable.

## Audio

Short air-pop and splat sounds are synthesized with Web Audio after a user gesture. This mode does not download or play firearm/flesh recordings. Noise is reused from one small audio buffer and each sound's nodes disconnect after playback.

## Mobile UI

The combat view keeps only Home, the placement/status text, crosshair and a compact weapon strip. Ammo, score/wave/enemy count, manual reload and recenter panels are intentionally omitted. Reload starts automatically as soon as the active magazine becomes empty; automatic weapons resume after reload while the same press remains held.

The page locks Safari to scale 1, disables selection/callouts and text resizing, and cancels Safari gesture, multi-touch pinch, double-tap and selection events. Interactive controls retain `touch-action: manipulation` while the game surface continues using pointer events for firing.

## Fast estimated placement

This experiment does not wait for the shared high-confidence surface sampler. After about 280 ms of normal tracking, it uses the centre ray's estimated ground intersection when available; otherwise it places the anchor 2.8 m ahead on XR8's default `y=0` floor. The preview appears briefly and combat starts automatically about 100 ms later. Tracking loss still pauses combat.

## Programmatic weapon icons

The five weapon selectors are created at runtime and rendered as distinct Canvas 2D silhouettes for pistol, AK, SMG, shotgun and sniper. No image assets or text labels are displayed. The underlying compact buttons retain Arabic `aria-label` and `aria-pressed` attributes for touch and accessibility.

## Upstream MIT notice

MIT License

Copyright (c) 2026 Ehsan Sarshar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE.
