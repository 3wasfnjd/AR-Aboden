import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

// The model adapter is deliberately independent of targets, scoring and AR.
export const BOOTH_URL = './assets/gallery/carnival.glb';
export const FRONT_Z = 1.78;
const brass = new THREE.MeshStandardMaterial({color:0xbc8c45,roughness:.38,metalness:.55});
const green = new THREE.MeshStandardMaterial({color:0x18382f,roughness:.65,metalness:.1});
const ivory = new THREE.MeshStandardMaterial({color:0xf3e7c8,roughness:.65});
const red = new THREE.MeshStandardMaterial({color:0xa33728,roughness:.5,metalness:.12});
function box(parent,w,h,d,mat,x,y,z){const o=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),mat);o.position.set(x,y,z);parent.add(o);return o;}
function badgeTexture(){const canvas=document.createElement('canvas');canvas.width=1024;canvas.height=160;const c=canvas.getContext('2d');c.fillStyle='#15362c';c.fillRect(0,0,1024,160);c.strokeStyle='#d5af66';c.lineWidth=4;c.strokeRect(10,10,1004,140);c.fillStyle='#f1dfb9';c.font='bold 64px Tahoma, Arial';c.textAlign='center';c.textBaseline='middle';c.fillText('رماية عبودين',512,75);const tex=new THREE.CanvasTexture(canvas);tex.colorSpace=THREE.SRGBColorSpace;return tex;}
function circle(parent,r,mat,z){const mesh=new THREE.Mesh(new THREE.CircleGeometry(r,40),mat);mesh.position.z=z;parent.add(mesh);return mesh;}

