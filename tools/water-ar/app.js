import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { createWaterPool } from './pool.js';
import { PlacementLock, intersectHorizontal, supportedSurface } from './placement.js';

const $=id=>document.getElementById(id),canvas=$('view');
const placement=new PlacementLock();
const raycaster=new THREE.Raycaster(),ndc=new THREE.Vector2(),localRay=new THREE.Ray();
const inverse=new THREE.Matrix4(),hitPoint=new THREE.Vector3();
const sphereProxy=new THREE.Sphere(),plane=new THREE.Plane(new THREE.Vector3(0,1,0),0);
let mode='',scene,camera,renderer,pool,orbit,reticle;
let width=.70,yaw=0,lastTime=0,nextSample=0,ready=false,starting=false,disposed=false,failed=false;
let drag=null,lastDrop=null,lastDropAt=0,toastTimer,enginePromise;
let frames=0,fps=0,statsAt=0;
window.THREE=THREE;
function hint(text){if($('hint').textContent!==text)$('hint').textContent=text;}
function toast(text){$('toast').textContent=text;clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').textContent='',2800);}
function resized(){
  const w=window.innerWidth,h=window.visualViewport?.height||window.innerHeight;
  document.documentElement.style.setProperty('--vh',h+'px');
  if(mode==='preview'&&renderer){renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix();}
}
function releaseDrag(){
  if(drag){const id=drag.id;drag=null;try{canvas.releasePointerCapture(id);}catch{}}
  lastDrop=null;if(orbit)orbit.enabled=true;
}
function fail(error){
  if(failed)return;failed=true;ready=false;starting=false;releaseDrag();
  console.error('[WATER LAB]',error);
  if(mode==='ar'){try{window.XR8?.stop();}catch{}}
  renderer?.setAnimationLoop(null);pool?.dispose();pool=null;
  $('hud').hidden=true;$('intro').hidden=false;$('error').hidden=false;
  $('error').textContent=String(error?.message||error);$('loading').textContent='';
  $('arBtn').disabled=true;$('previewBtn').disabled=true;$('retryBtn').hidden=false;
}

function addSceneContent(){
  renderer.debug.checkShaderErrors=true;
  renderer.debug.onShaderError=(gl,program,vs,fs)=>{console.error(gl.getProgramInfoLog(program),gl.getShaderInfoLog(vs),gl.getShaderInfoLog(fs));setTimeout(()=>fail(new Error('تعذر ترجمة مؤثر الماء على هذا المتصفح. جرّب الجودة الخفيفة.')),0);};
  scene.add(new THREE.HemisphereLight(0xe8f8ff,0x57666c,2));
  const light=new THREE.DirectionalLight(0xffffff,2.4);light.position.set(2,4,-1);scene.add(light);
  pool=createWaterPool(renderer,$('quality').value);pool.setWidth(width);scene.add(pool.group);
  reticle=new THREE.Mesh(new THREE.RingGeometry(.06,.078,48).rotateX(-Math.PI/2),new THREE.MeshBasicMaterial({color:0x8ce4ee,side:THREE.DoubleSide,depthWrite:false}));
  reticle.visible=false;scene.add(reticle);
  pool.group.visible=mode==='preview';
  lastTime=performance.now();statsAt=lastTime;ready=true;starting=false;
  $('intro').hidden=true;$('hud').hidden=false;$('modeLabel').textContent=mode==='ar'?'· AR':'· معاينة 3D';
  $('placementControls').hidden=mode!=='ar';resized();
  if(mode==='preview')hint('المس الماء أو اسحب الكرة. اسحب خارج الحوض لتدوير المشهد.');
  else hint('حرّك الجوال بهدوء ووجّه منتصف الشاشة إلى الأرضية.');
}

async function startPreview(){
  if(starting||ready)return;starting=true;mode='preview';
  $('arBtn').disabled=$('previewBtn').disabled=true;
  try{
    renderer=new THREE.WebGLRenderer({canvas,antialias:true,alpha:false,powerPreference:'high-performance'});
    renderer.setPixelRatio(Math.min(devicePixelRatio||1,1.5));renderer.setClearColor(0x10222c,1);
    scene=new THREE.Scene();scene.background=new THREE.Color(0x10222c);
    camera=new THREE.PerspectiveCamera(45,1,.01,30);camera.position.set(1.05,1.1,1.3);
    orbit=new OrbitControls(camera,canvas);orbit.target.set(0,.22,0);orbit.enableDamping=true;
    orbit.minDistance=.5;orbit.maxDistance=3;orbit.minPolarAngle=.15;orbit.maxPolarAngle=Math.PI/2-.08;
    addSceneContent();
    const floor=new THREE.Mesh(new THREE.PlaneGeometry(8,8).rotateX(-Math.PI/2),new THREE.MeshStandardMaterial({color:0x16333b,roughness:.85}));
    floor.position.y=-.005;scene.add(floor);
    renderer.setAnimationLoop(now=>{
      if(!ready||document.hidden)return;
      try{orbit.update();tick(now);renderer.render(scene,camera);}catch(e){fail(e);}
    });
  }catch(error){fail(error);}
}

function loadEngine(){
  if(window.XR8)return Promise.resolve(window.XR8);
  if(enginePromise)return enginePromise;
  enginePromise=new Promise((resolve,reject)=>{
    const script=document.createElement('script');let complete=false;
    function done(error){if(complete)return;complete=true;clearTimeout(timer);window.removeEventListener('xrloaded',loaded);error?reject(error):resolve(window.XR8);}
    function loaded(){if(window.XR8)done();}
    const timer=setTimeout(()=>done(new Error('تعذر تحميل محرك AR خلال المهلة. أعد التحميل أو جرّب المعاينة بدون كاميرا.')),30000);
    window.addEventListener('xrloaded',loaded);
    script.src='https://cdn.jsdelivr.net/npm/@8thwall/engine-binary@1/dist/xr.js';
    script.crossOrigin='anonymous';script.async=true;script.dataset.preloadChunks='slam';
    script.onload=loaded;script.onerror=()=>done(new Error('تعذر تنزيل محرك AR. تحقق من اتصال الإنترنت.'));
    document.head.append(script);
  });
  return enginePromise;
}

async function startAR(){
  if(starting||ready)return;
  if(!window.isSecureContext){$('error').hidden=false;$('error').textContent='تشغيل الكاميرا يحتاج رابط HTTPS.';return;}
  starting=true;mode='ar';$('arBtn').disabled=$('previewBtn').disabled=true;
  $('loading').textContent='تحميل تتبع المكان، ثم طلب إذن الكاميرا…';
  try{
    const XR8=await loadEngine();if(disposed)return;
    XR8.XrController.configure({disableWorldTracking:false,enableLighting:false,enableWorldPoints:true,scale:'absolute'});
    XR8.addCameraPipelineModules([
      XR8.GlTextureRenderer.pipelineModule(),XR8.Threejs.pipelineModule(),XR8.XrController.pipelineModule(),
      {
        name:'aboden-water-ar-lab',
        onStart(){
          try{
            const xr=XR8.Threejs.xrScene();scene=xr.scene;camera=xr.camera;renderer=xr.renderer;
            // Keep XR8's camera background; never add a sky/background scene.
            scene.background=null;renderer.shadowMap.enabled=false;
            addSceneContent();window.dispatchEvent(new Event('resize'));
          }catch(error){fail(error);}
        },
        onUpdate({processCpuResult}){
          if(!ready||document.hidden)return;
          try{
            const now=performance.now(),r=processCpuResult?.reality;
            placement.observe(now,r?.trackingStatus,r?.position);
            updatePlacement(now,r?.worldPoints||[]);tick(now);
          }catch(error){fail(error);}
        },
        onCameraStatusChange({status}){if(status==='failed')fail(new Error('تعذر فتح الكاميرا. اسمح للمتصفح بالكاميرا ثم أعد التحميل.'));},
        onException(error){fail(new Error('تعذر استمرار AR: '+String(error?.message||error)));},
      },
    ]);
    const result=XR8.run({canvas});if(result?.catch)result.catch(fail);
  }catch(error){fail(error);}
}

function updatePlacement(now,worldPoints){
  if(placement.anchor){
    // Only an explicit relocation can move the saved world-space anchor.
    pool.group.position.copy(placement.anchor);reticle.visible=false;
    const tracked=placement.trackingReady(now);pool.group.visible=tracked;
    if(!tracked)releaseDrag();
    hint(tracked?'الحوض مثبت. المس الماء أو اسحب الكرة.':'التتبع ضعيف — الحوض مخفي مؤقتًا. وجّه الجوال إلى المكان نفسه.');
    return;
  }
  if(!placement.trackingReady(now)){
    pool.group.visible=reticle.visible=false;$('placeBtn').disabled=true;
    hint('حرّك الجوال ببطء حتى يستقر تتبع المكان.');return;
  }
  if(now<nextSample)return;nextSample=now+100;
  camera.updateMatrixWorld(true);raycaster.setFromCamera(ndc.set(0,0),camera);
  const ray=raycaster.ray;let result=null;
  if($('surfaceType').value==='table'){
    let hits=[];try{hits=window.XR8.XrController.hitTest(.5,.5,['FEATURE_POINT']);}catch{}
    result=supportedSurface(ray.origin,ray.direction,hits,[...worldPoints,...hits]);
  }else{
    const p=intersectHorizontal(ray.origin,ray.direction,0);if(p)result={position:p,kind:'estimated-floor'};
  }
  placement.sample(result,now);
  if(!placement.candidate){
    reticle.visible=pool.group.visible=false;$('placeBtn').disabled=true;
    hint($('surfaceType').value==='table'?'امسح طاولة واضحة التفاصيل. لا يتم التثبيت من نقطة منفردة.':'وجّه منتصف الشاشة إلى الأرضية أمامك.');return;
  }
  pool.group.position.copy(placement.candidate);pool.group.rotation.y=yaw;pool.group.visible=true;
  reticle.position.copy(placement.candidate);reticle.position.y+=.004;reticle.visible=true;
  reticle.material.color.setHex(placement.ready?0x9ef5c6:0x8ce4ee);
  $('placeBtn').disabled=!placement.ready;
  hint(placement.ready?(result.kind==='supported'?'سطح أفقي مدعوم — اضغط ثبّت الحوض.':'موضع أرضي تقديري — تحقق من الارتفاع ثم ثبّت الحوض.'):'اثبت الجوال لحظة لتأكيد الموضع.');
}
function placeOrMove(){
  releaseDrag();
  if(placement.anchor){placement.relocate();pool.group.visible=false;$('placeBtn').disabled=true;$('placeBtn').textContent='ثبّت الحوض';$('surfaceType').disabled=false;return;}
  const anchor=placement.lock(performance.now());if(!anchor)return;
  pool.group.position.copy(anchor);pool.group.rotation.y=yaw;pool.group.updateMatrixWorld(true);
  reticle.visible=false;$('placeBtn').textContent='نقل الحوض';$('surfaceType').disabled=true;toast('تم تثبيت موضع الحوض');
}
function tick(now){
  const dt=Math.min(.05,Math.max(0,(now-lastTime)/1000));lastTime=now;
  if(pool.group.visible)pool.step(dt,camera);
  frames++;
  if(now-statsAt>=1000){fps=Math.round(frames*1000/(now-statsAt));frames=0;statsAt=now;const s=pool.stats();$('diagnostics').textContent=`${fps} FPS | ${s.resolution}² | ${mode==='ar'?placement.status:'3D'} | queued ${s.queued}`;}
}
function rayInPool(event){
  const rect=canvas.getBoundingClientRect();
  ndc.set(((event.clientX-rect.left)/rect.width)*2-1,-((event.clientY-rect.top)/rect.height)*2+1);
  camera.updateMatrixWorld(true);pool.group.updateMatrixWorld(true);
  raycaster.setFromCamera(ndc,camera);inverse.copy(pool.space.matrixWorld).invert();
  localRay.copy(raycaster.ray).applyMatrix4(inverse);return localRay;
}
function hitWater(ray,y=0){plane.constant=-y;const p=ray.intersectPlane(plane,hitPoint);return p&&Math.abs(p.x)<.96&&Math.abs(p.z)<.96?p:null;}
function pointerDown(e){
  if(!ready||!pool.group.visible||drag||(mode==='ar'&&!placement.anchor)|| (e.pointerType==='mouse'&&e.button!==0))return;
  const ray=rayInPool(e);sphereProxy.set(pool.sphere.position,pool.radius);
  const sphereHit=ray.intersectSphere(sphereProxy,new THREE.Vector3());
  const waterHit=hitWater(ray);
  if(!sphereHit&&!waterHit)return;
  e.preventDefault();e.stopImmediatePropagation();canvas.setPointerCapture(e.pointerId);if(orbit)orbit.enabled=false;
  drag={id:e.pointerId,kind:sphereHit?'sphere':'water',offset:new THREE.Vector3()};
  if(sphereHit){const p=hitWater(ray,pool.sphere.position.y);if(p)drag.offset.copy(pool.sphere.position).sub(p);}
  else{pool.addDrop(waterHit.x,waterHit.z);lastDrop=waterHit.clone();lastDropAt=performance.now();}
}
function pointerMove(e){
  if(!drag||e.pointerId!==drag.id||!ready)return;e.preventDefault();e.stopImmediatePropagation();
  const ray=rayInPool(e);
  if(drag.kind==='sphere'){
    const p=hitWater(ray,pool.sphere.position.y);if(!p)return;
    pool.sphere.position.x=THREE.MathUtils.clamp(p.x+drag.offset.x,-.73,.73);
    pool.sphere.position.z=THREE.MathUtils.clamp(p.z+drag.offset.z,-.73,.73);
  }else{
    const p=hitWater(ray);if(!p||performance.now()-lastDropAt<25)return;
    const dist=lastDrop?lastDrop.distanceTo(p):0,n=Math.min(6,Math.max(1,Math.ceil(dist/.08)));
    for(let i=1;i<=n;i++){const t=i/n;pool.addDrop(lastDrop?THREE.MathUtils.lerp(lastDrop.x,p.x,t):p.x,lastDrop?THREE.MathUtils.lerp(lastDrop.z,p.z,t):p.z,.012);}
    lastDrop=p.clone();lastDropAt=performance.now();
  }
}
function pointerUp(e){if(drag?.id!==e.pointerId)return;e.preventDefault();e.stopImmediatePropagation();releaseDrag();}
canvas.addEventListener('pointerdown',pointerDown,{capture:true,passive:false});
canvas.addEventListener('pointermove',pointerMove,{capture:true,passive:false});
canvas.addEventListener('pointerup',pointerUp,{capture:true,passive:false});
canvas.addEventListener('pointercancel',pointerUp,{capture:true,passive:false});
canvas.addEventListener('lostpointercapture',()=>releaseDrag());
canvas.addEventListener('webglcontextlost',e=>{e.preventDefault();fail(new Error('توقفت الرسوم على الجهاز. أعد التحميل بالجودة الخفيفة.'));});
$('arBtn').addEventListener('click',startAR);$('previewBtn').addEventListener('click',startPreview);
$('placeBtn').addEventListener('click',placeOrMove);
$('surfaceType').addEventListener('change',()=>{placement.clearCandidate();pool.group.visible=false;$('placeBtn').disabled=true;});
function setSize(factor){if(!pool)return;releaseDrag();width=THREE.MathUtils.clamp(width*factor,.35,1.25);pool.setWidth(width);$('widthLabel').textContent='عرض الحوض: '+Math.round(width*100)+' سم';}
$('smallerBtn').addEventListener('click',()=>setSize(.9));$('largerBtn').addEventListener('click',()=>setSize(1.1));
$('rotateBtn').addEventListener('click',()=>{if(pool){releaseDrag();yaw+=Math.PI/12;pool.group.rotation.y=yaw;}});
$('splashBtn').addEventListener('click',()=>{if(pool&&pool.group.visible){pool.addDrop(-.4,-.35,.03,.05);pool.addDrop(.45,.3,.025,.04);}});
$('resetBtn').addEventListener('click',()=>{if(pool){releaseDrag();pool.reset();toast('تم تصفير الماء والكرة دون تغيير موضع الحوض');}});
function dispose(){
  if(disposed)return;disposed=true;ready=false;releaseDrag();clearTimeout(toastTimer);
  if(mode==='ar'){try{window.XR8?.stop();}catch{}}
  renderer?.setAnimationLoop(null);pool?.dispose();orbit?.dispose();
  if(mode==='preview'){scene?.traverse(o=>{if(o.isMesh){o.geometry?.dispose();if(Array.isArray(o.material))o.material.forEach(m=>m.dispose());else o.material?.dispose();}});renderer?.dispose();}
}
$('exitBtn').addEventListener('click',()=>{dispose();location.reload();});
window.addEventListener('pagehide',dispose);
window.addEventListener('pageshow',e=>{if(e.persisted&&disposed)location.reload();});
window.addEventListener('resize',resized);window.visualViewport?.addEventListener('resize',resized);
document.addEventListener('visibilitychange',()=>{
  releaseDrag();lastTime=performance.now();
  if(mode==='ar'&&ready){
    try{if(document.hidden)window.XR8?.pause();else{window.XR8?.resume();placement.clearCandidate();}}catch(error){fail(error);}
  }
});
clearTimeout(window.waterBootTimer);$('loading').textContent='المحاكاة جاهزة. اختر طريقة التجربة.';
$('arBtn').disabled=$('previewBtn').disabled=false;$('retryBtn').hidden=true;resized();
