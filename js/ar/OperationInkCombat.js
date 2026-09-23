import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { clone as cloneSkeleton } from 'three/addons/utils/SkeletonUtils.js';
import { PaintballEffects } from './PaintballEffects.js?v=1';

// Adapted for AR-Aboden from the gameplay concepts and balancing values in
// byteab/operation-ink (MIT). This file is intentionally independent from the
// original mission runtime so it can run inside XR8 on mobile.

export const WEAPONS = {
  pistol:  { label:'مسدس',      capacity:12, reload:1.85, interval:.25,  range:22, damage:30, automatic:false, kick:.018 },
  ak:      { label:'AK',         capacity:30, reload:2.30, interval:.12,  range:28, damage:34, automatic:true,  kick:.022 },
  smg:     { label:'SMG',        capacity:24, reload:2.05, interval:.085, range:20, damage:24, automatic:true,  kick:.012 },
  shotgun: { label:'Shotgun',    capacity:6,  reload:2.80, interval:.90,  range:11, damage:28, automatic:false, kick:.050 },
  sniper:  { label:'Sniper',     capacity:5,  reload:2.90, interval:1.35, range:34, damage:65, automatic:false, kick:.038 }
};

const ENEMY_WEAPONS = {
  pistol:{damage:10, gap:.72},
  ak:{damage:9, gap:.48},
  smg:{damage:7, gap:.38},
  shotgun:{damage:14, gap:1.25},
  sniper:{damage:24, gap:1.80}
};

const HIT_MULTIPLIER = {head:2.2, torso:1, arm:.6, leg:.7};
const FRONT_AREA={near:1.8,far:5.8,widthRatio:.65,separation:.55};

const SOLDIER_MODEL_URL = 'https://raw.githubusercontent.com/guyz/tinystrike/main/assets/models/soldier_t.glb';
const SOLDIER_SOURCE_HEIGHT = 2.1358;
const SOLDIER_TARGET_HEIGHT = 1.20;
const SOLDIER_MODEL_SCALE = SOLDIER_TARGET_HEIGHT / SOLDIER_SOURCE_HEIGHT;
const SOLDIER_HIT_PROXY_HEIGHT = 1.895;
const SOLDIER_HIT_PROXY_SCALE = SOLDIER_TARGET_HEIGHT / SOLDIER_HIT_PROXY_HEIGHT;
const SOLDIER_GUN_MESH_NAMES = new Set(['AK','SMG','Sniper','Pistol']);
const SOLDIER_GUN_FOR_WEAPON = {
  ak:'AK', smg:'SMG', sniper:'Sniper', pistol:'Pistol', shotgun:'AK'
};
let soldierAssetPromise = null;

function loadSoldierAsset(){
  if(soldierAssetPromise) return soldierAssetPromise;
  soldierAssetPromise = new Promise((resolve,reject)=>{
    const loader = new GLTFLoader();
    loader.setCrossOrigin('anonymous');
    loader.load(
      SOLDIER_MODEL_URL,
      gltf=>resolve({scene:gltf.scene,clips:gltf.animations||[]}),
      undefined,
      reject
    );
  }).catch(err=>{
    console.warn('[Operation Ink AR] Soldier GLB failed; primitive fallback remains active.',err);
    soldierAssetPromise = null;
    return null;
  });
  return soldierAssetPromise;
}

function setSoldierAction(root,name,fade=.14){
  const u=root?.userData;
  if(!u?.mixer) return;
  let action=u.actions?.[name];
  if(!action) action=u.actions?.Idle || Object.values(u.actions||{})[0];
  if(!action || u.actionName===name) return;

  const previous=u.actions?.[u.actionName];
  if(previous && previous!==action) previous.fadeOut(fade);

  action.enabled=true;
  action.reset();
  if(name==='Walk' || name==='Walk_Shoot')action.time=(u.phase/(Math.PI*2))*action.getClip().duration;
  action.fadeIn(fade);
  if(name==='Death'){
    action.setLoop(THREE.LoopOnce,1);
    action.clampWhenFinished=true;
  }else{
    action.setLoop(THREE.LoopRepeat,Infinity);
    action.clampWhenFinished=false;
  }
  action.play();
  u.actionName=name;
}

function attachSoldierMuzzle(root,model){
  const gun=model.getObjectByName(SOLDIER_GUN_FOR_WEAPON[root.userData.weapon]);
  if(!gun) return;

  // Locate the barrel tip in the model's +Z facing direction, then keep it in
  // the gun's local space so the muzzle follows the animated hand and scale.
  model.updateWorldMatrix(true,true);
  const worldToModel=new THREE.Matrix4().copy(model.matrixWorld).invert();
  const meshes=[];
  gun.traverse(obj=>{
    const positions=obj.geometry?.attributes.position;
    if(positions) meshes.push({positions,toModel:new THREE.Matrix4().multiplyMatrices(worldToModel,obj.matrixWorld)});
  });
  const point=new THREE.Vector3(),tip=new THREE.Vector3();
  let front=-Infinity,back=Infinity,count=0;
  for(const {positions,toModel} of meshes){
    for(let i=0;i<positions.count;i++){
      point.fromBufferAttribute(positions,i).applyMatrix4(toModel);
      front=Math.max(front,point.z);back=Math.min(back,point.z);
    }
  }
  const band=(front-back)*.015;
  for(const {positions,toModel} of meshes){
    for(let i=0;i<positions.count;i++){
      point.fromBufferAttribute(positions,i).applyMatrix4(toModel);
      if(point.z>=front-band){tip.add(point);count++;}
    }
  }
  if(!count) return;
  const muzzle=new THREE.Object3D();
  muzzle.name='soldier-muzzle';
  const modelToGun=new THREE.Matrix4().multiplyMatrices(worldToModel,gun.matrixWorld).invert();
  muzzle.position.copy(tip.divideScalar(count).applyMatrix4(modelToGun));
  gun.add(muzzle);
  root.userData.parts.muzzle=muzzle;
}

