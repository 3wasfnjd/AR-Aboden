import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PlacementLock, intersectHorizontal, supportedSurface } from './placement.js';
const origin={x:0,y:1.6,z:0},direction={x:0,y:-.8,z:-.6};
function patch(y){return [-.18,0,.18].flatMap(x=>[-.18,0,.18].map(dz=>({position:{x,y,z:-.6+dz},confidence:1})));}
function steady(p){for(let t=0;t<=1200;t+=100){p.observe(t,'NORMAL',origin);p.sample({position:{x:0,y:0,z:-1.2},kind:'estimated-floor'},t);}}

test('ground intersection is in front and below the camera',()=>{
  const p=intersectHorizontal(origin,direction,0);assert.ok(Math.abs(p.z+1.2)<1e-9);assert.equal(p.y,0);
});
test('horizontal, upward and invalid rays cannot place',()=>{
  assert.equal(intersectHorizontal(origin,{x:0,y:0,z:-1},0),null);
  assert.equal(intersectHorizontal(origin,{x:0,y:.5,z:-.8},0),null);
  assert.equal(intersectHorizontal({x:NaN,y:1,z:0},direction,0),null);
  assert.equal(intersectHorizontal(origin,direction,-8),null);
});
test('horizontal feature patch supports a raised tabletop',()=>{
  const result=supportedSurface(origin,direction,[{position:{x:0,y:.8,z:-.6}}],patch(.8));
  assert.equal(result?.kind,'supported');assert.equal(result.support,9);assert.ok(Math.abs(result.position.y-.8)<1e-9);
});
test('a single point does not establish a tabletop',()=>{
  assert.equal(supportedSurface(origin,direction,[{position:{x:0,y:.8,z:-.6}}],patch(.8).slice(0,1)),null);
});
test('collinear wall edge cannot be treated as a table',()=>{
  const line=Array.from({length:9},(_,i)=>({x:(i-4)*.04,y:.8,z:-.6}));
  assert.equal(supportedSurface(origin,direction,[line[4]],line),null);
});
test('sloping surface is rejected',()=>{
  const pts=patch(.8).map(o=>({position:{...o.position,y:.8+o.position.x*.6}}));
  assert.equal(supportedSurface(origin,direction,[{x:0,y:.8,z:-.6}],pts),null);
});
test('lock needs tracked pose and stable repeated samples',()=>{
  const p=new PlacementLock();assert.equal(p.lock(0),null);steady(p);assert.equal(p.ready,true);assert.ok(p.lock(1200));
});
test('moving camera cannot move an already locked anchor',()=>{
  const p=new PlacementLock();steady(p);const anchor=p.lock(1200);
  for(let t=1300;t<=1800;t+=100){p.observe(t,'NORMAL',{...origin,x:.03*(t-1200)/100});p.sample({position:{x:3,y:2,z:1},kind:'supported'},t);}
  assert.equal(p.anchor,anchor);assert.equal(p.anchor.x,0);assert.ok(Object.isFrozen(p.anchor));
});
test('lost tracking preserves anchor but prevents interaction readiness',()=>{
  const p=new PlacementLock();steady(p);const a=p.lock(1200);p.observe(1300,'LIMITED',origin);
  assert.equal(p.anchor,a);assert.equal(p.trackingReady(1300),false);
});
test('stale data and explicit relocation block placement',()=>{
  const p=new PlacementLock();steady(p);assert.equal(p.lock(1600),null);steady(p);p.lock(1200);p.relocate();assert.equal(p.anchor,null);assert.equal(p.lock(1200),null);
});
test('camera discontinuity invalidates an unlocked candidate',()=>{
  const p=new PlacementLock();steady(p);p.observe(1300,'NORMAL',{...origin,x:1});assert.equal(p.ready,false);assert.equal(p.lock(1300),null);
});
test('static integration contract: hidden route, pinned water source, local optics, bounded time',()=>{
  const html=readFileSync(new URL('./index.html',import.meta.url),'utf8');
  const pool=readFileSync(new URL('./pool.js',import.meta.url),'utf8');
  const app=readFileSync(new URL('./app.js',import.meta.url),'utf8');
  assert.match(html,/noindex,nofollow/);assert.match(pool,/d1cb23dcce6ea8ee4a60f6159daeb79d4b511dba/);
  assert.match(pool,/poolInverse \* worldPosition/);assert.match(pool,/applyMatrix4\(inverse\)/);
  assert.match(app,/localRay.copy\(raycaster.ray\).applyMatrix4\(inverse\)/);
  assert.match(pool,/substeps\+\+<6/);assert.match(pool,/drops.length>=24/);
  assert.match(app,/scene.background=null/);assert.match(app,/name:'aboden-water-ar-lab'/);
});
