import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const moduleFromSource = source => import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const { GroundPlacement, groundPatch } = await moduleFromSource(await readFile(new URL('../js/ar/GroundPlacement.js', import.meta.url), 'utf8'));
const aim = {x:0,y:0,z:-1};
const camera = {x:0,y:1.5,z:0};
const rotation = {x:0,y:0,z:0,w:1};
const points = (center=aim, height=.015) => [-.2,0,.2].flatMap(x=>[-.2,0,.2].map(z=>({position:{x:center.x+x,y:height,z:center.z+z},confidence:1})));
function observe(p, now, status='NORMAL', position=camera) {
  p.observe({now,status,position,rotation});
}
function settle(p, end=2000) {
  for(let now=0;now<=end;now+=100){
    observe(p,now);
    p.sample(aim,points(),now);
  }
}

test('distributed ground evidence estimates height; unsupported surfaces fail',()=>{
  assert.ok(Math.abs(groundPatch(aim,points()).position.y-.015)<1e-10);
  assert.equal(groundPatch(aim,[]),null);
  assert.equal(groundPatch(aim,points().slice(0,5)),null);
  assert.equal(groundPatch(aim,points(aim,.7)),null); // tabletop
  assert.equal(groundPatch(aim,points().map(p=>({...p,confidence:0}))),null);
  assert.equal(groundPatch(aim,Array.from({length:9},(_,i)=>({x:i*.04,y:0,z:-1}))),null); // wall edge
  assert.equal(groundPatch(aim,points().map(p=>({x:p.position.x,y:p.position.x*.3,z:p.position.z}))),null); // slope
});

test('rejects a noisy/nonplanar patch, accepts small measurement noise',()=>{
  const rough=points().map((p,i)=>({x:p.position.x,y:i%2?.023:-.023,z:p.position.z}));
  assert.equal(groundPatch(aim,rough),null);
  const fine=points().map((p,i)=>({x:p.position.x,y:i%2?.003:-.003,z:p.position.z}));
  assert.ok(groundPatch(aim,fine));
});

test('requires sustained tracking and a full stability window before locking',()=>{
  const p=new GroundPlacement();
  settle(p,1700);
  assert.equal(p.ready,false);
  assert.equal(p.lock(1700),null);
  observe(p,1800);p.sample(aim,points(),1800);
  assert.equal(p.ready,true);
  const anchor=p.lock(1800);
  assert.ok(anchor);
  assert.ok(Math.abs(anchor.y-.015)<1e-10);
  assert.ok(Object.isFrozen(anchor));
});

for(const fps of [30,60]) test(`continuous slow movement is never accepted at ${fps} fps`,()=>{
  const p=new GroundPlacement();
  let nextSample=0;
  for(let frame=0;frame<fps*6;frame++){
    const now=frame*1000/fps;
    observe(p,now);
    const moving={x:now*.00012,y:0,z:-1}; // 12 cm/s; per-frame delta passed the old test
    if(now>=nextSample){p.sample(moving,points(moving),now);nextSample=now+100;}
    assert.equal(p.ready,false);
  }
});

test('small jitter settles; isolated outlier cancels readiness',()=>{
  const p=new GroundPlacement();
  for(let now=0;now<=2000;now+=100){
    observe(p,now);
    const candidate={x:now%200?.004:-.004,y:0,z:-1};
    p.sample(candidate,points(),now);
  }
  assert.equal(p.ready,true);
  observe(p,2100);
  p.sample({...aim,x:.2},points(),2100);
  assert.equal(p.ready,false);
});

test('tracking loss, large pose jump, and stale samples prevent placement',()=>{
  const p=new GroundPlacement();settle(p);
  assert.equal(p.lock(2300),null);
  observe(p,2100,'LIMITED');
  assert.equal(p.ready,false);
  assert.equal(p.candidate,null);
  observe(p,2200);p.sample(aim,points(),2200);
  assert.equal(p.ready,false);
  p.reset();settle(p);
  observe(p,2100,'NORMAL',{...camera,x:.5});
  assert.equal(p.trackingReady(2100),false);
  assert.equal(p.lock(2100),null);
});

test('sample outage restarts stability even while tracking remains normal',()=>{
  const p=new GroundPlacement();settle(p);
  for(let now=2100;now<=2400;now+=100) observe(p,now);
  assert.equal(p.lock(2400),null);
  p.sample(aim,points(),2400);
  assert.equal(p.ready,false);
});

test('locked world position survives tracking loss/recovery and resets only explicitly',()=>{
  const p=new GroundPlacement();settle(p);
  const anchor=p.lock(2000);
  const original={...anchor};
  observe(p,2100,'LIMITED');
  assert.equal(p.trackingReady(2100),false);
  for(let now=2200;now<=3100;now+=100){
    observe(p,now,'NORMAL',{...camera,x:.5});
    p.sample({...aim,x:.5},points(),now);
  }
  assert.equal(p.trackingReady(3100),true);
  assert.deepEqual(p.anchor,original);
  p.reset();assert.equal(p.anchor,null);assert.equal(p.ready,false);
});

test('physics places floor and walls at the selected height, including after movement',async()=>{
  const source=await readFile(new URL('../js/Physics.js',import.meta.url),'utf8');
  // Exercise the actual coordinate calculations with only the external physics API stubbed.
  const fake=`const MotionType={STATIC:0}; const box={create:o=>o};
    const rigidBody={create:(world,o)=>({...o}),setPosition:(world,body,p)=>{body.position=p;}};`;
  const physics=await moduleFromSource(source.replace(/import\s*\{[\s\S]*?\}\s*from 'crashcat';/,fake));
  for(const height of [0,.047,-.025]){
    const arena=physics.createArenaPhysics({_OL_STATIC:0},1,2,{floorY:height});
    assert.equal(arena.floor.position[1],height-.025);
    assert.ok(arena.walls.every(w=>w.position[1]===height+arena.wallHeight*.5));
    physics.moveArenaPhysics(arena,3,4);
    assert.deepEqual(arena.floor.position,[3,height-.025,4]);
    assert.ok(arena.walls.every(w=>w.position[1]===height+arena.wallHeight*.5));
  }
  assert.equal(physics.createArenaPhysics({_OL_STATIC:0}).floor.position[1],-.025);
});