async function attachSoldierModel(root){
  const asset=await loadSoldierAsset();
  if(!asset || !root?.parent) return false;

  const model=cloneSkeleton(asset.scene);
  const visual=new THREE.Group();
  visual.name='quaternius-soldier-visual';
  // The GLB already faces +Z, matching facePhone's atan2(dx,dz).
  visual.scale.setScalar(SOLDIER_MODEL_SCALE);
  visual.add(model);
  root.add(visual);

  model.traverse(obj=>{
    if(obj.isMesh || obj.isSkinnedMesh){
      obj.castShadow=true;
      obj.receiveShadow=true;
      obj.frustumCulled=false;
    }
    if(SOLDIER_GUN_MESH_NAMES.has(obj.name)){
      obj.visible=obj.name===SOLDIER_GUN_FOR_WEAPON[root.userData.weapon];
    }
  });

  const mixer=new THREE.AnimationMixer(model);
  const actions={};
  for(const clip of asset.clips){
    if(!clip?.name) continue;
    actions[clip.name]=mixer.clipAction(clip);
  }

  root.userData.visual=visual;
  root.userData.mixer=mixer;
  root.userData.actions=actions;
  root.userData.actionName=null;
  root.userData.fallbackVisual.visible=false;
  // Calibrate the feet and muzzle in the standing pose, including when the
  // model finishes loading after this enemy was killed.
  if(root.userData.dead){
    root.rotation.x=0;
    root.rotation.z=0;
    root.position.y=root.userData.groundY;
  }
  setSoldierAction(root,'Idle',0);
  mixer.update(0);
  root.updateMatrixWorld(true);
  const box=new THREE.Box3().setFromObject(visual,true);
  const rootWorld=new THREE.Vector3();
  root.getWorldPosition(rootWorld);
  if(Number.isFinite(box.min.y)) visual.position.y += rootWorld.y - box.min.y;
  root.updateMatrixWorld(true);
  attachSoldierMuzzle(root,model);
  if(root.userData.dead) setSoldierAction(root,'Death',0);

  console.info('[Operation Ink AR] Soldier model ready', {
    animations:Object.keys(actions),
    height:SOLDIER_TARGET_HEIGHT
  });
  return true;
}
function clamp(v,a,b){ return Math.max(a,Math.min(b,v)); }
function flatDistance(a,b){ return Math.hypot(a.x-b.x,a.z-b.z); }

function makeMat(color, roughness=.72){
  return new THREE.MeshStandardMaterial({color,roughness,metalness:.03});
}

function limb(geometry, material, x,y,z, rx=0, rz=0){
  const pivot = new THREE.Group();
  pivot.position.set(x,y,z);
  const mesh = new THREE.Mesh(geometry,material);
  mesh.position.y = -.5;
  mesh.rotation.x = rx;
  mesh.rotation.z = rz;
  pivot.add(mesh);
  return {pivot,mesh};
}

function markHit(mesh, root, zone){
  mesh.userData.enemyRoot = root;
  mesh.userData.hitZone = zone;
  root.userData.hitMeshes.push(mesh);
}

function makeWeaponMesh(name, dark){
  const g = new THREE.Group();
  const body = new THREE.Mesh(
    new THREE.BoxGeometry(name==='pistol'?.18:.34,.055,name==='sniper'?.62:(name==='shotgun'?.52:.42)),
    dark
  );
  body.rotation.x = Math.PI/2;
  g.add(body);
  const barrel = new THREE.Mesh(
    new THREE.CylinderGeometry(.014,.014,name==='pistol'?.16:(name==='sniper'?.55:.32),8),
    dark
  );
  barrel.rotation.x = Math.PI/2;
  barrel.position.z = -(name==='pistol'?.13:.31);
  g.add(barrel);
  if(name!=='pistol'){
    const mag = new THREE.Mesh(new THREE.BoxGeometry(.07,.16,.09),dark);
    mag.position.set(0,-.09,.03);
    mag.rotation.x = -.25;
    g.add(mag);
  }
  return g;
}

