import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir, access } from 'node:fs/promises';
import { StrokeQueue } from '../js/sand/vendor/input/strokes.js';
import { SandCamera } from '../js/sand/vendor/render/camera.js';
import { FixedClock } from '../js/sand/vendor/simulation/clock.js';
import { WaveResetEffect } from '../js/sand/vendor/reset/effect.js';
import { waveResetViewport } from '../js/sand/vendor/reset/viewport.js';

test('browser modules resolve locally without TypeScript or a build server', async () => {
  const visit = async dir => {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const url = new URL(entry.name + (entry.isDirectory() ? '/' : ''), dir);
      if (entry.isDirectory()) { await visit(url); continue; }
      if (!entry.name.endsWith('.js')) continue;
      const source = await readFile(url, 'utf8');
      for (const [, specifier] of source.matchAll(/from ['"]([^'"]+)['"]/g)) {
        assert.match(specifier, /^\.\.?\/.*\.js$/);
        await access(new URL(specifier, url));
      }
    }
  };
  await visit(new URL('../js/sand/', import.meta.url));
});

test('portrait and landscape pointer coordinates stay finite and centered', () => {
  const camera = new SandCamera();
  for (const [width, height] of [[360, 600], [844, 260], [1280, 650]]) {
    camera.aspect = width / height;
    const center = camera.screenToBed(width / 2, height / 2, width, height);
    assert.ok(Math.abs(center.x) < 1e-9 && Math.abs(center.y) < 1e-9);
    for (const [x, y] of [[0, 0], [width, 0], [width, height], [0, height]]) {
      const point = camera.screenToBed(x, y, width, height);
      assert.ok(Number.isFinite(point.x) && Number.isFinite(point.y));
      assert.ok(Math.abs(point.x) < 0.4 && Math.abs(point.y) < 0.4);
    }
  }
});

test('two fingers stay separate and cancelling one does not bridge their paths', () => {
  const q = new StrokeQueue();
  q.begin({ x: -0.1, y: 0 }, 0.75, 0, 1);
  q.begin({ x: 0.1, y: 0 }, 0.75, 0, 2);
  q.move({ x: -0.1, y: 0.04 }, 0.75, 40, 1);
  q.move({ x: 0.1, y: 0.04 }, 0.75, 40, 2);
  q.cancel(1);
  q.end(2);
  const result = q.nextBatch();
  assert.ok(result.length > 0);
  for (const s of result) {
    assert.equal(s.from.x, 0.1);
    assert.equal(s.to.x, 0.1);
  }
  q.cancel();
  assert.deepEqual(q.nextBatch(), []);
});

test('equal-time touch samples do not produce unbounded impact velocities', () => {
  const q = new StrokeQueue();
  q.begin({ x: 0, y: 0 }, 0.7, 100, 3);
  q.move({ x: 0.025, y: 0 }, 0.7, 100, 3);
  q.end(3);
  const strokes = q.nextBatch();
  assert.ok(strokes.length > 0);
  for (const s of strokes) assert.ok(Number.isFinite(s.velocity.x) && Math.abs(s.velocity.x) < 10);
});

test('background pause resets simulation clock without replaying elapsed time', () => {
  const clock = new FixedClock(1 / 120, 4);
  assert.equal(clock.advance(0), 0);
  assert.equal(clock.advance(1000 / 60), 2);
  clock.reset(30000);
  assert.equal(clock.advance(30000), 0);
  assert.equal(clock.advance(30000 + 1000 / 60), 2);
});

test('wave reset crosses the entire bed and ends for both screen orientations', () => {
  for (const aspect of [0.6, 3.2]) {
    const camera = new SandCamera();
    camera.aspect = aspect;
    const effect = new WaveResetEffect();
    effect.start(0, 4.754, waveResetViewport(camera));
    let front = Infinity, erase = false, finished = false;
    for (let time = 0; time <= 4800; time += 16) {
      const state = effect.update(time);
      if (state.erase) {
        assert.ok(state.eraseCurrentBaseFront <= front);
        front = state.eraseCurrentBaseFront;
        erase = true;
      }
      if (state.justFinished) finished = true;
    }
    assert.ok(erase && finished);
    assert.ok(front <= -0.5 + 1e-8);
    assert.equal(effect.update(5000).active, false);
  }
});
