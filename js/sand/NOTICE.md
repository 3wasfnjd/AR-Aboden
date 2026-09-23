# Sand writing: source and license

This isolated experience (`sand.html`, `sand.css`, `js/sand/` and
`assets/sand/`) is distributed under **GPL-3.0-only**. The complete license is
in [LICENSE.txt](LICENSE.txt). This notice does not change the licenses of the
other, separate AR-Aboden experiences.

The sand simulation, shaders, stroke input, camera, shadows and wave reset are
adapted from **scottstts/Sandboard**, as distributed in:

- https://github.com/scottstts/Threejs-Awesome-Graphics-Agent-Skills
- Revision: `d1cb23dcce6ea8ee4a60f6159daeb79d4b511dba`
- Original directory: `skills/threejs-procedural-materials/examples/deformable-sand/`
- Original project: https://github.com/scottstts/Sandboard

The upstream collection's MIT notice for its gallery integration material is
also preserved in `UPSTREAM-MIT.txt`; the sand engine's specific GPL notice
takes precedence for the sand source and asset.

The optional `assets/sand/coconut_tree.glb` comes from the same revision's
`example-gallery/examples/threejs-procedural-materials/deformable-sand/assets/`
and is also GPL-3.0-only, as identified by the upstream third-party notice.

Modifications for AR-Aboden (2026-09-23): TypeScript annotations removed,
relative imports given `.js` extensions, readable JavaScript used as the
maintained source, and Arabic touch UI/lifecycle integration added. All source
is shipped here without minification or a build step. Mobile uses a 384²
simulation grid and a capped drawing buffer; desktop uses the original 512².
The original sand transport, grain and water shaders are retained.