export function createSoldier(index, weapon='ak'){
  const root = new THREE.Group();
  const fallbackVisual = new THREE.Group();
  fallbackVisual.name = 'primitive-soldier-fallback';
  root.add(fallbackVisual);
  root.name = 'operation-ink-enemy-' + index;
  root.userData = {
    id:index, weapon, health:100, state:'patrol', stateTime:0, fireCooldown:.6+Math.random(),
    reposition:0, target:new THREE.Vector3(), lastKnown:new THREE.Vector3(),
    hitMeshes:[], dead:false, phase:Math.random()*Math.PI*2, stride:0,
    moveSpeed:.38+Math.random()*.55,pauseTimer:Math.random()*.7,justPaused:false,
    alertDelay:.18+Math.random()*.36,
    fallbackVisual, visual:null, mixer:null, actions:{}, actionName:null, groundY:0
  };

  const uniform = makeMat(0x161a1e);
  const cloth = makeMat(0x282f36);
  const skin = makeMat(0xa98a70);
  const dark = makeMat(0x050607,.55);
  const vest = makeMat(0x30363c);

  const pelvis = new THREE.Mesh(new THREE.BoxGeometry(.34,.24,.20),uniform);
  pelvis.position.y=.86;
  fallbackVisual.add(pelvis); markHit(pelvis,root,'torso');

  const torso = new THREE.Mesh(new THREE.BoxGeometry(.48,.62,.24),cloth);
  torso.position.y=1.23;
  fallbackVisual.add(torso); markHit(torso,root,'torso');

  const vestMesh = new THREE.Mesh(new THREE.BoxGeometry(.52,.40,.29),vest);
  vestMesh.position.set(0,1.25,-.015);
  fallbackVisual.add(vestMesh); markHit(vestMesh,root,'torso');

  const head = new THREE.Mesh(new THREE.SphereGeometry(.15,14,10),skin);
  head.position.y=1.68;
  fallbackVisual.add(head); markHit(head,root,'head');

  const helmet = new THREE.Mesh(new THREE.SphereGeometry(.166,14,8,0,Math.PI*2,0,Math.PI*.58),uniform);
  helmet.position.y=1.73;
  fallbackVisual.add(helmet); markHit(helmet,root,'head');

  const legGeo = new THREE.CylinderGeometry(.075,.085,.72,8);
  const armGeo = new THREE.CylinderGeometry(.06,.067,.57,8);

  const lLeg=limb(legGeo,uniform,-.11,.82,0,0,.015);
  const rLeg=limb(legGeo,uniform,.11,.82,0,0,-.015);
  fallbackVisual.add(lLeg.pivot,rLeg.pivot);
  markHit(lLeg.mesh,root,'leg'); markHit(rLeg.mesh,root,'leg');

  const lArm=limb(armGeo,cloth,-.31,1.47,0,.15,.10);
  const rArm=limb(armGeo,cloth,.31,1.47,0,-.15,-.10);
  fallbackVisual.add(lArm.pivot,rArm.pivot);
  markHit(lArm.mesh,root,'arm'); markHit(rArm.mesh,root,'arm');

  const gun = makeWeaponMesh(weapon,dark);
  gun.position.set(.10,1.27,.26);
  gun.rotation.y=Math.PI;
  fallbackVisual.add(gun);

  const muzzle = new THREE.Object3D();
  muzzle.position.set(.10,1.30,weapon==='pistol'?.48:weapon==='sniper'?.78:.61);
  fallbackVisual.add(muzzle);

  root.userData.parts={lLeg:lLeg.pivot,rLeg:rLeg.pivot,lArm:lArm.pivot,rArm:rArm.pivot,gun,muzzle,head};
  fallbackVisual.scale.setScalar(SOLDIER_HIT_PROXY_SCALE);
  root.scale.setScalar(1);
  root.traverse(o=>{ if(o.isMesh){o.castShadow=true;o.receiveShadow=true;} });
  // Upgrade asynchronously. The primitive body remains as a reliable fallback
  // until the skinned GLB and its animation clips are ready.
  queueMicrotask(()=>attachSoldierModel(root));
  return root;
}

function createPlayerWeapon(name){
  const dark = new THREE.MeshStandardMaterial({color:0x16191d,roughness:.42,metalness:.48});
  const accent = new THREE.MeshStandardMaterial({color:0x303a43,roughness:.55,metalness:.20});
  const g = new THREE.Group();
  g.name='operation-ink-player-weapon';

  const dims = {
    pistol:[.13,.12,.30], ak:[.16,.14,.62], smg:[.15,.15,.47], shotgun:[.15,.13,.70], sniper:[.14,.13,.78]
  }[name];

  const body=new THREE.Mesh(new THREE.BoxGeometry(dims[0],dims[1],dims[2]),dark);
  body.position.z=-dims[2]*.25;
  g.add(body);

  const grip=new THREE.Mesh(new THREE.BoxGeometry(.09,.22,.11),accent);
  grip.position.set(0,-.14,.03);
  grip.rotation.x=-.28;
  g.add(grip);

  const barrelLen=name==='pistol'?.14:(name==='sniper'?.48:.31);
  const barrel=new THREE.Mesh(new THREE.CylinderGeometry(.017,.017,barrelLen,10),dark);
  barrel.rotation.x=Math.PI/2;
  barrel.position.z=-(dims[2]*.5+barrelLen*.45);
  g.add(barrel);
  const muzzle=new THREE.Object3D();
  muzzle.position.z=-(dims[2]*.5+barrelLen*.95);
  g.add(muzzle);g.userData.muzzle=muzzle;

  if(name==='ak'||name==='smg'){
    const mag=new THREE.Mesh(new THREE.BoxGeometry(.09,.21,.11),accent);
    mag.position.set(0,-.16,-.10); mag.rotation.x=-.24; g.add(mag);
  }
  if(name==='sniper'){
    const scope=new THREE.Mesh(new THREE.CylinderGeometry(.04,.04,.24,12),accent);
    scope.rotation.z=Math.PI/2; scope.position.set(0,.09,-.08); g.add(scope);
  }
  if(name==='shotgun'){
    const pump=new THREE.Mesh(new THREE.BoxGeometry(.11,.09,.22),accent);
    pump.position.z=-.30; g.add(pump);
  }
  return g;
}

