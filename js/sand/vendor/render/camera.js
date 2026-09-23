// SPDX-License-Identifier: GPL-3.0-only
// Adapted from scottstts/Sandboard via Threejs-Awesome-Graphics-Agent-Skills.
// Revision d1cb23dcce6ea8ee4a60f6159daeb79d4b511dba; see js/sand/NOTICE.md.
import { SAND } from '../config.js';
export function normalize(vector) {
    const length = Math.hypot(...vector);
    return vector.map((component)=>component / length);
}
export class SandCamera {
    eye = [
        0,
        0.52,
        0.26
    ];
    forward = normalize([
        0,
        SAND.depth - this.eye[1],
        -this.eye[2]
    ]);
    right = [
        1,
        0,
        0
    ];
    up = [
        0,
        -this.forward[2],
        this.forward[1]
    ];
    distance = Math.hypot(this.eye[1] - SAND.depth, this.eye[2]);
    aspect = 1;
    get tanHalfFov() {
        return 0.22 / this.distance / Math.max(1, this.aspect);
    }
    setView(eye, target) {
        const nextEye = [
            eye[0] ?? 0,
            eye[1] ?? 0,
            eye[2] ?? 0
        ];
        const direction = [
            (target[0] ?? 0) - nextEye[0],
            (target[1] ?? SAND.depth) - nextEye[1],
            (target[2] ?? 0) - nextEye[2]
        ];
        const forward = normalize(direction);
        const cross = (a, b)=>[
                a[1] * b[2] - a[2] * b[1],
                a[2] * b[0] - a[0] * b[2],
                a[0] * b[1] - a[1] * b[0]
            ];
        const right = normalize(cross(forward, [
            0,
            1,
            0
        ]));
        this.eye = nextEye;
        this.forward = forward;
        this.right = right;
        this.up = normalize(cross(right, forward));
        this.distance = Math.max(Math.hypot(...direction), 1e-4);
    }
    screenToBed(clientX, clientY, width, height) {
        const horizontal = (2 * clientX / width - 1) * this.tanHalfFov * this.aspect;
        const vertical = (1 - 2 * clientY / height) * this.tanHalfFov;
        const direction = this.forward.map((component, axis)=>component + horizontal * this.right[axis] + vertical * this.up[axis]);
        const distance = (SAND.depth - this.eye[1]) / direction[1];
        return {
            x: this.eye[0] + direction[0] * distance,
            y: this.eye[2] + direction[2] * distance
        };
    }
}
