// SPDX-License-Identifier: GPL-3.0-only
// Adapted from scottstts/Sandboard via Threejs-Awesome-Graphics-Agent-Skills.
// Revision d1cb23dcce6ea8ee4a60f6159daeb79d4b511dba; see js/sand/NOTICE.md.
export function waveResetViewport(camera) {
    const bottomLeft = camera.screenToBed(0, 1, 1, 1);
    const bottomRight = camera.screenToBed(1, 1, 1, 1);
    const minX = Math.min(bottomLeft.x, bottomRight.x);
    const maxX = Math.max(bottomLeft.x, bottomRight.x);
    const nearY = Math.max(bottomLeft.y, bottomRight.y);
    return {
        minX,
        maxX,
        nearY
    };
}