export class OperationInkCombat {
  constructor({scene,camera,onEvent=()=>{},onHud=()=>{}}){
    this.scene=scene; this.camera=camera; this.onEvent=onEvent; this.onHud=onHud;
    this.anchor=new THREE.Vector3(); this.enemies=[]; this.hitMeshes=[];
    this.viewForward=new THREE.Vector3(0,0,-1);this.viewRight=new THREE.Vector3(1,0,0);
    this.frontWidthRatio=FRONT_AREA.widthRatio;
    this.spawnWidthRatio=FRONT_AREA.widthRatio;
    this.weapon='ak'; this.magazines={}; this.reserve={};
    for(const [name,rule] of Object.entries(WEAPONS)){
      this.magazines[name]=rule.capacity;
      this.reserve[name]=rule.capacity*4;
    }
    this.fireCooldown=0; this.reloadTimer=0; this.triggerHeld=false;
    this.playerHealth=100; this.score=0; this.wave=0; this.alert=0;
    this.tracking=true; this.running=false; this.nextWaveTimer=0;
    this.raycaster=new THREE.Raycaster();
    this.paintballs=new PaintballEffects(scene);
    this.playerWeaponRoot=new THREE.Group();
    this.playerWeaponRoot.position.set(.24,-.25,-.53);
    this.playerWeaponRoot.rotation.set(-.06,-.07,-.02);
    this.camera.add(this.playerWeaponRoot);
    this.setWeapon('ak',true);
    loadSoldierAsset();
  }

  reset(anchor){
    this.paintballs.clear();
    for(const enemy of this.enemies) this.scene.remove(enemy);
    this.enemies.length=0; this.hitMeshes.length=0;
    this.anchor.copy(anchor); this.playerHealth=100; this.score=0; this.wave=0; this.alert=0;
    this.running=true; this.nextWaveTimer=.35;
    for(const [name,rule] of Object.entries(WEAPONS)){
      this.magazines[name]=rule.capacity;
      this.reserve[name]=rule.capacity*4;
    }
    this.setWeapon('ak',true);
    this.pushHud();
  }

  dispose(){
    this.running=false;this.triggerUp();this.paintballs.dispose();
    for(const enemy of this.enemies) this.scene.remove(enemy);
    this.camera.remove(this.playerWeaponRoot);
  }

  setTracking(active){
    this.tracking=!!active;
    if(!this.tracking) this.triggerUp();
  }

  setWeapon(name,silent=false){
    if(!WEAPONS[name]) return false;
    this.weapon=name; this.reloadTimer=0; this.triggerHeld=false;
    this.playerWeaponRoot.clear();
    const gun=createPlayerWeapon(name);
    gun.position.set(0,0,0);
    this.playerWeaponRoot.add(gun);
    this.playerMuzzle=gun.userData.muzzle;
    if(!silent) this.onEvent({type:'weapon-change',weapon:name});
    this.pushHud();
    return true;
  }

  reload(){
    const rule=WEAPONS[this.weapon], mag=this.magazines[this.weapon], reserve=this.reserve[this.weapon];
    if(this.reloadTimer>0 || mag>=rule.capacity || reserve<=0) return false;
    this.reloadTimer=rule.reload;
    this.triggerHeld=false;
    this.onEvent({type:'reload-start',weapon:this.weapon,duration:rule.reload});
    this.pushHud();
    return true;
  }

  triggerDown(){
    this.triggerHeld=true;
    this.fireOnce();
  }
  triggerUp(){ this.triggerHeld=false; }

  currentRule(){ return WEAPONS[this.weapon]; }

  pushHud(){
    this.onHud({
      weapon:this.weapon,
      label:WEAPONS[this.weapon].label,
      ammo:this.magazines[this.weapon],
      reserve:this.reserve[this.weapon],
      health:Math.ceil(this.playerHealth),
      score:this.score,
      wave:this.wave,
      reloading:this.reloadTimer>0,
      enemies:this.enemies.filter(e=>!e.userData.dead).length
    });
  }

  completeReload(){
    const rule=WEAPONS[this.weapon];
    const need=rule.capacity-this.magazines[this.weapon];
    const take=Math.min(need,this.reserve[this.weapon]);
    this.magazines[this.weapon]+=take;
    this.reserve[this.weapon]-=take;
    this.onEvent({type:'reload-complete',weapon:this.weapon});
    this.pushHud();
  }

