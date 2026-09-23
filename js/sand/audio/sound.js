// SPDX-License-Identifier: GPL-3.0-only
// Original Sandboard audio, revision 489cb01e81b11ba575887f7c76760498eb41aaa8.
// See js/sand/NOTICE.md for attribution and local changes.
import { sandWorkletSource } from './sand-worklet.js';
const ambientVolume = 0.08;
const waveVolume = 0.92;
const proceduralVolume = 0.34;
const minimumSampleMilliseconds = 1;
const motionHoldMilliseconds = 55;
function normalizedSpeed(pxPerSecond) {
    return Math.max(0, Math.min(1, (pxPerSecond - 24) / 1080));
}
function penPressure(event) {
    return event.pointerType === 'pen' ? event.pressure : 0;
}
function isAppleMobile() {
    return /iPhone|iPad|iPod/.test(navigator.userAgent) || navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
}
function requestPlaybackAudioSession() {
    if (!isAppleMobile()) return;
    const session = navigator.audioSession;
    if (!session) return;
    try {
        session.type = 'playback';
    } catch  {
        return;
    }
}
export class SandSound {
    ambient = new Audio(new URL('../../../assets/sand/beach.mp3', import.meta.url).href);
    wave = new Audio(new URL('../../../assets/sand/wave.mp3', import.meta.url).href);
    gestures = new Map();
    unlockController = new AbortController();
    context;
    ambientSource;
    ambientGain;
    waveSource;
    waveGain;
    sandNode;
    proceduralGain;
    proceduralReady;
    prepareReady;
    waveMetadataReady;
    waveDuration = 4.754;
    disposed = false;
    muted = false;
    paused = false;
    resumeWave = false;
    constructor(){
        this.ambient.loop = true;
        this.ambient.preload = 'auto';
        this.ambient.volume = 1;
        this.ambient.setAttribute('playsinline', '');
        this.wave.preload = 'auto';
        this.wave.volume = 1;
        this.wave.setAttribute('playsinline', '');
        this.waveMetadataReady = this.loadWaveMetadata();
        const unlock = ()=>{
            this.activatePlayback();
        };
        const { signal } = this.unlockController;
        window.addEventListener('pointerdown', unlock, {
            signal,
            passive: true
        });
        window.addEventListener('keydown', unlock, {
            signal
        });
    }
    prepare() {
        if (this.prepareReady) return this.prepareReady;
        this.prepareReady = Promise.all([
            this.prepareAudio(),
            this.waveMetadataReady
        ]).then(()=>undefined);
        return this.prepareReady;
    }
    beginPointer(event) {
        if (this.disposed || this.muted || this.paused) return;
        this.activatePlayback();
        this.gestures.set(event.pointerId, {
            x: event.clientX,
            y: event.clientY,
            time: event.timeStamp,
            velocityX: 0,
            velocityY: 0,
            filteredSpeed: 0,
            speed: 0.025,
            pressure: penPressure(event),
            turn: 0,
            audibleUntil: performance.now() + motionHoldMilliseconds
        });
        this.sendGestureState();
    }
    movePointer(event, pointerId = event.pointerId) {
        const track = this.gestures.get(pointerId);
        if (!track) return;
        const dt = Math.max(minimumSampleMilliseconds, event.timeStamp - track.time) / 1000;
        const dx = event.clientX - track.x;
        const dy = event.clientY - track.y;
        const distance = Math.hypot(dx, dy);
        const rawSpeed = distance / dt;
        const blend = 1 - Math.exp(-dt * 18);
        track.filteredSpeed += (rawSpeed - track.filteredSpeed) * blend;
        const velocityX = dx / dt;
        const velocityY = dy / dt;
        const velocityMagnitude = Math.hypot(velocityX, velocityY);
        const oldMagnitude = Math.hypot(track.velocityX, track.velocityY);
        let turn = 0;
        if (velocityMagnitude > 20 && oldMagnitude > 20) {
            const dot = (velocityX * track.velocityX + velocityY * track.velocityY) / (velocityMagnitude * oldMagnitude);
            turn = Math.max(0, Math.min(1, (1 - dot) * 0.72));
        }
        const acceleration = Math.hypot(velocityX - track.velocityX, velocityY - track.velocityY) / Math.max(3000, velocityMagnitude * 8);
        turn = Math.min(1, turn + acceleration * 0.35);
        track.x = event.clientX;
        track.y = event.clientY;
        track.time = event.timeStamp;
        track.velocityX = velocityX;
        track.velocityY = velocityY;
        track.speed = normalizedSpeed(track.filteredSpeed);
        track.pressure = penPressure(event);
        track.turn = turn;
        if (distance > 0) track.audibleUntil = performance.now() + motionHoldMilliseconds;
        this.sendGestureState();
    }
    update(now) {
        if (this.gestures.size) this.sendGestureState(now);
    }
    endPointer(pointerId) {
        if (!this.gestures.delete(pointerId)) return;
        this.sendGestureState();
    }
    cancelAll() {
        if (!this.gestures.size) return;
        this.gestures.clear();
        this.sendGestureState();
    }
    setMuted(muted) {
        this.muted = Boolean(muted);
        for (const [node, level] of [[this.ambientGain, ambientVolume], [this.waveGain, waveVolume], [this.proceduralGain, proceduralVolume]]) {
            if (node) node.gain.setTargetAtTime(this.muted ? 0 : level, this.context.currentTime, 0.015);
        }
        if (this.muted) {
            this.cancelAll();
            this.ambient.pause();
        } else if (!this.paused) {
            this.activatePlayback();
        }
    }
    setPaused(paused) {
        if (this.disposed || this.paused === Boolean(paused)) return;
        this.paused = Boolean(paused);
        if (this.paused) {
            this.resumeWave = !this.wave.paused;
            this.cancelAll();
            this.ambient.pause();
            this.wave.pause();
            void this.context?.suspend().catch(() => undefined);
        } else {
            this.activatePlayback();
            if (this.resumeWave && !this.muted) void this.wave.play().catch(() => undefined);
            this.resumeWave = false;
        }
    }
    stopResetWave() {
        this.resumeWave = false;
        this.wave.pause();
        try { this.wave.currentTime = 0; } catch {}
    }
    dispose() {
        if (this.disposed) return;
        this.disposed = true;
        this.unlockController.abort();
        this.cancelAll();
        this.sandNode?.disconnect();
        this.sandNode = undefined;
        this.ambientSource?.disconnect();
        this.ambientSource = undefined;
        this.ambientGain?.disconnect();
        this.ambientGain = undefined;
        this.waveSource?.disconnect();
        this.waveSource = undefined;
        this.waveGain?.disconnect();
        this.waveGain = undefined;
        this.proceduralGain?.disconnect();
        this.proceduralGain = undefined;
        if (this.context) void this.context.close().catch(() => undefined);
        this.context = undefined;
        this.ambient.pause();
        this.stopResetWave();
        this.ambient.removeAttribute('src');
        this.wave.removeAttribute('src');
        this.ambient.load();
        this.wave.load();
    }
    async prepareAudio() {
        if (this.disposed) return;
        const context = this.ensureContext();
        const procedural = this.ensureProcedural(context);
        this.activatePlayback();
        await procedural;
    }
    activatePlayback() {
        if (this.disposed || this.muted || this.paused) return;
        const context = this.ensureContext();
        if (context.state !== 'running') void context.resume().catch(()=>undefined);
        void this.playAmbient();
        void this.ensureProcedural(context).then(()=>this.sendGestureState());
    }
    ensureContext() {
        if (this.context) return this.context;
        requestPlaybackAudioSession();
        const context = new AudioContext({
            latencyHint: 'interactive'
        });
        const ambientSource = context.createMediaElementSource(this.ambient);
        const ambientGain = new GainNode(context, {
            gain: this.muted ? 0 : ambientVolume
        });
        ambientSource.connect(ambientGain).connect(context.destination);
        const waveSource = context.createMediaElementSource(this.wave);
        const waveGain = new GainNode(context, {
            gain: this.muted ? 0 : waveVolume
        });
        waveSource.connect(waveGain).connect(context.destination);
        this.context = context;
        this.ambientSource = ambientSource;
        this.ambientGain = ambientGain;
        this.waveSource = waveSource;
        this.waveGain = waveGain;
        return context;
    }
    get resetDurationSeconds() {
        return this.waveDuration;
    }
    playResetWave() {
        if (this.disposed || this.muted || this.paused) return this.waveDuration;
        this.activatePlayback();
        this.wave.pause();
        try {
            this.wave.currentTime = 0;
        } catch  {}
        void this.wave.play().catch(()=>undefined);
        return this.waveDuration;
    }
    loadWaveMetadata() {
        return new Promise((resolve)=>{
            let timeout;
            const finalize = ()=>{
                clearTimeout(timeout);
                const duration = this.wave.duration;
                if (Number.isFinite(duration) && duration > 0) this.waveDuration = duration;
                resolve();
            };
            if (this.wave.readyState >= HTMLMediaElement.HAVE_METADATA) {
                finalize();
                return;
            }
            // Missing/slow audio must never block the sand experience forever.
            timeout = setTimeout(finalize, 4000);
            const { signal } = this.unlockController;
            this.wave.addEventListener('loadedmetadata', finalize, {
                once: true, signal
            });
            this.wave.addEventListener('error', finalize, {
                once: true, signal
            });
            signal.addEventListener('abort', finalize, { once: true });
            this.wave.load();
        });
    }
    async playAmbient() {
        if (this.disposed || this.muted || this.paused || !this.ambient.paused) return;
        await this.ambient.play().catch(()=>undefined);
    }
    ensureProcedural(context) {
        if (this.proceduralReady) return this.proceduralReady;
        this.proceduralReady = this.createProcedural(context).catch((error)=>{
            console.warn('[Sandboard audio] Procedural drawing sound unavailable.', error);
        });
        return this.proceduralReady;
    }
    async createProcedural(context) {
        if (this.disposed || this.sandNode) return;
        const blob = new Blob([
            sandWorkletSource
        ], {
            type: 'text/javascript'
        });
        const url = URL.createObjectURL(blob);
        try {
            await context.audioWorklet.addModule(url);
        } finally{
            URL.revokeObjectURL(url);
        }
        if (this.disposed || context !== this.context) return;
        const sandNode = new AudioWorkletNode(context, 'sand-processor', {
            numberOfInputs: 0,
            numberOfOutputs: 1,
            outputChannelCount: [
                2
            ]
        });
        const highpass = new BiquadFilterNode(context, {
            type: 'highpass',
            frequency: 90,
            Q: 0.7
        });
        const presence = new BiquadFilterNode(context, {
            type: 'peaking',
            frequency: 2200,
            Q: 0.75,
            gain: -4.8
        });
        const soften = new BiquadFilterNode(context, {
            type: 'lowpass',
            frequency: 4800,
            Q: 0.42
        });
        const compressor = new DynamicsCompressorNode(context, {
            threshold: -18,
            knee: 16,
            ratio: 2.2,
            attack: 0.004,
            release: 0.09
        });
        const master = new GainNode(context, {
            gain: this.muted ? 0 : proceduralVolume
        });
        sandNode.connect(highpass).connect(presence).connect(soften).connect(compressor).connect(master).connect(context.destination);
        this.sandNode = sandNode;
        this.proceduralGain = master;
    }
    sendGestureState(now = performance.now()) {
        if (!this.sandNode) return;
        if (!this.gestures.size) {
            this.sandNode.port.postMessage({
                type: 'state',
                gate: 0,
                speed: 0,
                pressure: 0,
                turn: 0
            });
            return;
        }
        let strongest;
        let strongestEnergy = -1;
        for (const track of this.gestures.values()){
            if (track.audibleUntil < now) continue;
            const energy = track.speed * (0.92 + track.pressure * 0.08);
            if (energy > strongestEnergy) {
                strongest = track;
                strongestEnergy = energy;
            }
        }
        if (!strongest) {
            this.sandNode.port.postMessage({
                type: 'state',
                gate: 0,
                speed: 0,
                pressure: 0,
                turn: 0
            });
            return;
        }
        this.sandNode.port.postMessage({
            type: 'state',
            gate: 1,
            speed: strongest.speed,
            pressure: strongest.pressure,
            turn: strongest.turn
        });
    }
}
