// SPDX-License-Identifier: GPL-3.0-only
// Adapted from scottstts/Sandboard via Threejs-Awesome-Graphics-Agent-Skills.
// Revision d1cb23dcce6ea8ee4a60f6159daeb79d4b511dba; see js/sand/NOTICE.md.
export class FixedClock {
    previous;
    accumulator = 0;
    droppedSeconds = 0;
    step;
    maxSteps;
    constructor(step, maxSteps){
        this.step = step;
        this.maxSteps = maxSteps;
    }
    advance(now) {
        if (this.previous === undefined) {
            this.previous = now;
            return 0;
        }
        const elapsed = Math.max(0, (now - this.previous) / 1000);
        this.previous = now;
        const budget = this.step * this.maxSteps;
        this.droppedSeconds += Math.max(0, elapsed - budget);
        this.accumulator += Math.min(elapsed, budget);
        const count = Math.min(this.maxSteps, Math.floor((this.accumulator + 1e-9) / this.step));
        this.accumulator -= count * this.step;
        return count;
    }
    reset(now) {
        this.previous = now;
        this.accumulator = 0;
    }
}