  fireOnce(){
    if(!this.running || !this.tracking || this.playerHealth<=0 || this.reloadTimer>0 || this.fireCooldown>0) return false;
    const rule=WEAPONS[this.weapon];
    if(this.magazines[this.weapon]<=0){ this.reload(); return false; }
    this.magazines[this.weapon]--;
    this.fireCooldown=rule.interval;
    this.alert=1;
    for(const e of this.enemies){
      if(e.userData.dead) continue;
      if(e.userData.state==='patrol') this.setEnemyState(e,'suspicious');
    }

    this.playerWeaponRoot.rotation.x=-.06-rule.kick;
    setTimeout(()=>{ if(this.playerWeaponRoot) this.playerWeaponRoot.rotation.x=-.06; },55);
    this.onEvent({type:'player-shot',weapon:this.weapon});

    if(this.weapon==='shotgun'){
      for(let i=0;i<7;i++) this.castPlayerShot(rule,.026);
    }else{
      this.castPlayerShot(rule,this.weapon==='smg'?.006:this.weapon==='ak'?.0035:0);
    }
    if(this.magazines[this.weapon]===0) this.onEvent({type:'empty-soon',weapon:this.weapon});
    this.pushHud();
    return true;
  }

  castPlayerShot(rule,spread){
    const dir=new THREE.Vector3();
    this.camera.getWorldDirection(dir);
    if(spread){
      dir.x+=(Math.random()-.5)*spread;
      dir.y+=(Math.random()-.5)*spread;
      dir.z+=(Math.random()-.5)*spread;
      dir.normalize();
    }
    const origin=new THREE.Vector3();
    this.camera.getWorldPosition(origin);
    this.raycaster.set(origin,dir);
    this.raycaster.far=rule.range;
    const hits=this.raycaster.intersectObjects(this.hitMeshes,false)
      .filter(h=>!h.object.userData.enemyRoot?.userData.dead);
    const end=origin.clone().addScaledVector(dir,rule.range);
    if(hits.length)end.copy(hits[0].point);
    if(dir.y<-.001){
      const distance=(this.anchor.y-origin.y)/dir.y;
      if(distance>0 && distance<origin.distanceTo(end))end.copy(origin).addScaledVector(dir,distance);
    }
    const muzzle=this.playerMuzzle.getWorldPosition(new THREE.Vector3());
    this.paintballs.fire(muzzle,end.sub(muzzle).normalize(),{
      team:'player',weapon:this.weapon,damage:rule.damage,range:rule.range
    });
  }

  tracePaintball(ball,end){
    const distance=ball.position.distanceTo(end);
    if(distance<1e-8)return null;
    this.raycaster.set(ball.position,ball.direction);this.raycaster.far=distance;
    let hit=null;
    if(ball.team==='player'){
      const intersection=this.raycaster.intersectObjects(this.hitMeshes,false)
        .find(h=>!h.object.userData.enemyRoot?.userData.dead);
      if(intersection)hit={...intersection,type:'enemy',root:intersection.object.userData.enemyRoot,zone:intersection.object.userData.hitZone||'torso'};
    }else{
      const phone=this.camera.getWorldPosition(new THREE.Vector3());
      const point=this.raycaster.ray.intersectSphere(new THREE.Sphere(phone,.17),new THREE.Vector3());
      if(point && point.distanceTo(ball.position)<=distance)hit={type:'player',point,distance:point.distanceTo(ball.position)};
    }
    if(end.y<=this.anchor.y && ball.position.y>this.anchor.y){
      const t=(this.anchor.y-ball.position.y)/(end.y-ball.position.y),floorDistance=t*distance;
      if(!hit || floorDistance<hit.distance)hit={type:'ground',point:ball.position.clone().lerp(end,t),normal:new THREE.Vector3(0,1,0),distance:floorDistance};
    }
    return hit;
  }

  paintballImpact(ball,hit){
    if(hit.type==='player'){
      // Keep the existing invincible test mode; paint briefly marks the visor.
      this.playerHealth=100;
      this.onEvent({type:'player-hit',damage:0,health:100,source:ball.origin.clone(),color:ball.color,invincible:true});
      return;
    }
    let point=hit.point.clone(),normal=ball.direction.clone().negate(),parent=null;
    if(hit.type==='enemy'){
      const root=hit.root;
      if(root.userData.dead || !root.parent)return;
      parent=hit.object;
      // Hit proxies decide gameplay; refine the paint position against the
      // visible skin so a stain cannot end up hidden inside a cartoon body.
      if(root.userData.visual){
        root.updateMatrixWorld(true);
        root.userData.visual.traverse(obj=>{if(obj.isSkinnedMesh)obj.computeBoundingSphere();});
        const surfaceRay=new THREE.Raycaster(point.clone().addScaledVector(ball.direction,-.8),ball.direction,0,1.6);
        const surface=surfaceRay.intersectObject(root.userData.visual,true).find(h=>{
          for(let obj=h.object;obj && obj!==root;obj=obj.parent)if(!obj.visible)return false;
          return true;
        });
        if(surface){
          point.copy(surface.point);parent=surface.object;
          if(surface.face){
            const vertices=['a','b','c'].map(key=>surface.object.getVertexPosition(surface.face[key],new THREE.Vector3()).applyMatrix4(surface.object.matrixWorld));
            normal.subVectors(vertices[2],vertices[1]).cross(vertices[0].sub(vertices[1])).normalize();
            if(normal.dot(ball.direction)>0)normal.negate();
          }
          if(surface.object.isSkinnedMesh){
            let nearest=Infinity;
            root.userData.visual.traverse(obj=>{
              if(!obj.isBone || /Root|PoleTarget/.test(obj.name))return;
              const distance=obj.getWorldPosition(new THREE.Vector3()).distanceToSquared(point);
              if(distance<nearest){nearest=distance;parent=obj;}
            });
          }
        }else parent=root;
      }
      this.paintballs.splat(point,normal,ball.color,parent);
      const mult=hit.zone==='head' && ball.weapon==='sniper'?2:(HIT_MULTIPLIER[hit.zone]||1);
      const damage=ball.damage*mult;root.userData.health-=damage;root.userData.lastKnown.copy(ball.origin);
      this.setEnemyState(root,'combat');
      this.onEvent({type:'enemy-hit',zone:hit.zone,weapon:ball.weapon,damage,position:point,color:ball.color});
      if(root.userData.health<=0)this.killEnemy(root);
    }else{
      this.paintballs.splat(point,hit.normal,ball.color);
      this.onEvent({type:'world-hit',weapon:ball.weapon,position:point,color:ball.color});
    }
  }

