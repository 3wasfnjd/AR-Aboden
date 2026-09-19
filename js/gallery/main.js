import * as THREE from 'three';
import {createStage} from './stage.js';
import {createRound,accuracy,spendShot,reloadRound,tickRound,ROUND_SECONDS} from './rules.js';
import {GalleryAudio} from './audio.js';
const $=id=>document.getElementById(id);
const ui={intro:$('intro'),hud:$('hud'),placement:$('placement'),ready:$('ready'),controls:$('controls'),results:$('results'),paused:$('paused'),crosshair:$('crosshair'),countdown:$('countdown'),pause:$('pause')};
let canvas=$('camerafeed'),renderer,scene,camera,stage,reticle;
let state='intro',mode='mixed',ar=false,busy=false,round=createRound(),elapsed=0,last=performance.now(),cooldown=0,count=3,pausedFrom='playing';
let floorY=-1.4,placementValid=false,stable=0,lastPoint=new THREE.Vector3(),stageScale=1,placementHeight=0;
let xrLoaded=false,xrStarted=false,xrTimer=null,trackingLost=false;
const point=new THREE.Vector3(),forward=new THREE.Vector3(),ray=new THREE.Raycaster(),pointer=new THREE.Vector2(),floor=new THREE.Plane(new THREE.Vector3(0,1,0),1.4);
const sound=new GalleryAudio();const labels={mixed:'تحدّي مختلط',fixed:'أهداف ثابتة',moving:'بطّات متحركة'};
let hitTimer,hudElapsed=0,lastShotAt=-Infinity;
function showState(next){state=next;document.body.dataset.state=next;for(const [key,el]of Object.entries(ui))el.hidden=true;
 if(next==='intro')ui.intro.hidden=false;
 if(next==='placing')ui.placement.hidden=false;
 if(next==='ready')ui.ready.hidden=false;
 if(['playing','countdown','paused'].includes(next)){ui.hud.hidden=false;ui.crosshair.hidden=false;}
 if(next==='playing'){ui.controls.hidden=false;ui.pause.hidden=false;}
 if(next==='countdown')ui.countdown.hidden=false;
 if(next==='results')ui.results.hidden=false;
 if(next==='paused')ui.paused.hidden=false;
 if(reticle)reticle.visible=next==='placing';
 $('vignette').hidden=ar;
 if(!ar&&camera)framePreview();
}
function toast(message){$('hitText').textContent=message;$('hitText').classList.add('on');clearTimeout(hitTimer);hitTimer=setTimeout(()=>$('hitText').classList.remove('on'),750);}
function fail(message){clearTimeout(xrTimer);$('errorText').textContent=message;$('error').hidden=false;busy=false;if(state==='playing'||state==='countdown')pauseGame('توقفت التجربة بسبب خطأ.');}
function size(){const vv=window.visualViewport;return{w:Math.round(vv?.width||innerWidth),h:Math.round(vv?.height||innerHeight)};}
function resize(){const{w,h}=size();document.documentElement.style.setProperty('--app-w',`${w}px`);document.documentElement.style.setProperty('--app-h',`${h}px`);canvas.style.width=`${w}px`;canvas.style.height=`${h}px`;
 // Preserve the tracked camera projection: XR8 owns its intrinsics and pose.
 if(renderer)renderer.setSize(w,h,false);
 if(!ar&&camera){camera.aspect=w/h;camera.updateProjectionMatrix();framePreview();}
}
function lights(){scene.add(new THREE.HemisphereLight(0xfff4d8,0x687e76,2.4));const sun=new THREE.DirectionalLight(0xffefd8,2.4);sun.position.set(-3,5,4);scene.add(sun);const fill=new THREE.DirectionalLight(0xc9e4e3,1.0);fill.position.set(4,3,-2);scene.add(fill);}
function initPreview(){const{w,h}=size();renderer=new THREE.WebGLRenderer({canvas,antialias:true,alpha:false,powerPreference:'high-performance'});renderer.setPixelRatio(Math.min(devicePixelRatio,1.7));renderer.setSize(w,h,false);renderer.setClearColor(0x102520);renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.25;scene=new THREE.Scene();camera=new THREE.PerspectiveCamera(36,w/h,.03,80);lights();}
function framePreview(){if(!camera||ar)return;const{w,h}=size();const intro=state==='intro';const wide=w>=750||w/h>1.45;const fit=4.5/(2*Math.tan(THREE.MathUtils.degToRad(18))*camera.aspect);const z=Math.max(6.8,fit)+(intro?1.65:0);camera.position.set(intro?.55:0,intro?2.65:1.75,z);camera.lookAt(0,1.02,.35);camera.clearViewOffset();
 if(intro){ // Keep the actual model away from the title and start button.
  if(wide)camera.setViewOffset(w,h,w*.17,0,w,h);
  else camera.setViewOffset(w,h,0,h*.20,w,h);
 }
 camera.updateProjectionMatrix();camera.updateMatrixWorld();
}
function makeReticle(){const g=new THREE.Group();const ring=new THREE.Mesh(new THREE.RingGeometry(.17,.185,48),new THREE.MeshBasicMaterial({color:0xdfba70,side:THREE.DoubleSide,depthTest:false}));ring.rotation.x=-Math.PI/2;g.add(ring);const center=new THREE.Mesh(new THREE.CircleGeometry(.027,20),ring.material);center.rotation.x=-Math.PI/2;g.add(center);scene.add(g);return g;}
function syncHUD(){ $('score').textContent=round.score;$('timer').textContent=Math.ceil(round.time);$('accuracy').textContent=round.shots?`${accuracy(round)}%`:'—';$('ammo').textContent=round.remaining;$('timeBar').style.width=`${round.time/ROUND_SECONDS*100}%`;$('timer').classList.toggle('urgent',round.time<10);$('ammoPips').innerHTML=Array.from({length:6},(_,i)=>`<i class="${i<round.magazine?'':'empty'}"></i>`).join('');$('reload').textContent=round.reload>0?'جاري التلقيم…':'تلقيم ↻';$('fire').disabled=round.reload>0||round.magazine===0;}
function setMode(value){mode=value;stage?.setMode(mode);document.querySelectorAll('[data-mode]').forEach(b=>{b.classList.toggle('selected',b.dataset.mode===mode);b.setAttribute('aria-pressed',String(b.dataset.mode===mode));});$('modeBadge').textContent=labels[mode];}
function beginPreview(){if(!stage||busy)return;sound.unlock();ar=false;stage.root.position.set(0,0,0);stage.root.rotation.y=0;stage.root.scale.setScalar(1);stage.root.visible=true;stage.reset();elapsed=0;setMode(mode);$('aimHelp').textContent='اضغط على الهدف لإطلاق النار، أو وجّه المؤشر إليه واستخدم الزناد. مركز الهدف يمنح نقاطًا إضافية.';$('reposition').textContent='اختيار نوع التحدّي';showState('ready');}
function startRound(){sound.unlock();round=createRound();elapsed=0;cooldown=0;lastShotAt=-Infinity;stage.reset();stage.setMode(mode);count=3;$('countdown').textContent='3';sound.tick();syncHUD();pointer.set(0,0);positionCrosshair();showState('countdown');}
function finish(){showState('results');sound.finish();const a=accuracy(round);$('finalScore').textContent=round.score;$('finalHits').textContent=`${round.hits} / ${round.shots}`;$('finalAccuracy').textContent=`${a}%`;
 const key=`aboden-gallery-best-${mode}`;let best=round.score;try{best=Math.max(Number(localStorage.getItem(key))||0,round.score);localStorage.setItem(key,String(best));}catch{}
 $('best').textContent=best;$('resultTitle').textContent=round.score>=500?'قنّاص الكرنفال':round.score>=250?'تصويب متقن':'جولة مكتملة';$('resultComment').textContent=a>=80?'دقّتك عالية. جرّب الحفاظ عليها مع الأهداف المتحركة.':'راقب حركة الهدف وخذ لحظة قبل إطلاق الطلقة.';
 $('medal').textContent=round.score>=500?'✦ ✦ ✦':round.score>=250?'✦ ✦':'✦';
}
function reload(){if(state!=='playing')return;if(reloadRound(round)){sound.reload();syncHUD();}}
function fire(){sound.unlock();const shotNow=performance.now();if(state!=='playing'||shotNow-lastShotAt<220)return;if(!spendShot(round)){if(round.magazine===0&&round.reload===0)reload();return;}lastShotAt=shotNow;sound.shot();camera.updateMatrixWorld();ray.setFromCamera(ar?new THREE.Vector2(0,0):pointer,camera);const hit=stage.shoot(ray);
 if(hit){round.score+=hit.points;round.hits++;sound.hit(hit.bull);toast(hit.bull?`في المركز! +${hit.points}`:`+${hit.points}`);ui.crosshair.classList.add('hit');setTimeout(()=>ui.crosshair.classList.remove('hit'),150);}
 $('fire').classList.add('fired');setTimeout(()=>$('fire').classList.remove('fired'),90);if(navigator.vibrate)navigator.vibrate(hit?15:7);
 if(round.magazine===0&&round.remaining>0)reload();syncHUD();if(round.remaining===0)finish();
}
function pauseGame(reason='تابع عندما تكون مستعدًا.'){if(!['playing','countdown'].includes(state))return;pausedFrom=state;$('pauseReason').textContent=reason;showState('paused');}
function resume(){if(trackingLost){toast('انتظر عودة تتبع الكاميرا');return;}last=performance.now();showState(pausedFrom);}
function positionCrosshair(){const{w,h}=size();ui.crosshair.style.left=`${(pointer.x*.5+.5)*w}px`;ui.crosshair.style.top=`${(-pointer.y*.5+.5)*h}px`;}
function aim(e){if(ar||state!=='playing')return;const r=canvas.getBoundingClientRect();pointer.set((e.clientX-r.left)/r.width*2-1,-(e.clientY-r.top)/r.height*2+1);positionCrosshair();}
function bindCanvas(){canvas.addEventListener('pointermove',aim);canvas.addEventListener('pointerdown',e=>{if(ar)return;if(state==='playing'){e.preventDefault();aim(e);fire();}});}
function updatePlacement(dt){if(!camera||!stage)return;camera.updateMatrixWorld();floor.constant=-(floorY+placementHeight);ray.setFromCamera(new THREE.Vector2(0,0),camera);const hit=ray.ray.intersectPlane(floor,point);const distance=hit?hit.distanceTo(camera.position):Infinity;
 const horizontalDistance=hit?Math.hypot(point.x-camera.position.x,point.z-camera.position.z):0;
 placementValid=!!hit&&horizontalDistance>2.4*stageScale&&distance<8&&!trackingLost;
 if(!placementValid){stable=0;reticle.visible=false;stage.root.visible=false;$('place').disabled=true;$('placementTitle').textContent=hit&&horizontalDistance<=2.4*stageScale?'أبعد المؤشر قليلًا عنك':'وجّه الجوال نحو مساحة أمامك';return;}
 if(lastPoint.distanceTo(point)<.06)stable+=dt;else stable=0;lastPoint.copy(point);reticle.visible=true;reticle.position.copy(point);reticle.position.y+=.014;stage.root.visible=true;stage.root.position.copy(point);stage.root.rotation.y=Math.atan2(camera.position.x-point.x,camera.position.z-point.z);stage.root.scale.setScalar(stageScale);
 $('place').disabled=stable<.3;$('placementTitle').textContent=stable>=.3?'المكان جاهز للتثبيت':'ثبّت الجوال قليلًا';
}
function place(){if(!placementValid||stable<.3)return;reticle.visible=false;showState('ready');$('aimHelp').textContent='حرّك الجوال للتصويب واضغط الزناد. مركز الهدف يمنح نقاطًا إضافية.';$('reposition').textContent='تغيير مكان المنصة';}
function reposition(){if(!ar){showState('intro');return;}stage.reset();stable=0;placementValid=false;showState('placing');}
function loadXR(){return new Promise((resolve,reject)=>{
 if(window.XR8){resolve();return;}let settled=false;const done=()=>{if(settled)return;settled=true;clearTimeout(timer);resolve();};const timer=setTimeout(()=>{if(!settled){settled=true;reject(new Error('استغرق محرك الواقع المعزز وقتًا طويلًا. تحقق من الاتصال وأعد المحاولة.'));}},30000);
 window.addEventListener('xrloaded',done,{once:true});const script=document.createElement('script');script.src='https://cdn.jsdelivr.net/npm/@8thwall/engine-binary@1/dist/xr.js';script.crossOrigin='anonymous';script.async=true;script.setAttribute('data-preload-chunks','slam');script.onerror=()=>{clearTimeout(timer);reject(new Error('تعذر تحميل محرك الواقع المعزز. يمكنك استخدام المعاينة بدون كاميرا.'));};document.head.appendChild(script);
 });}
