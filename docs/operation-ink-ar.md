# Operation Ink AR integration

This experiment adapts combat-system ideas and balancing values from:

- `byteab/operation-ink` / **Operation Safe Return**
- Source code license: MIT
- Copyright (c) 2026 Ehsan Sarshar

The AR-Aboden integration is a fresh XR8/mobile implementation rather than a copy of the original mission runtime. It reuses the MIT-licensed weapon balance and AI-state concepts (patrol, suspicious, combat, search/reposition).

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
