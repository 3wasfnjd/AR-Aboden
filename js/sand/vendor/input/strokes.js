// SPDX-License-Identifier: GPL-3.0-only
// Adapted from scottstts/Sandboard via Threejs-Awesome-Graphics-Agent-Skills.
// Revision d1cb23dcce6ea8ee4a60f6159daeb79d4b511dba; see js/sand/NOTICE.md.
import { SAND, idleStroke } from '../config.js';
const minimumSampleSeconds = 0.0001;
const nonAdvancingSampleSeconds = SAND.step * 0.5;
const minimumMovement = 1e-7;
export const maxQueuedSegmentsPerPointer = SAND.maxContacts * SAND.maxSteps * 4;
export class StrokeQueue {
    tracks = new Map();
    roundRobin = 0;
    currentPressure = 0.7;
    position = {
        x: 0,
        y: 0
    };
    radius = SAND.radius;
    begin(point, pressure, time, pointerId = 0) {
        const bounded = this.bound(point);
        const existing = this.tracks.get(pointerId);
        const timestamp = this.timestamp(existing, time);
        const start = {
            ...bounded,
            time: timestamp
        };
        this.position = bounded;
        this.currentPressure = this.clampPressure(pressure);
        this.tracks.set(pointerId, {
            held: true,
            pressure: this.currentPressure,
            start,
            latest: start,
            latestTime: timestamp,
            segments: existing?.segments ?? []
        });
    }
    move(point, pressure, time, pointerId = 0) {
        const bounded = this.bound(point);
        this.position = bounded;
        this.currentPressure = this.clampPressure(pressure);
        const track = this.tracks.get(pointerId);
        if (!track || !track.held) return;
        const timestamp = this.timestamp(track, time);
        track.pressure = this.currentPressure;
        track.latestTime = timestamp;
        track.latest = {
            ...bounded,
            time: timestamp
        };
        this.subdivide(track);
    }
    end(pointerId = 0) {
        const track = this.tracks.get(pointerId);
        if (!track) return;
        track.held = false;
        this.flush(track);
        this.prune(pointerId, track);
    }
    cancel(pointerId) {
        if (pointerId === undefined) {
            this.tracks.clear();
            this.roundRobin = 0;
            return;
        }
        this.tracks.delete(pointerId);
        if (this.roundRobin >= this.tracks.size) this.roundRobin = 0;
    }
    clampPressure(pressure) {
        return Math.max(0.1, Math.min(1, pressure));
    }
    bound(point) {
        const limit = SAND.extent / 2 - 0.03;
        return {
            x: Math.max(-limit, Math.min(limit, point.x)),
            y: Math.max(-limit, Math.min(limit, point.y))
        };
    }
    timestamp(track, time) {
        const previous = track?.latestTime;
        const fallback = (previous ?? -SAND.step * 1000) + SAND.step * 1000;
        const candidate = time !== undefined && Number.isFinite(time) ? time : fallback;
        return previous === undefined ? candidate : Math.max(previous, candidate);
    }
    spacing() {
        return Math.max(SAND.extent / SAND.resolution * 1.5, this.radius * 0.5);
    }
    makeStroke(from, to, pressure) {
        const rawDuration = (to.time - from.time) / 1000;
        const duration = rawDuration > 0 ? Math.max(minimumSampleSeconds, rawDuration) : nonAdvancingSampleSeconds;
        return {
            from: {
                x: from.x,
                y: from.y
            },
            to: {
                x: to.x,
                y: to.y
            },
            velocity: {
                x: (to.x - from.x) / duration,
                y: (to.y - from.y) / duration
            },
            radius: this.radius,
            pressure,
            active: true
        };
    }
    subdivide(track) {
        const spacing = this.spacing();
        let distance = Math.hypot(track.latest.x - track.start.x, track.latest.y - track.start.y);
        while(distance >= spacing){
            const fraction = spacing / distance;
            const to = {
                x: track.start.x + (track.latest.x - track.start.x) * fraction,
                y: track.start.y + (track.latest.y - track.start.y) * fraction,
                time: track.start.time + (track.latest.time - track.start.time) * fraction
            };
            track.segments.push(this.makeStroke(track.start, to, track.pressure));
            this.trimBacklog(track);
            track.start = to;
            distance = Math.hypot(track.latest.x - track.start.x, track.latest.y - track.start.y);
        }
    }
    flush(track) {
        const distance = Math.hypot(track.latest.x - track.start.x, track.latest.y - track.start.y);
        if (distance > minimumMovement) {
            track.segments.push(this.makeStroke(track.start, track.latest, track.pressure));
            this.trimBacklog(track);
        }
        track.start = track.latest;
    }
    trimBacklog(track) {
        const overflow = track.segments.length - maxQueuedSegmentsPerPointer;
        if (overflow > 0) track.segments.splice(0, overflow);
    }
    prune(pointerId, track) {
        if (!track.held && track.segments.length === 0) this.tracks.delete(pointerId);
    }
    drain(limit) {
        for (const track of this.tracks.values())if (track.held) this.flush(track);
        const entries = [
            ...this.tracks.entries()
        ];
        if (!entries.length) return [];
        const result = [];
        let emptyPasses = 0;
        let cursor = this.roundRobin % entries.length;
        while(result.length < limit && emptyPasses < entries.length){
            const [pointerId, track] = entries[cursor];
            const stroke = track.segments.shift();
            if (stroke) {
                result.push(stroke);
                emptyPasses = 0;
                this.prune(pointerId, track);
            } else {
                emptyPasses++;
            }
            cursor = (cursor + 1) % entries.length;
        }
        this.roundRobin = cursor;
        return result;
    }
    nextBatch() {
        return this.drain(SAND.maxContacts);
    }
    next() {
        return this.drain(1)[0] ?? {
            ...idleStroke(),
            from: this.position,
            to: this.position,
            radius: this.radius,
            pressure: this.currentPressure
        };
    }
    get cursor() {
        return {
            ...idleStroke(),
            from: this.position,
            to: this.position,
            radius: this.radius
        };
    }
}
