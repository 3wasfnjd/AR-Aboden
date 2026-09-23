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

## Audio

This experiment intentionally does **not** use the Project I.G.I. recordings present in `operation-ink/public/sounds/igi/`.

It loads only the fallback sound files credited as CC0 by the upstream project:

- `shot_pistol_0.m4a`
- `shot_rifle_0.m4a`
- `hit_flesh_0.m4a`
- `hit_world_0.m4a`

Upstream credits identify these as derived from OpenGameArt/Kenney CC0 assets. See the upstream `public/sounds/CREDITS.md` for the original source links and processing notes.

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