  killEnemy(root){
    if(root.userData.dead) return;
    root.userData.dead=true; root.userData.health=0; root.userData.state='dead';
    this.score+=100 + this.wave*15;
    root.userData.hitMeshes.forEach(m=>{
      const i=this.hitMeshes.indexOf(m); if(i>=0) this.hitMeshes.splice(i,1);
    });
    if(root.userData.mixer){
      setSoldierAction(root,'Death',.08);
    }else{
      root.rotation.z=(Math.random()>.5?1:-1)*1.42;
      root.position.y=root.userData.groundY+.05;
    }
    this.onEvent({type:'enemy-dead',position:root.position.clone(),weapon:root.userData.weapon});
    this.pushHud();
    if(this.enemies.every(e=>e.userData.dead)) this.nextWaveTimer=1.7;
  }

  setEnemyState(enemy,state){
    if(enemy.userData.dead || enemy.userData.state===state) return;
    enemy.userData.state=state;
    enemy.userData.stateTime=0;
    if(state==='combat') enemy.userData.reposition=0;
    this.onEvent({type:'enemy-state',state,enemy:enemy.userData.id});
  }

  spawnWave(){
    this.wave++;
    const count=Math.min(8,3+this.wave);
    const choices=['ak','pistol','smg','ak','shotgun'];
    if(this.wave>=3) choices.push('sniper');

    this.enemies=this.enemies.filter(e=>{
      if(!e.userData.dead) return true;
      this.scene.remove(e);
      return false;
    });

    const player=new THREE.Vector3();
    this.camera.getWorldPosition(player);
    this.updateFrontFrame();

    for(let i=0;i<count;i++){
      const weapon=choices[(i+this.wave)%choices.length];
      const soldier=createSoldier(this.wave*100+i,weapon);
      soldier.position.copy(this.randomFrontPoint(player));
      this.facePhone(soldier,player);
      soldier.userData.groundY=this.anchor.y;
      soldier.userData.target.copy(soldier.position);
      soldier.userData.lastKnown.copy(player);
      this.scene.add(soldier);
      this.enemies.push(soldier);
      this.hitMeshes.push(...soldier.userData.hitMeshes);
    }
    this.alert=0;
    this.onEvent({type:'wave-start',wave:this.wave,count});
    this.pushHud();
  }

  chooseReposition(enemy,player){
    const u=enemy.userData;
    u.target.copy(this.randomFrontPoint(player,enemy));
    u.reposition=.9+Math.random()*2.1;
    u.moveSpeed=.38+Math.random()*.55;
  }

  updateFrontFrame(){
    const forward=this.camera.getWorldDirection(new THREE.Vector3());forward.y=0;
    // Keep the last horizontal heading when the phone points straight down.
    if(forward.lengthSq()>.01)this.viewForward.copy(forward).normalize();
    this.viewRight.set(-this.viewForward.z,0,this.viewForward.x);
    if(Number.isFinite(this.camera.fov) && Number.isFinite(this.camera.aspect)){
      this.spawnWidthRatio=clamp(Math.tan(THREE.MathUtils.degToRad(this.camera.fov/2))*this.camera.aspect*.9,.20,FRONT_AREA.widthRatio);
    }
  }

  frontCoordinates(point,player){
    const dx=point.x-player.x,dz=point.z-player.z;
    return {depth:dx*this.viewForward.x+dz*this.viewForward.z,side:dx*this.viewRight.x+dz*this.viewRight.z};
  }

  inFrontArea(point,player){
    const {depth,side}=this.frontCoordinates(point,player);
    return depth>=FRONT_AREA.near-1e-6 && depth<=FRONT_AREA.far+1e-6 && Math.abs(side)<=depth*this.frontWidthRatio+1e-6;
  }

