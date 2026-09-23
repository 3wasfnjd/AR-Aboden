// SPDX-License-Identifier: GPL-3.0-only
// AR-Aboden integration of the upstream sand engine. See NOTICE.md.
import { SAND } from './vendor/config.js';
import { StrokeQueue } from './vendor/input/strokes.js';
import { SandRenderer } from './vendor/render/renderer.js';
import { SandSolver } from './vendor/simulation/solver.js';
import { FixedClock } from './vendor/simulation/clock.js';
import { WaveResetEffect, idleWaveResetState } from './vendor/reset/effect.js';
import { waveResetViewport } from './vendor/reset/viewport.js';
import { SandSound } from './audio/sound.js';

export async function start() {
  const $ = id => document.getElementById(id);
  const canvas = $('sand');
  const controls = $('tool-controls');
  const strokes = new StrokeQueue();
  const clock = new FixedClock(SAND.step, SAND.maxSteps);
  const listeners = new AbortController();
  const pointers = new Map();
  const mobile = matchMedia('(pointer: coarse)').matches;
  let wave = new WaveResetEffect();
  let waveState = idleWaveResetState();
  let device, context, renderer, solver, observer, sound;
  let ready = false, stopped = false, frameId = 0;
  let keyboardDrawing = false, keyboardCursor = false;
  let elapsed = 0, waveTime = 0, previousTime;
  const keyboardId = -1;

  function cancelInput() {
    const captured = [...pointers.keys()];
    pointers.clear();
    for (const id of captured) if (canvas.hasPointerCapture(id)) canvas.releasePointerCapture(id);
    strokes.cancel();
    sound?.cancelAll();
    keyboardDrawing = false;
    keyboardCursor = false;
  }

  function dispose() {
    if (stopped) return;
    stopped = true;
    ready = false;
    cancelAnimationFrame(frameId);
    cancelInput();
    listeners.abort();
    observer?.disconnect();
    sound?.dispose();
    renderer?.dispose();
    solver?.dispose();
    context?.unconfigure();
    device?.destroy();
  }

  function fail(title, message, error) {
    if (error) console.error('Sand experience:', error);
    $('startup').hidden = false;
    $('spinner').hidden = true;
    $('startup-title').textContent = title;
    $('startup-message').textContent = message;
    $('retry').hidden = false;
    $('state').textContent = 'غير متاحة الآن';
    controls.disabled = true;
    canvas.dataset.state = 'error';
    dispose();
  }

  const on = (target, name, handler, options = {}) =>
    target.addEventListener(name, handler, { ...options, signal: listeners.signal });

  try {
    if (!isSecureContext || !navigator.gpu) {
      fail('متصفحك لا يدعم هذه التجربة', 'تحتاج الكتابة على الرمل إلى WebGPU. افتح الرابط في متصفح محدّث يدعمها، مثل Safari أو Chrome على جهاز متوافق.');
      return;
    }
    const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!adapter) {
      fail('الرسم ثلاثي الأبعاد غير متاح', 'لم يتمكّن المتصفح من تشغيل محاكاة الرمل على هذا الجهاز. جرّب متصفحًا محدّثًا أو جهازًا آخر.');
      return;
    }
    device = await adapter.requestDevice({ label: 'Aboden sand' });
    device.lost.then(info => {
      if (!stopped) fail('توقّفت تجربة الرمل', 'أعد تشغيل التجربة لاستعادة الرسم.', info.message);
    });
    on(device, 'uncapturederror', event => {
      event.preventDefault();
      if (!stopped) fail('تعذّر إكمال الرسم', 'أعد تحميل الصفحة لتشغيل التجربة من جديد.', event.error);
    });
    context = canvas.getContext('webgpu');
    if (!context) throw new Error('WebGPU canvas unavailable');
    const format = navigator.gpu.getPreferredCanvasFormat();
    context.configure({ device, format, alphaMode: 'opaque' });
    solver = new SandSolver(device, mobile ? 384 : SAND.resolution);
    renderer = new SandRenderer(device, solver, format, mobile,
      new URL('../../assets/sand/coconut_tree.glb', import.meta.url).href);
    sound = new SandSound();
    sound.setPaused(document.hidden);
    const soundReady = sound.prepare().catch(error => {
      console.warn('Sand audio unavailable:', error);
      sound?.dispose();
      sound = undefined;
      $('sound').disabled = true;
      $('sound').title = 'الصوت غير متاح في هذا المتصفح';
      $('sound').setAttribute('aria-label', 'الصوت غير متاح في هذا المتصفح');
    });
    await solver.initialize();
    await renderer.initialize();
    await soundReady;
    if (stopped) return;

    function resize() {
      if (stopped) return;
      const rect = canvas.getBoundingClientRect();
      // Bound pixel work and GPU memory independently of the phone's native DPR.
      const pixelBudget = mobile ? 1100000 : 2200000;
      const ratio = Math.min(devicePixelRatio || 1, mobile ? 1.5 : 2,
        Math.sqrt(pixelBudget / Math.max(1, rect.width * rect.height)),
        device.limits.maxTextureDimension2D / Math.max(1, rect.width, rect.height));
      const width = Math.max(1, Math.round(rect.width * ratio));
      const height = Math.max(1, Math.round(rect.height * ratio));
      if (canvas.width === width && canvas.height === height && ready) return;
      cancelInput();
      canvas.width = width;
      canvas.height = height;
      renderer.resize(width, height);
      // A rotation preserves the drawing. A running wave finishes clearing the
      // full bed even when its visible viewport changes.
    }
    resize();
    observer = new ResizeObserver(resize);
    observer.observe(canvas);

    function updateBrush() {
      strokes.radius = Number($('brush').value) / 1000;
      const value = Number($('brush').value);
      const label = value < 7 ? 'رفيع' : value > 11 ? 'عريض' : 'متوسط';
      $('brush-value').textContent = label;
      $('brush').setAttribute('aria-valuetext', label);
    }
    updateBrush();
    on($('brush'), 'input', updateBrush);

    const pointFor = event => {
      const rect = canvas.getBoundingClientRect();
      return renderer.camera.screenToBed(event.clientX - rect.left, event.clientY - rect.top, rect.width, rect.height);
    };
    const pressureFor = event => event.pointerType === 'pen' ? Math.max(0.1, event.pressure) : 0.75;
    const timeFor = event => event.timeStamp > performance.timeOrigin ? event.timeStamp - performance.timeOrigin : event.timeStamp;
    const stale = event => {
      const started = pointers.get(event.pointerId);
      return started !== undefined && timeFor(event) > 0 && timeFor(event) < started;
    };
    const markUsed = () => $('hint').classList.add('used');

    on(canvas, 'pointerdown', event => {
      if (!ready || waveState.active || pointers.has(event.pointerId)) return;
      if (event.pointerType === 'mouse' && event.button !== 0) return;
      event.preventDefault();
      const now = timeFor(event) || performance.now();
      pointers.set(event.pointerId, now);
      canvas.setPointerCapture(event.pointerId);
      canvas.focus({ preventScroll: true });
      strokes.begin(pointFor(event), pressureFor(event), now, event.pointerId);
      sound?.beginPointer(event);
      // Give a stationary touch a tiny contact segment so Arabic dots and taps
      // leave a mark, even when there is no pointermove between down and up.
      const point = pointFor(event);
      strokes.move({ x: point.x + SAND.extent / solver.resolution * 0.1, y: point.y }, pressureFor(event), now + 1, event.pointerId);
      keyboardCursor = false;
      markUsed();
    }, { passive: false });

    on(canvas, 'pointermove', event => {
      if (!ready || waveState.active || !pointers.has(event.pointerId) || stale(event)) return;
      event.preventDefault();
      const samples = event.getCoalescedEvents?.();
      for (const sample of samples?.length ? samples : [event]) {
        if (!stale(sample)) {
          strokes.move(pointFor(sample), pressureFor(sample), timeFor(sample), event.pointerId);
          sound?.movePointer(sample, event.pointerId);
        }
      }
    }, { passive: false });

    on(canvas, 'pointerup', event => {
      if (!pointers.has(event.pointerId) || stale(event)) return;
      strokes.move(pointFor(event), pressureFor(event), timeFor(event), event.pointerId);
      strokes.end(event.pointerId);
      sound?.endPointer(event.pointerId);
      pointers.delete(event.pointerId);
      if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    });
    const cancelPointer = event => {
      if (stale(event) || !pointers.has(event.pointerId)) return;
      pointers.delete(event.pointerId);
      strokes.cancel(event.pointerId);
      sound?.endPointer(event.pointerId);
      if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    };
    on(canvas, 'pointercancel', cancelPointer);
    on(canvas, 'lostpointercapture', cancelPointer);
    on(canvas, 'contextmenu', event => event.preventDefault());
    on(window, 'blur', cancelInput);

    on(canvas, 'keydown', event => {
      if (!ready || waveState.active) return;
      if (event.code === 'Space') {
        event.preventDefault();
        if (!keyboardDrawing) {
          strokes.begin(strokes.position, 0.75, timeFor(event), keyboardId);
          keyboardDrawing = true;
          markUsed();
        }
      }
      const direction = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[event.key];
      if (direction) {
        event.preventDefault();
        keyboardCursor = true;
        strokes.move({ x: strokes.position.x + direction[0] * 0.003, y: strokes.position.y + direction[1] * 0.003 }, 0.75, timeFor(event), keyboardId);
      }
    });
    on(canvas, 'keyup', event => {
      if (event.code === 'Space') {
        event.preventDefault();
        strokes.end(keyboardId);
        keyboardDrawing = false;
      }
    });
    on(canvas, 'blur', cancelInput);

    on($('sound'), 'click', () => {
      if (!sound) return;
      sound.setMuted(!sound.muted);
      $('sound').setAttribute('aria-pressed', String(!sound.muted));
      const label = sound.muted ? 'تشغيل الصوت' : 'كتم الصوت';
      $('sound').setAttribute('aria-label', label);
      $('sound').title = label;
    });

    function washing(active) {
      $('wash').disabled = active;
      $('brush').disabled = active;
      $('wash-label').textContent = active ? 'الموجة تمسح…' : 'امسح بموجة';
      $('feedback').textContent = active ? 'انتظر عودة الموجة لتبدأ رسمًا جديدًا' : 'ارسم بحرية • لا تحتاج إلى الكاميرا';
    }
    on($('wash'), 'click', () => {
      if (!ready || waveState.active) return;
      cancelInput();
      wave.start(waveTime, sound?.playResetWave(), waveResetViewport(renderer.camera));
      waveState = wave.update(waveTime);
      washing(true);
      markUsed();
    });
    on($('clear'), 'click', () => {
      if (!ready) return;
      cancelInput();
      sound?.stopResetWave();
      wave = new WaveResetEffect();
      waveState = idleWaveResetState();
      solver.reset();
      const encoder = device.createCommandEncoder();
      solver.clearTransientState(encoder);
      device.queue.submit([encoder.finish()]);
      washing(false);
      $('feedback').textContent = 'الرمل جاهز لرسم جديد';
    });

    function frame(now) {
      if (!ready || stopped || document.hidden) return;
      try {
        const rawDelta = previousTime === undefined ? 0 : Math.max(0, now - previousTime);
        const delta = Math.min(50, rawDelta);
        previousTime = now;
        elapsed += delta;
        // The audio clip uses real time: do not slow its wave at low frame rates.
        // Visibility changes reset previousTime and pause both media elements.
        waveTime += rawDelta;
        sound?.update(now);
        const steps = clock.advance(elapsed);
        const encoder = device.createCommandEncoder({ label: 'Aboden sand frame' });
        // Preserve justStarted until the frame consumes it.
        if (!waveState.justStarted) waveState = wave.update(waveTime);
        if (waveState.justStarted) solver.clearTransientState(encoder);
        if (waveState.erase) solver.encodeWaveReset(encoder, waveState);
        if (!waveState.active && !waveState.justFinished && steps) {
          solver.encode(encoder, Array.from({ length: steps }, () => strokes.nextBatch()));
        }
        renderer.encode(encoder, context.getCurrentTexture().createView(), strokes.cursor,
          elapsed, !waveState.active && (pointers.size > 0 || keyboardCursor || keyboardDrawing), waveState);
        device.queue.submit([encoder.finish()]);
        if (waveState.justFinished) washing(false);
        if (waveState.justStarted) waveState = { ...waveState, justStarted: false };
        frameId = requestAnimationFrame(frame);
      } catch (error) {
        fail('توقّفت تجربة الرمل', 'أعد تحميل الصفحة لتشغيل التجربة من جديد.', error);
      }
    }

    on(document, 'visibilitychange', () => {
      cancelInput();
      sound?.setPaused(document.hidden);
      cancelAnimationFrame(frameId);
      previousTime = undefined;
      clock.reset(elapsed);
      if (!document.hidden && ready && !stopped) frameId = requestAnimationFrame(frame);
    });
    // Keep state for browser back/forward cache, but free GPU resources when
    // this page is actually unloaded.
    on(window, 'pagehide', event => {
      if (!event.persisted) dispose();
      else { cancelInput(); sound?.setPaused(true); cancelAnimationFrame(frameId); previousTime = undefined; }
    });
    on(window, 'pageshow', event => {
      if (event.persisted && ready && !stopped) {
        sound?.setPaused(document.hidden);
        cancelAnimationFrame(frameId);
        previousTime = undefined;
        clock.reset(elapsed);
        frameId = requestAnimationFrame(frame);
      }
    });

    ready = true;
    canvas.dataset.state = 'ready';
    controls.disabled = false;
    $('startup').hidden = true;
    $('state').textContent = 'جاهزة للرسم';
    frameId = requestAnimationFrame(frame);
  } catch (error) {
    if (!stopped) fail('تعذّر تشغيل تجربة الرمل', 'تحقّق من اتصالك، وأغلق الصفحات الثقيلة ثم أعد المحاولة. يلزم متصفح وجهاز يدعمان WebGPU.', error);
  }
}
