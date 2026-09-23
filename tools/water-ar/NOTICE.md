# Water AR Lab — source and license notices

The pool simulation and optical materials are imported, at a fixed revision, from:
https://github.com/scottstts/Threejs-Awesome-Graphics-Agent-Skills/blob/d1cb23dcce6ea8ee4a60f6159daeb79d4b511dba/skills/threejs-water-optics/examples/interactive-pool-volume/water-volume-system.js

That example adapts https://github.com/jeantimex/threejs-water, a port of Evan Wallace's WebGL Water. The AR adapter adds pool-local optical transforms, bounded mobile updates, render-state isolation and independent placement/input/UI. The generated tile and studio cubemap are local prototype assets; no real-camera environment capture is performed.

## MIT License

Copyright (c) 2026 Scott Sun
Original work Copyright (c) 2011 Evan Wallace
Modified work Copyright (c) 2026 Yong Su

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
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Runtime dependencies

Three.js (MIT): https://github.com/mrdoob/three.js/blob/dev/LICENSE

8th Wall engine is loaded separately from its npm package using the same channel as the existing AR-Aboden experiments; its own package terms apply. It is not relicensed by this notice. No engine binaries are copied into this folder.