async function enterAR(){if(!stage||busy)return;busy=true;sound.unlock();$('enterAR').disabled=true;$('enterAR').firstElementChild.textContent='جاري تشغيل الكاميرا…';$('loadStatus').textContent='اسمح باستخدام الكاميرا عند ظهور الطلب.';
 try{
  window.THREE=THREE;await loadXR();xrLoaded=true;
  // The preview context must not be reused by the XR camera pipeline.
  renderer.dispose();canvas.replaceWith(canvas.cloneNode(false));canvas=$('camerafeed');renderer=null;ar=true;pointer.set(0,0);positionCrosshair();resize();
  XR8.XrController.configure({disableWorldTracking:false,enableLighting:true,enableWorldPoints:true,scale:'responsive'});
  XR8.addCameraPipelineModules([XR8.GlTextureRenderer.pipelineModule(),XR8.Threejs.pipelineModule(),XR8.XrController.pipelineModule(),{
   name:'aboden-fairground',
   onStart:()=>{try{const xr=XR8.Threejs.xrScene();scene=xr.scene;camera=xr.camera;renderer=xr.renderer;renderer.shadowMap.enabled=false;scene.add(stage.root);stage.root.visible=false;lights();reticle=makeReticle();floorY=camera.position.y-1.4;stage.root.rotation.y=0;busy=false;xrStarted=true;clearTimeout(xrTimer);showState('placing');resize();}catch(err){console.error(err);fail('تعذر تجهيز المنصة في الكاميرا. أعد المحاولة.');}},
   onException:error=>{console.error(error);fail('تعذر تشغيل الكاميرا أو التتبع. اسمح بالكاميرا وافتح الرابط في Safari أو Chrome مباشرة.');},
   onCameraStatusChange:({status})=>{if(status==='failed')fail('لم نتمكن من فتح الكاميرا. تحقق من الإذن وأعد المحاولة.');},
   listeners:[{event:'reality.trackingstatus',process:({detail})=>{const status=detail?.status;trackingLost=status==='LIMITED';if(trackingLost)pauseGame('توقف التتبع مؤقتًا. حرّك الجوال ببطء نحو مكان واضح ومضاء.');} }]
  }]);
  xrTimer=setTimeout(()=>{if(!xrStarted)fail('لم يبدأ تتبع الكاميرا. تحقق من الإذن، ثم أعد المحاولة.');},30000);
  await XR8.run({canvas});
 }catch(err){console.error(err);fail(err.message||'تعذر بدء الواقع المعزز.');}
}
function loop(now){requestAnimationFrame(loop);const realDt=Math.max(0,(now-last)/1000||.016),dt=Math.min(.1,realDt);last=now;if(!stage||!renderer||!camera)return;
 if(state!=='paused'&&!document.hidden){cooldown=Math.max(0,cooldown-realDt);
  if(state==='placing')updatePlacement(dt);
  if(state==='countdown'){const old=Math.ceil(count);count-=realDt;if(count<=0){showState('playing');}else if(Math.ceil(count)!==old){$('countdown').textContent=Math.ceil(count);sound.tick();}}
  if(state==='playing'){const finished=tickRound(round,realDt);elapsed+=dt;hudElapsed+=realDt;if(hudElapsed>=.1){syncHUD();hudElapsed=0;}if(finished)finish();}
  if(['intro','ready','playing','placing'].includes(state)){if(state!=='playing')elapsed+=dt;stage.update(dt,elapsed,true);}
 }
 if(!ar){if(state==='intro')stage.root.rotation.y=Math.sin(now*.00013)*.08;renderer.render(scene,camera);}
}
$('enterAR').addEventListener('click',enterAR);$('preview').addEventListener('click',beginPreview);$('startRound').addEventListener('click',startRound);$('again').addEventListener('click',startRound);$('place').addEventListener('click',place);$('reposition').addEventListener('click',reposition);
$('fire').addEventListener('pointerdown',e=>{e.preventDefault();fire();});$('reload').addEventListener('click',reload);$('pause').addEventListener('click',()=>pauseGame());$('resume').addEventListener('click',resume);
$('sound').addEventListener('click',()=>{sound.unlock();sound.muted=!sound.muted;$('sound').textContent=sound.muted?'×':'♪';$('sound').setAttribute('aria-label',sound.muted?'تشغيل الصوت':'كتم الصوت');});
$('scale').addEventListener('input',e=>{stageScale=Number(e.target.value)/100;});$('height').addEventListener('input',e=>{placementHeight=Number(e.target.value)/100;stable=0;});
for(const b of document.querySelectorAll('[data-mode]'))b.addEventListener('click',()=>setMode(b.dataset.mode));
window.addEventListener('resize',resize);window.visualViewport?.addEventListener('resize',resize);window.addEventListener('orientationchange',()=>{setTimeout(resize,250);});document.addEventListener('visibilitychange',()=>{if(document.hidden)pauseGame('توقفت الجولة عند مغادرة الشاشة.');else last=performance.now();});window.addEventListener('pagehide',()=>{try{if(ar)XR8.stop();sound.ctx?.suspend();}catch{}});
window.addEventListener('keydown',e=>{if(e.code==='Space'){e.preventDefault();fire();}if(e.code==='KeyR')reload();if(e.code==='Escape')state==='paused'?resume():pauseGame();});
async function boot(){try{initPreview();bindCanvas();resize();requestAnimationFrame(loop);stage=await createStage(e=>{$('loadStatus').textContent=e.total?`تحميل المنصة ${Math.round(e.loaded/e.total*100)}%`:'جاري تحميل المنصة…';});scene.add(stage.root);window.galleryLoaded=true;setMode(mode);framePreview();$('enterAR').disabled=false;$('enterAR').firstElementChild.textContent='ضع الكشك في مكانك';$('preview').disabled=false;$('loadStatus').textContent='جاهز · افتح الكاميرا أو جرّب المعاينة';if(new URLSearchParams(location.search).has('preview'))beginPreview();
 // Exposed only in an explicit QA session, never enabled by the normal link.
 if(new URLSearchParams(location.search).has('qa'))window.galleryQA={THREE,get stage(){return stage;},get camera(){return camera;},get state(){return state;},get round(){return round;},get renderer(){return renderer;},fire,beginPreview,startRound,pauseGame,resume,setMode,finish,aimTarget:(index)=>{const t=stage.targets[index];t.hitObject.updateWorldMatrix(true,false);const p=new THREE.Box3().setFromObject(t.hitObject).getCenter(new THREE.Vector3()).project(camera);pointer.set(p.x,p.y);positionCrosshair();return{x:(p.x*.5+.5)*innerWidth,y:(-p.y*.5+.5)*innerHeight};}};
 }catch(err){console.error(err);fail('تعذر تحميل الكشك. تحقق من اتصال الإنترنت ثم أعد المحاولة.');}}
boot();
