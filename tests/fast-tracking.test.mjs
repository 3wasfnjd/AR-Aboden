import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const source=await readFile(new URL('../js/ar/FastTrackingGate.js',import.meta.url),'utf8');
const {FastTrackingGate}=await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const position={x:0,y:1.5,z:0};
const observe=(gate,now,status='NORMAL',point=position)=>gate.observe({now,status,position:point});

for(const fps of [15,30,60,120])test(`estimated placement is ready on the second tracked frame at ${fps} fps`,()=>{
  const gate=new FastTrackingGate();
  assert.equal(gate.ready(0),false);
  observe(gate,0);assert.equal(gate.ready(0),false);
  observe(gate,1000/fps);assert.equal(gate.ready(1000/fps),true);
});

test('ordinary tracked motion does not restart a stillness timer',()=>{
  const gate=new FastTrackingGate();
  observe(gate,0);
  for(let i=1;i<300;i++){
    observe(gate,i*16,'NORMAL',{x:i*.04,y:1.5+Math.sin(i)*.01,z:i*.015});
    assert.equal(gate.ready(i*16),true);
  }
});

test('limited, absent, and invalid poses never place; recovery needs two fresh frames',()=>{
  for(const [status,point] of [['LIMITED',position],[undefined,position],['NORMAL',undefined],
    ['NORMAL',{x:NaN,y:1,z:0}],['NORMAL',{x:0,y:Infinity,z:0}],['NORMAL',{x:0,z:0}]]){
    const gate=new FastTrackingGate();observe(gate,0);observe(gate,16);
    gate.observe({now:32,status,position:point});assert.equal(gate.ready(32),false);
    observe(gate,48);assert.equal(gate.ready(48),false);
    observe(gate,64);assert.equal(gate.ready(64),true);
  }
});

test('stale data, duplicate/reversed timestamps, and reset cannot bypass the gate',()=>{
  const gate=new FastTrackingGate();observe(gate,0);observe(gate,16);
  assert.equal(gate.ready(266),true);assert.equal(gate.ready(267),false);
  observe(gate,300);assert.equal(gate.ready(300),false);
  observe(gate,300);assert.equal(gate.ready(300),false);
  observe(gate,316);assert.equal(gate.ready(316),true);
  assert.equal(gate.ready(315),false);
  observe(gate,200);assert.equal(gate.ready(200),false);
  observe(gate,216);assert.equal(gate.ready(216),true);
  observe(gate,NaN);assert.equal(gate.ready(250),false);
  observe(gate,300);observe(gate,316);gate.reset();assert.equal(gate.ready(316),false);
});

const page=await readFile(new URL('../operation-ink-ar.html',import.meta.url),'utf8');
const functionSource=(name,next)=>page.slice(page.indexOf(`    function ${name}(`),page.indexOf(`    function ${next}(`));
const vector=(x=0,y=0,z=0)=>({x,y,z,
  set(x,y,z){Object.assign(this,{x,y,z});return this;},
  clone(){return vector(this.x,this.y,this.z);},
  addScaledVector(p,s){return this.set(this.x+p.x*s,this.y+p.y*s,this.z+p.z*s);},
  lengthSq(){return this.x*this.x+this.y*this.y+this.z*this.z;},
  normalize(){const n=Math.sqrt(this.lengthSq());return this.set(this.x/n,this.y/n,this.z/n);},
  distanceTo(p){return Math.hypot(this.x-p.x,this.y-p.y,this.z-p.z);}
});

test('actual page captures one anchor on the second frame, without a surface scan or preview delay',()=>{
  for(const directionY of [-1,0,1]){
    const trackingGate=new FastTrackingGate(),anchors=[];
    const context=vm.createContext({placed:false,trackingGate,centerNdc:{},groundPlane:{},hitPoint:vector(),estimatedForward:vector(),
      statusText:{textContent:''},
      camera:{position:vector(0,1.5,0),updateMatrixWorld(){},getWorldDirection:v=>v.set(0,directionY,-1),getWorldPosition:v=>v.set(0,1.5,0)},
      raycaster:{setFromCamera(){},ray:{direction:{y:directionY},intersectPlane:(_,v)=>v.set(0,0,-2)}},
      createCombat(anchor){anchors.push(anchor);context.placed=true;}
    });
    vm.runInContext(functionSource('updatePlacement','tick'),context);
    observe(trackingGate,0);vm.runInContext('updatePlacement(0)',context);assert.equal(anchors.length,0);
    observe(trackingGate,16);vm.runInContext('updatePlacement(16)',context);assert.equal(anchors.length,1);
    assert.equal(anchors[0].y,0);assert.equal(anchors[0].z,directionY<0?-2:-2.8);
    context.camera.position.x=2;observe(trackingGate,32);vm.runInContext('updatePlacement(32)',context);
    assert.equal(anchors.length,1);assert.equal(anchors[0].x,0,'anchor remains fixed after placement');
  }
});

test('actual XR adapter pauses in the background/on exceptions and needs fresh frames on return',()=>{
  const trackingGate=new FastTrackingGate();let now=0,ticks=0,active=true;
  const context=vm.createContext({sceneReady:true,trackingGate,document:{hidden:false},lastTick:0,
    performance:{now:()=>now},combat:{setTracking:value=>{active=value;}},console:{error(){}},statusText:{},
    tick(){ticks++;active=trackingGate.ready(now);}
  });
  vm.runInContext(functionSource('worldModule','startupFailure'),context);
  const adapter=vm.runInContext('worldModule()',context);
  const update=()=>adapter.onUpdate({processCpuResult:{reality:{trackingStatus:'NORMAL',position}}});
  update();assert.equal(active,false);now=16;update();assert.equal(active,true);
  context.document.hidden=true;now=32;update();assert.equal(active,false);assert.equal(ticks,2);
  context.document.hidden=false;now=48;update();assert.equal(active,false);now=64;update();assert.equal(active,true);
  adapter.onException(new Error('mock tracking exception'));assert.equal(active,false);assert.equal(trackingGate.ready(now),false);
});
