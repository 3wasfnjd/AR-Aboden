// SPDX-License-Identifier: GPL-3.0-only
// Adapted from scottstts/Sandboard via Threejs-Awesome-Graphics-Agent-Skills.
// Revision d1cb23dcce6ea8ee4a60f6159daeb79d4b511dba; see js/sand/NOTICE.md.
import { SAND } from '../config.js';
const defaultWaveSeconds = 4.754;
const enterFraction = 0.44;
const exitSearchSamples = 96;
export const WAVE_RESET = {
    coverageMargin: 0.10,
    visibleInset: 0.030,
    shorelineTilt: -0.060,
    shorelineAmplitude: 0.018,
    shorelineFrequencyA: 20.0,
    shorelineFrequencyB: 10.0,
    shorelineFrequencyC: 5.2,
    shorelineSpeedA: 1.55,
    shorelineSpeedB: -0.94,
    shorelineSpeedC: 0.62,
    shorelineBlend: 0.50,
    shorelineFeather: 0.018,
    waterMaskBackstep: 0.06,
    foamWidth: 0.052,
    foamTrail: 0.090,
    waterDepth: 0.14,
    waterOpacity: 0.50,
    waterTintStrength: 0.58,
    washGloss: 0.42,
    rippleScale: 24,
    rippleDrift: 0.48
};
const halfExtent = SAND.extent * 0.5;
const renderEntryFront = halfExtent - WAVE_RESET.visibleInset;
const crestFront = -halfExtent - WAVE_RESET.coverageMargin;
const eraseOriginFront = halfExtent + WAVE_RESET.coverageMargin;
const dryWaterMaskDistance = -WAVE_RESET.shorelineFeather * WAVE_RESET.waterMaskBackstep;
const fullBedViewport = {
    minX: -halfExtent,
    maxX: halfExtent,
    nearY: halfExtent
};
function smooth(value) {
    const t = Math.max(0, Math.min(1, value));
    return t * t * (3 - 2 * t);
}
function mix(from, to, amount) {
    return from + (to - from) * amount;
}
export function shorelineOffsetAt(x, time) {
    const breakerA = Math.sin(x * WAVE_RESET.shorelineFrequencyA + time * WAVE_RESET.shorelineSpeedA);
    const breakerB = Math.sin(x * WAVE_RESET.shorelineFrequencyB + time * WAVE_RESET.shorelineSpeedB + 1.7);
    const breakerC = Math.sin(x * WAVE_RESET.shorelineFrequencyC - time * WAVE_RESET.shorelineSpeedC + 0.6);
    return x * WAVE_RESET.shorelineTilt + WAVE_RESET.shorelineAmplitude * (breakerA + breakerB * WAVE_RESET.shorelineBlend) + WAVE_RESET.shorelineAmplitude * 0.55 * breakerC;
}
function normalizedViewport(viewport = fullBedViewport) {
    const rawMinX = Math.min(viewport.minX, viewport.maxX);
    const rawMaxX = Math.max(viewport.minX, viewport.maxX);
    const minX = Number.isFinite(rawMinX) ? rawMinX : fullBedViewport.minX;
    const maxX = Number.isFinite(rawMaxX) ? rawMaxX : fullBedViewport.maxX;
    const nearY = Number.isFinite(viewport.nearY) ? viewport.nearY : fullBedViewport.nearY;
    return {
        minX,
        maxX,
        nearY
    };
}
function minimumShorelineOffsetAt(time, viewport = fullBedViewport) {
    const visible = normalizedViewport(viewport);
    let minimum = Number.POSITIVE_INFINITY;
    let minimumIndex = 0;
    for(let index = 0; index <= exitSearchSamples; index++){
        const x = visible.minX + (visible.maxX - visible.minX) * index / exitSearchSamples;
        const value = shorelineOffsetAt(x, time);
        if (value < minimum) {
            minimum = value;
            minimumIndex = index;
        }
    }
    let left = visible.minX + (visible.maxX - visible.minX) * Math.max(0, minimumIndex - 1) / exitSearchSamples;
    let right = visible.minX + (visible.maxX - visible.minX) * Math.min(exitSearchSamples, minimumIndex + 1) / exitSearchSamples;
    for(let iteration = 0; iteration < 16; iteration++){
        const third = (right - left) / 3;
        const a = left + third;
        const b = right - third;
        if (shorelineOffsetAt(a, time) <= shorelineOffsetAt(b, time)) right = b;
        else left = a;
    }
    return Math.min(minimum, shorelineOffsetAt((left + right) * 0.5, time));
}
export function renderExitFrontAt(time, viewport = fullBedViewport) {
    const visible = normalizedViewport(viewport);
    const dryVisibleFront = visible.nearY - dryWaterMaskDistance;
    return dryVisibleFront - minimumShorelineOffsetAt(time, visible);
}
const renderExitFront = renderExitFrontAt(defaultWaveSeconds);
export function idleWaveResetState() {
    return {
        active: false,
        incoming: false,
        justStarted: false,
        justFinished: false,
        erase: false,
        time: 0,
        previousBaseFront: renderExitFront,
        currentBaseFront: renderExitFront,
        progress: 0,
        erasePreviousBaseFront: eraseOriginFront,
        eraseCurrentBaseFront: eraseOriginFront,
        erasePreviousTime: 0,
        eraseCurrentTime: 0
    };
}
export class WaveResetEffect {
    active = false;
    startedAt = 0;
    durationSeconds = defaultWaveSeconds;
    renderExitFront = renderExitFront;
    viewport = fullBedViewport;
    retreatStartEnvelope = crestFront + minimumShorelineOffsetAt(defaultWaveSeconds * enterFraction);
    retreatExitEnvelope = halfExtent - dryWaterMaskDistance;
    previousRenderFront = renderEntryFront;
    previousEraseFront = eraseOriginFront;
    previousEraseTime = 0;
    firstUpdate = true;
    start(now, durationSeconds, viewport = fullBedViewport) {
        this.active = true;
        this.startedAt = now;
        this.durationSeconds = Number.isFinite(durationSeconds) && durationSeconds && durationSeconds > 0 ? durationSeconds : defaultWaveSeconds;
        const enterSeconds = this.durationSeconds * enterFraction;
        this.viewport = normalizedViewport(viewport);
        this.renderExitFront = renderExitFrontAt(this.durationSeconds, this.viewport);
        this.retreatStartEnvelope = crestFront + minimumShorelineOffsetAt(enterSeconds, this.viewport);
        this.retreatExitEnvelope = this.viewport.nearY - dryWaterMaskDistance;
        this.previousRenderFront = renderEntryFront;
        this.previousEraseFront = eraseOriginFront;
        this.previousEraseTime = 0;
        this.firstUpdate = true;
    }
    update(now) {
        if (!this.active) return idleWaveResetState();
        const elapsedSeconds = Math.max(0, (now - this.startedAt) / 1000);
        const enterSeconds = Math.max(this.durationSeconds * enterFraction, 0.001);
        const retreatSeconds = Math.max(this.durationSeconds - enterSeconds, 0.001);
        const previousRenderFront = this.previousRenderFront;
        const eraseCurrentTime = Math.min(elapsedSeconds, enterSeconds);
        const eraseProgress = smooth(eraseCurrentTime / enterSeconds);
        const eraseCurrentFront = mix(renderEntryFront, crestFront, eraseProgress);
        const erase = eraseCurrentFront < this.previousEraseFront - 1e-6;
        let incoming = true;
        let progress;
        let currentRenderFront;
        let active = true;
        let justFinished = false;
        if (elapsedSeconds < enterSeconds) {
            progress = smooth(elapsedSeconds / enterSeconds);
            currentRenderFront = mix(renderEntryFront, crestFront, progress);
        } else if (elapsedSeconds < this.durationSeconds) {
            incoming = false;
            progress = smooth((elapsedSeconds - enterSeconds) / retreatSeconds);
            const shorelineEnvelope = mix(this.retreatStartEnvelope, this.retreatExitEnvelope, progress);
            currentRenderFront = shorelineEnvelope - minimumShorelineOffsetAt(elapsedSeconds, this.viewport);
        } else {
            incoming = false;
            progress = 1;
            currentRenderFront = this.renderExitFront;
            active = false;
            justFinished = true;
        }
        const state = {
            active,
            incoming,
            justStarted: this.firstUpdate,
            justFinished,
            erase,
            time: Math.min(elapsedSeconds, this.durationSeconds),
            previousBaseFront: previousRenderFront,
            currentBaseFront: currentRenderFront,
            progress,
            erasePreviousBaseFront: this.previousEraseFront,
            eraseCurrentBaseFront: eraseCurrentFront,
            erasePreviousTime: this.previousEraseTime,
            eraseCurrentTime
        };
        this.firstUpdate = false;
        this.previousRenderFront = currentRenderFront;
        if (erase) {
            this.previousEraseFront = eraseCurrentFront;
            this.previousEraseTime = eraseCurrentTime;
        }
        if (justFinished) this.active = false;
        return state;
    }
}
export { crestFront, dryWaterMaskDistance, eraseOriginFront, renderEntryFront, renderExitFront };