export async function createStage(onProgress){
 const loader=new GLTFLoader();
 const [gltf,targetGLTF,canGLTF]=await Promise.all([loader.loadAsync(BOOTH_URL,onProgress),loader.loadAsync('./assets/gallery/duck-target.glb'),loader.loadAsync('./assets/gallery/tin-can.glb')]);
 const raw=gltf.scene;raw.updateMatrixWorld(true);
 let source;targetGLTF.scene.traverse(o=>{if(o.isMesh&&!source)source=o;});
 if(!source)throw new Error('تعذر تحميل هدف البطّة.');
 // Targets are separate assets: replacing the booth never changes hit logic.
 const duckGeometry=source.geometry.clone();
 const duckMaterial=source.material.clone();duckMaterial.side=THREE.DoubleSide;duckMaterial.transparent=false;duckMaterial.alphaTest=.45;duckMaterial.depthWrite=true;
 // Tin can: already close to real can proportions with its base near y=0 —
 // just centred on X/Z and scaled to the target stack height (canH below).
 const canRaw=canGLTF.scene;canRaw.updateMatrixWorld(true);
 const canBox=new THREE.Box3().setFromObject(canRaw),canSize=canBox.getSize(new THREE.Vector3()),canCenter=canBox.getCenter(new THREE.Vector3());
 canRaw.position.set(-canCenter.x,-canBox.min.y,-canCenter.z);
 canRaw.traverse(o=>{if(o.isMesh){o.castShadow=false;o.receiveShadow=false;}});
 const canTemplate=new THREE.Group();canTemplate.add(canRaw);canTemplate.scale.setScalar(.22/canSize.y);
 const root=new THREE.Group();root.name='gallery-stage';const model=new THREE.Group();model.name='replaceable-booth';root.add(model);model.add(raw);
 raw.traverse(o=>{if(o.isMesh){o.castShadow=false;o.receiveShadow=false;for(const m of (Array.isArray(o.material)?o.material:[o.material])){if(m.name==='color_texture'){m.transparent=false;m.alphaTest=.45;m.depthWrite=true;}if(m.emissiveIntensity>1)m.emissiveIntensity=1;}}});
 for(const name of ['duckk','duckk1','duckk2']){const o=raw.getObjectByName(name);if(o)o.visible=false;}
 const b=new THREE.Box3().setFromObject(raw),size=b.getSize(new THREE.Vector3()),center=b.getCenter(new THREE.Vector3());
 raw.position.set(-center.x,-b.min.y,-center.z);model.scale.setScalar(3.8/size.x);model.rotation.y=Math.PI;
 const mixer=new THREE.AnimationMixer(raw);for(const clip of gltf.animations)mixer.clipAction(clip).play();
 const rack=new THREE.Group();rack.name='independent-target-rack';root.add(rack);
 // A clear foreground counter keeps the scenery from masking small targets.
 box(rack,3.22,.16,.32,green,0,.55,FRONT_Z);
 box(rack,3.26,.035,.36,brass,0,.645,FRONT_Z);
 box(rack,3.1,.05,.09,brass,0,1.19,FRONT_Z-.025);
 for(const x of [-1.53,1.53]){box(rack,.09,1.48,.10,green,x,.78,FRONT_Z);box(rack,.13,.08,.14,brass,x,1.49,FRONT_Z);for(const y of [.45,.83,1.20]){const screw=new THREE.Mesh(new THREE.SphereGeometry(.025,10,8),brass);screw.position.set(x,y,FRONT_Z+.06);rack.add(screw);}}
 const sign=new THREE.Mesh(new THREE.PlaneGeometry(1.05,.164),new THREE.MeshBasicMaterial({map:badgeTexture(),side:THREE.DoubleSide}));sign.position.set(0,.54,FRONT_Z+.166);rack.add(sign);
 const targets=[];
 // Fixed discs split into a left and right cluster (instead of one row),
 // leaving the centre clear for the can stack below.
 const discX=[-1.35,-.85,.85,1.35];
 for(let i=0;i<discX.length;i++){
  const pivot=new THREE.Group();pivot.position.set(discX[i],.67,FRONT_Z+.015);rack.add(pivot);
  box(pivot,.034,.13,.035,brass,0,.065,0);
  const plate=new THREE.Group();plate.position.y=.25;pivot.add(plate);
  const rim=new THREE.Mesh(new THREE.CylinderGeometry(.173,.173,.045,40),brass);rim.rotation.x=Math.PI/2;plate.add(rim);
  circle(plate,.155,ivory,.025);circle(plate,.121,red,.026);circle(plate,.09,ivory,.027);circle(plate,.052,red,.028);circle(plate,.011,brass,.03);
  const target={kind:'fixed',index:i,pivot,hitObject:plate,cooldown:0,fall:0,baseX:pivot.position.x,flash:0};plate.userData.target=target;targets.push(target);
 }
 for(let i=0;i<3;i++){
  const pivot=new THREE.Group();pivot.position.set((i-1)*1.03,1.21,FRONT_Z);rack.add(pivot);
  const mesh=new THREE.Mesh(duckGeometry,duckMaterial);pivot.add(mesh);
  const target={kind:'moving',index:i,pivot,hitObject:mesh,cooldown:0,fall:0,baseX:pivot.position.x,flash:0};mesh.userData.target=target;targets.push(target);
 }
 // Three-can stack, dead centre — a bonus target always up regardless of
 // the fixed/moving mode toggle. Each can is its own pivot rooted at its
 // own base so the existing fold-over hit animation tips it convincingly,
 // and the three sit directly on top of one another.
 const canH=.22;
 for(let i=0;i<3;i++){
  const pivot=new THREE.Group();pivot.position.set(0,.67+canH*i,FRONT_Z+.02);rack.add(pivot);
  const mesh=canTemplate.clone(true);pivot.add(mesh);
  const target={kind:'can',index:i,pivot,hitObject:mesh,cooldown:0,fall:0,baseX:0,flash:0};mesh.traverse(o=>{if(o.isMesh)o.userData.target=target;});targets.push(target);
 }
 const particles=[];const particleGeo=new THREE.SphereGeometry(.012,6,4);const particleMat=new THREE.MeshBasicMaterial({color:0xffd883});
 const sparkPool=Array.from({length:30},()=>{const p=new THREE.Mesh(particleGeo,particleMat);p.visible=false;root.add(p);return p;});
 function burst(worldPoint){const point=root.worldToLocal(worldPoint.clone());for(let i=0;i<6;i++){const mesh=sparkPool.find(p=>!p.visible);if(!mesh)break;mesh.visible=true;mesh.position.copy(point);particles.push({mesh,life:.25+Math.random()*.15,v:new THREE.Vector3((Math.random()-.5)*.5,Math.random()*.6,.3+Math.random()*.3)});}}
 function setMode(mode){for(const t of targets){t.pivot.visible=t.kind==='can'?true:(mode==='mixed'||t.kind===mode);t.cooldown=0;t.fall=0;t.pivot.rotation.x=0;}}
 function reset(){for(const t of targets){t.cooldown=0;t.fall=0;t.pivot.rotation.x=0;}for(const p of particles)p.mesh.visible=false;particles.length=0;}
 function update(dt,time,animate=true){
  if(animate)mixer.update(dt);
  for(const t of targets){
   if(!t.pivot.visible)continue;
   if(t.kind==='moving'&&animate)t.pivot.position.x=((time*.48+t.index*1.04)%3.12)-1.56;
   if(t.cooldown>0)t.cooldown=Math.max(0,t.cooldown-dt);
   const angle=t.cooldown>.36?-Math.PI*.49:0;t.fall=THREE.MathUtils.damp(t.fall,angle,angle?15:10,dt);t.pivot.rotation.x=t.fall;
  }
  for(let i=particles.length-1;i>=0;i--){const p=particles[i];p.life-=dt;if(p.life<=0){p.mesh.visible=false;particles.splice(i,1);continue;}p.v.y-=1.8*dt;p.mesh.position.addScaledVector(p.v,dt);p.mesh.scale.setScalar(Math.min(1,p.life*6));}
 }
 function shoot(raycaster){
  // Targets fold away on impact and cannot be scored again during reset.
  root.updateMatrixWorld(true);
  const localOrigin=root.worldToLocal(raycaster.ray.origin.clone());if(localOrigin.z<FRONT_Z)return null;
  const active=targets.filter(t=>t.pivot.visible&&t.cooldown===0&&Math.abs(t.fall)<.16);
  const hit=raycaster.intersectObjects(active.map(t=>t.hitObject),true)[0];if(!hit)return null;
  let o=hit.object;while(o&&!o.userData.target)o=o.parent;const t=o?.userData.target;if(!t)return null;
  const p=t.hitObject.worldToLocal(hit.point.clone());const bull=t.kind==='fixed'&&Math.hypot(p.x,p.y)<.052;
  t.cooldown=t.kind==='fixed'?2.2:t.kind==='can'?1.6:2.7;burst(hit.point);
  return{points:t.kind==='moving'?35:t.kind==='can'?20:bull?25:10,bull,kind:t.kind};
 }
 return{root,targets,mixer,update,shoot,setMode,reset};
}