  clampFrontPoint(point,player){
    const local=this.frontCoordinates(point,player),depth=clamp(local.depth,FRONT_AREA.near,FRONT_AREA.far);
    const side=clamp(local.side,-depth*this.frontWidthRatio,depth*this.frontWidthRatio);
    return point.copy(player).addScaledVector(this.viewForward,depth).addScaledVector(this.viewRight,side).setY(this.anchor.y);
  }

  randomFrontPoint(player,enemy=null){
    let best=null,bestClearance=-Infinity;
    for(let attempt=0;attempt<12;attempt++){
      let point;
      if(enemy){
        const angle=Math.random()*Math.PI*2,step=.55+Math.random()*1.15;
        point=enemy.position.clone().addScaledVector(this.viewRight,Math.cos(angle)*step).addScaledVector(this.viewForward,Math.sin(angle)*step);
        this.clampFrontPoint(point,player);
      }else{
        const depth=2.5+Math.random()*2.7,side=(Math.random()*2-1)*depth*this.spawnWidthRatio*.85;
        point=player.clone().addScaledVector(this.viewForward,depth).addScaledVector(this.viewRight,side).setY(this.anchor.y);
      }
      if(enemy && flatDistance(point,enemy.position)<.3)continue;
      let clearance=Infinity;
      for(const other of this.enemies){
        if(other===enemy || other.userData.dead)continue;
        clearance=Math.min(clearance,flatDistance(point,other.position),flatDistance(point,other.userData.target));
      }
      if(clearance>bestClearance){best=point;bestClearance=clearance;}
      if(clearance>=FRONT_AREA.separation)return point;
    }
    return best || this.clampFrontPoint(enemy?enemy.position.clone():player.clone(),player);
  }

  keepEnemyInFront(enemy,player){
    if(this.inFrontArea(enemy.position,player))return;
    const {depth}=this.frontCoordinates(enemy.position,player);
    const screen=enemy.position.clone().add(new THREE.Vector3(0,.6,0)).project(this.camera);
    // A phone turn can leave an enemy behind the view. Re-enter ahead while
    // out of view; never run around the user's back to find the new sector.
    if(depth<=0 || Math.abs(screen.x)>1.2 || Math.abs(screen.y)>1.2)enemy.position.copy(this.randomFrontPoint(player));
    else this.clampFrontPoint(enemy.position,player);
    enemy.userData.target.copy(enemy.position);enemy.userData.reposition=0;
  }

  wanderEnemy(enemy,player,dt,speedMultiplier=1){
    const u=enemy.userData;
    if(u.pauseTimer>0){u.pauseTimer=Math.max(0,u.pauseTimer-dt);return 0;}
    if(u.reposition<=0 || flatDistance(enemy.position,u.target)<.10 || !this.inFrontArea(u.target,player)){
      if(!u.justPaused && Math.random()<.32){u.pauseTimer=.2+Math.random()*.85;u.justPaused=true;return 0;}
      this.chooseReposition(enemy,player);u.justPaused=false;
    }
    // A small separation check prevents soldiers marching through each other.
    const next=enemy.position.clone(),delta=u.target.clone().sub(next);delta.y=0;
    const distance=delta.length();if(distance<.03)return 0;
    next.addScaledVector(delta,Math.min(distance,u.moveSpeed*speedMultiplier*dt)/distance);
    if(this.enemies.some(other=>other!==enemy && !other.userData.dead && flatDistance(next,other.position)<FRONT_AREA.separation && flatDistance(next,other.position)<flatDistance(enemy.position,other.position))){
      u.reposition=0;u.pauseTimer=.1+Math.random()*.25;return 0;
    }
    return this.moveToward(enemy,u.target,u.moveSpeed*speedMultiplier,dt);
  }

  enemyShoot(enemy,player){
    const u=enemy.userData, rule=ENEMY_WEAPONS[u.weapon]||ENEMY_WEAPONS.ak;
    const muzzle=new THREE.Vector3();
    u.parts.muzzle.getWorldPosition(muzzle);

    // Aim at the tracked phone. A moving player can dodge a travelling ball.
    const eye=player.clone();
    const distance=muzzle.distanceTo(eye);
    const accuracy=clamp(.92-distance*.04,.58,.86);
    const hit=Math.random()<accuracy;
    const forward=eye.clone().sub(muzzle).normalize();
    const right=new THREE.Vector3(0,1,0).cross(forward);
    if(right.lengthSq()<.001)right.set(1,0,0);else right.normalize();
    const up=forward.clone().cross(right).normalize(),angle=Math.random()*Math.PI*2;
    const spread=hit?Math.random()*.045:.26+Math.random()*.18;
    const target=eye.clone().addScaledVector(right,Math.cos(angle)*spread).addScaledVector(up,Math.sin(angle)*spread);
    this.paintballs.fire(muzzle,target.sub(muzzle).normalize(),{team:'enemy',weapon:u.weapon,range:distance+2,speed:20});
    this.onEvent({type:'enemy-shot',weapon:u.weapon,position:muzzle.clone(),hit});
    u.fireCooldown=rule.gap*(.88+Math.random()*.45);
  }

  moveToward(enemy,target,speed,dt){
    const dx=target.x-enemy.position.x, dz=target.z-enemy.position.z;
    const d=Math.hypot(dx,dz);
    if(d<.03) return 0;
    const step=Math.min(d,speed*dt);
    enemy.position.x+=dx/d*step;
    enemy.position.z+=dz/d*step;
    enemy.userData.stride+=step*8.5;
    return step;
  }

