import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source=await readFile(new URL('../js/ar/ArenaAutopilot.js',import.meta.url),'utf8');
const {ArenaAutopilot}=await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const randomFor=seed=>()=>((seed=(Math.imul(seed,1664525)+1013904223)>>>0)/4294967296);
const make=(options={})=>new ArenaAutopilot({center:{x:4,z:-3},roadY:.035,random:randomFor(123),...options});

for(const scale of [.6,1,1.4]) for(const fps of [15,30,60]) {
  test(`five-minute show at scale ${scale}, ${fps} fps stays clear of walls`,()=>{
    const a=make({scale,carRadius:.22});
    const states=new Set();let smokeFrames=0,distance=0;
    for(let i=0;i<fps*300;i++) {
      const p=a.update(1/fps);states.add(p.state);
      const radius=Math.hypot(p.x-4,p.z+3);
      assert.ok(radius+.22*scale <= 1.2*scale+1e-9);
      assert.equal(p.y,.035);
      for(const key of ['x','z','heading','speed','driftIntensity']) assert.ok(Number.isFinite(p[key]));
      if(p.driftIntensity>.7) smokeFrames++;
      distance+=p.speed/fps;
    }
    assert.ok(distance>50*scale,'car must keep moving');
    for(const state of ['DRIFTING','DONUT','CRUISING']) assert.ok(states.has(state),state);
    assert.ok(smokeFrames>fps*30,'sustained drift, not only cruising');
    assert.equal(a.boundaryCorrections,0,'normal movement must not rely on visible boundary snaps');
  });
}

test('scale and translation preserve choreography',()=>{
  const a=make(),b=make({center:{x:-6,z:8},scale:.6,roadY:.4});
  for(let i=0;i<6000;i++) {
    const p=a.update(1/60),q=b.update(1/60);
    assert.ok(Math.abs((p.x-4)*.6-(q.x+6))<1e-8);
    assert.ok(Math.abs((p.z+3)*.6-(q.z-8))<1e-8);
    assert.equal(q.y,.4);
  }
});

test('large timesteps and externally displaced poses remain contained',()=>{
  const a=make();a.x=a.limit*1.2;a.vx=4;
  const p=a.update(2);
  assert.ok(Math.hypot(p.x-4,p.z+3)<=a.limit+1e-9);
  assert.ok(a.boundaryCorrections>0);
  assert.equal(a.state,'AVOIDANCE');
  const time=a.time,pose=a.update(0);
  assert.equal(a.time,time);assert.equal(pose.x,p.x);assert.equal(pose.z,p.z);
});

test('actual arena frame loop pauses before placement, on tracking loss and in background',async()=>{
  const html=await readFile(new URL('../arena.html',import.meta.url),'utf8');
  const start=html.indexOf('    function tickWorld(');
  const end=html.indexOf("    document.addEventListener('visibilitychange'",start);
  const a=make();let visibleUpdates=0,effectUpdates=0;
  const context=vm.createContext({sceneReady:true,camera:{},
    vehicle:{updateAutonomous(){visibleUpdates++;}},lastTick:0,
    updatePlacement(){},placed:false,document:{hidden:false},
    placement:{trackingReady:()=>context.tracked},tracked:true,drivingEnabled:false,
    setStatus(){},diagnostics:null,autopilot:a,
    smokeTrails:{update(){effectUpdates++;}},driftMarks:{update(){effectUpdates++;}}
  });
  vm.runInContext(html.slice(start,end),context);
  vm.runInContext('tickWorld(16)',context);assert.equal(a.time,0);
  context.placed=true;vm.runInContext('tickWorld(32)',context);
  assert.ok(a.time>0);const time=a.time;
  context.tracked=false;vm.runInContext('tickWorld(1000)',context);assert.equal(a.time,time);
  context.tracked=true;context.document.hidden=true;
  vm.runInContext('tickWorld(2000)',context);assert.equal(a.time,time);
  context.document.hidden=false;vm.runInContext('tickWorld(2016)',context);
  assert.ok(a.time-time<.02);assert.equal(visibleUpdates,2);assert.equal(effectUpdates,4);
  assert.ok(!html.includes('MobileControls'));
  assert.ok(!html.includes('id="steerZone"'));
  assert.ok(!html.includes('id="handbrakeBtn"'));
});

test('vehicle pose adapter follows the show and animates wheels independent of frame rate',async()=>{
  const code=await readFile(new URL('../js/Vehicle.js',import.meta.url),'utf8');
  const start=code.indexOf('  updateAutonomous('),end=code.indexOf('  update(dt, input',start);
  const adapter=vm.runInNewContext('({'+code.slice(start,end)+'})').updateAutonomous;
  const vector=()=>({set(x,y,z){Object.assign(this,{x,y,z});return this;},copy(p){return this.set(p.x,p.y,p.z);}});
  const vehicle=()=>({container:{position:vector(),rotation:vector(),scale:{x:.6}},
    spherePos:vector(),sphereVel:vector(),modelVelocity:vector(),prevModelPos:vector(),
    sphereRadius:.04,wheels:[{rotation:{x:0}}],_animateVisuals(){this.wheels[0].rotation.x+=123;}});
  const pose={x:3,y:.2,z:2,heading:1,vx:.3,vz:.2,speed:.4,steer:.5,handbrake:true,driftIntensity:1.1};
  const a=vehicle(),b=vehicle();
  for(let i=0;i<30;i++) adapter.call(a,pose,1/30);
  for(let i=0;i<60;i++) adapter.call(b,pose,1/60);
  assert.ok(Math.abs(a.wheels[0].rotation.x-b.wheels[0].rotation.x)<1e-9);
  assert.equal(a.container.position.y,.2);assert.equal(a.container.rotation.y,1);
  assert.equal(a.driftIntensity,1.1);assert.equal(a.modelVelocity.x,.3);
});