  facePhone(enemy,player){
    const dx=player.x-enemy.position.x;
    const dz=player.z-enemy.position.z;
    if(Math.hypot(dx,dz)>.001) enemy.rotation.y=Math.atan2(dx,dz);
  }

  animateEnemy(enemy,dt,moving){
    const u=enemy.userData,p=u.parts;

    if(u.mixer){
      if(u.dead){
        setSoldierAction(enemy,'Death',.08);
        u.mixer.update(dt);
        return;
      }
      let clip='Idle';
      if(u.state==='combat'){
        clip=moving>0 ? 'Walk_Shoot' : 'Idle_Shoot';
      }else if(u.state==='suspicious'){
        clip='Idle_Shoot';
      }else if(moving>0){
        clip='Walk';
      }
      setSoldierAction(enemy,clip);
      const act=u.actions?.[u.actionName];
      if(act && (clip==='Walk' || clip==='Walk_Shoot'))act.timeScale=clamp(moving/Math.max(dt,.001)/.75,.45,1.35);
      u.mixer.update(dt);
      return;
    }

    if(u.dead) return;
    const s=Math.sin(u.stride+u.phase);
    const amp=moving?.62:.07;
    p.lLeg.rotation.x=s*amp;
    p.rLeg.rotation.x=-s*amp;
    if(u.state==='combat'){
      p.lArm.rotation.x=-1.02;
      p.rArm.rotation.x=-1.08;
      p.lArm.rotation.z=.17;
      p.rArm.rotation.z=-.17;
    }else{
      p.lArm.rotation.x=-s*amp*.65;
      p.rArm.rotation.x=s*amp*.65;
    }
    p.head.rotation.y=Math.sin(performance.now()*.001+u.phase)*.05;
  }

  updateEnemy(enemy,dt,player){
    const u=enemy.userData;
    if(u.dead){
      if(u.mixer) this.animateEnemy(enemy,dt,0);
      return;
    }
    // Floor lock: enemy roots never inherit animation/root-motion Y drift.
    enemy.position.y=Number.isFinite(u.groundY)?u.groundY:this.anchor.y;
    this.keepEnemyInFront(enemy,player);
    u.stateTime+=dt; u.fireCooldown=Math.max(0,u.fireCooldown-dt); u.reposition-=dt;
    const dist=flatDistance(enemy.position,player);
    let moving=0;

    if(this.alert && u.state==='patrol'){
      this.setEnemyState(enemy,'suspicious');
    }

    if(u.state==='patrol'){
      moving=this.wanderEnemy(enemy,player,dt,.7);
      if(dist<4.9) this.setEnemyState(enemy,'suspicious');
    }else if(u.state==='suspicious'){
      if(u.stateTime>=u.alertDelay) this.setEnemyState(enemy,'combat');
    }else if(u.state==='combat'){
      u.lastKnown.copy(player);
      // Combat movement is independent from aiming: strafe/reposition while
      // the torso remains pointed at the tracked phone camera.
      moving=this.wanderEnemy(enemy,player,dt);
      if(dist>8.3) this.setEnemyState(enemy,'search');
    }else if(u.state==='search'){
      moving=this.wanderEnemy(enemy,player,dt,.8);
      if(this.tracking)this.setEnemyState(enemy,this.alert?'combat':'patrol');
    }
    // Keep every live state facing the current phone position, including
    // patrol/search and strafing. Movement must never overwrite aim yaw.
    this.facePhone(enemy,player);
    this.animateEnemy(enemy,dt,moving);
    if(u.state==='combat' && flatDistance(enemy.position,player)<7.2 && u.fireCooldown<=0){
      this.enemyShoot(enemy,player);
    }
  }

  updateFx(dt){
    this.paintballs.update(dt,(ball,end)=>this.tracePaintball(ball,end),(ball,hit)=>this.paintballImpact(ball,hit),this.running && this.tracking);
  }

  update(dt){
    dt=Math.min(.05,Math.max(0,dt||0));
    this.updateFx(dt);
    // A stale camera pose is not a valid target. Pause AI, wave/reload timers
    // and firing until XR tracking recovers; existing effects can fade out.
    if(!this.running || !this.tracking) return;
    this.updateFrontFrame();
    this.fireCooldown=Math.max(0,this.fireCooldown-dt);
    if(this.reloadTimer>0){
      this.reloadTimer-=dt;
      if(this.reloadTimer<=0){this.reloadTimer=0;this.completeReload();}
    }
    const rule=WEAPONS[this.weapon];
    if(this.triggerHeld && rule.automatic && this.fireCooldown<=0) this.fireOnce();

    if(this.nextWaveTimer>0){
      this.nextWaveTimer-=dt;
      if(this.nextWaveTimer<=0 && this.running) this.spawnWave();
    }

    const player=new THREE.Vector3();
    // Use the actual XR camera pose, including its tracked height, so enemy
    // bodies and bullet traces remain focused on the phone as the user moves.
    this.camera.getWorldPosition(player);
    for(const enemy of this.enemies) this.updateEnemy(enemy,dt,player);
  }
}
