import * as THREE from 'three';
import {
  InteractiveWaterHeightfield, PoolCausticsPass,
  createPoolInteriorMesh, createPoolInteriorMaterial,
  createInteractiveWaterSurfaceMaterial, createInteractiveWaterSurfaceMesh,
  createPoolSphereMaterial,
} from 'https://cdn.jsdelivr.net/gh/scottstts/Threejs-Awesome-Graphics-Agent-Skills@d1cb23dcce6ea8ee4a60f6159daeb79d4b511dba/skills/threejs-water-optics/examples/interactive-pool-volume/water-volume-system.js';

export const QUALITY={light:{resolution:128,segments:80,caustics:256,causticHz:20},fine:{resolution:256,segments:128,caustics:512,causticHz:30}};
const RADIUS=.23;
const INITIAL=new THREE.Vector3(-.35,-.12,.12);

// Stand-alone studio reflections, NOT a captured view of the real room.
function textures(){
  const tile=document.createElement('canvas');tile.width=tile.height=256;
  const c=tile.getContext('2d');c.fillStyle='#d1dfdc';c.fillRect(0,0,256,256);
  for(let y=0;y<16;y++)for(let x=0;x<16;x++){
    c.fillStyle=['#84b3b6','#91bdbe','#a7cccc','#b3d1d0'][(x*3+y*7)%4];
    c.fillRect(x*16+1,y*16+1,14,14);
  }
  const tiles=new THREE.CanvasTexture(tile);tiles.wrapS=tiles.wrapT=THREE.RepeatWrapping;
  tiles.colorSpace=THREE.NoColorSpace;
  const faces=Array.from({length:6},(_,i)=>{
    const face=document.createElement('canvas');face.width=face.height=128;
    const ctx=face.getContext('2d'),g=ctx.createLinearGradient(0,0,0,128);
    g.addColorStop(0,i===3?'#74878b':'#d8e5ed');g.addColorStop(1,i===2?'#eef5f7':'#738c98');
    ctx.fillStyle=g;ctx.fillRect(0,0,128,128);
    if(i===0||i===4){ctx.fillStyle='#f8fcff';ctx.fillRect(22,8,35,78);}
    return face;
  });
  const sky=new THREE.CubeTexture(faces);sky.colorSpace=THREE.NoColorSpace;
  sky.minFilter=sky.magFilter=THREE.LinearFilter;sky.generateMipmaps=false;sky.needsUpdate=true;
  return {tiles,sky};
}

export function createWaterPool(renderer,quality='light'){
  const q=QUALITY[quality]||QUALITY.light;
  const group=new THREE.Group();group.name='Water AR laboratory anchor';
  const space=new THREE.Group();space.position.y=1.08;group.add(space);
  const {tiles,sky}=textures();
  let simulation,caustics,dead=false,accumulator=0,causticTime=1,steps=0;
  const inverse=new THREE.Matrix4(),eye=new THREE.Vector3(),old=new THREE.Vector3();
  const savedViewport=new THREE.Vector4(),savedScissor=new THREE.Vector4(),savedColor=new THREE.Color();
  // Offscreen simulation must never clear or overwrite XR8's camera framebuffer.
  function isolated(fn){
    const target=renderer.getRenderTarget(),auto=renderer.autoClear,scissor=renderer.getScissorTest();
    const alpha=renderer.getClearAlpha(),xr=renderer.xr.enabled;
    renderer.getViewport(savedViewport);renderer.getScissor(savedScissor);renderer.getClearColor(savedColor);
    renderer.autoClear=true;renderer.xr.enabled=false;renderer.setScissorTest(false);
    try{return fn();}finally{
      renderer.setRenderTarget(target);renderer.setViewport(savedViewport);renderer.setScissor(savedScissor);
      renderer.setScissorTest(scissor);renderer.setClearColor(savedColor,alpha);renderer.autoClear=auto;renderer.xr.enabled=xr;
    }
  }
  try{
    isolated(()=>{
      simulation=new InteractiveWaterHeightfield(renderer,{resolution:q.resolution,damping:.995,waveSpeed:2});
      renderer.setRenderTarget(simulation.textureA);
      const gl=renderer.getContext();
      if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE)throw new Error('الجهاز لا يدعم هدف الماء Half-Float. جرّب متصفحًا آخر.');
    });
  }catch(error){simulation?.dispose();tiles.dispose();sky.dispose();throw error;}
  const light=new THREE.Vector3(2,3,-1).normalize();
  caustics=new PoolCausticsPass(renderer,{waterTexture:simulation.texture,resolution:q.caustics,sunDirection:light,sphereCenter:INITIAL,sphereRadius:RADIUS});
  caustics.mesh.geometry.dispose();caustics.mesh.geometry=new THREE.PlaneGeometry(2,2,q.segments,q.segments);
  // Avoid division by zero in a degenerate projected caustic triangle.
  caustics.material.fragmentShader=caustics.material.fragmentShader.replace('oldArea / newArea * 0.2','min(4.0, oldArea / max(newArea, 0.0000001) * 0.2)');
  const opts={waterTexture:simulation.texture,causticTexture:caustics.texture,tileTexture:tiles,skybox:sky,sunDirection:light,sphereCenter:INITIAL,sphereRadius:RADIUS};
  const poolMaterial=createPoolInteriorMaterial(opts),waterMaterial=createInteractiveWaterSurfaceMaterial(opts);
  const sphereMaterial=createPoolSphereMaterial(opts);
  // The upstream sphere shader used world coordinates. Keep its optical math in
  // pool-local space, like the water/interior, after AR scale/rotation/translation.
  sphereMaterial.uniforms.poolInverse={value:inverse};
  sphereMaterial.vertexShader='uniform mat4 poolInverse;\n'+sphereMaterial.vertexShader.replace('vPosition = worldPosition.xyz;','vPosition = (poolInverse * worldPosition).xyz;');
  const interior=createPoolInteriorMesh({material:poolMaterial});
  const water=createInteractiveWaterSurfaceMesh({width:2,depth:2,segments:q.segments,material:waterMaterial});
  const sphere=new THREE.Mesh(new THREE.SphereGeometry(RADIUS,28,20),sphereMaterial);sphere.position.copy(INITIAL);
  space.add(interior,water,sphere);
  const shellMaterial=new THREE.MeshStandardMaterial({color:0xe4e4da,roughness:.55,metalness:.06});
  function block(x,y,z,w,h,d){const m=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),shellMaterial);m.position.set(x,y,z);space.add(m);}
  // Leave a small gap behind the shader-defined interior to avoid coplanar z-fighting.
  block(0,-1.05,0,2.20,.06,2.20);
  block(-1.06,-.43,0,.08,1.22,2.20);block(1.06,-.43,0,.08,1.22,2.20);
  block(0,-.43,-1.06,2.04,1.22,.08);block(0,-.43,1.06,2.04,1.22,.08);
  block(-1.04,.18,0,.12,.06,2.20);block(1.04,.18,0,.12,.06,2.20);
  block(0,.18,-1.04,2,.06,.12);block(0,.18,1.04,2,.06,.12);
  const materials=[poolMaterial,waterMaterial,sphereMaterial];
  const drops=[];
  old.copy(sphere.position);
  function sync(camera){
    group.updateMatrixWorld(true);inverse.copy(space.matrixWorld).invert();
    camera.getWorldPosition(eye).applyMatrix4(inverse);
    for(const m of materials){m.uniforms.water.value=simulation.texture;m.uniforms.sphereCenter.value.copy(sphere.position);m.uniforms.eye.value.copy(eye);}
    caustics.setSphere(sphere.position,RADIUS,true);
  }
  function reset(){
    drops.length=0;accumulator=0;old.copy(INITIAL);sphere.position.copy(INITIAL);
    isolated(()=>{simulation.clear();simulation.moveSphere(new THREE.Vector3(INITIAL.x,2,INITIAL.z),sphere.position,RADIUS,{width:2,depth:2,displacementScale:.65});simulation.updateNormals();});causticTime=1;
  }
  function step(dt,camera){
    if(dead)return;
    accumulator+=Math.min(.05,Math.max(0,dt));causticTime+=dt;
    isolated(()=>{
      let count=0;
      while(drops.length&&count++<8){const p=drops.shift();simulation.addDrop(p.x,p.z,p.radius,p.strength);}
      if(old.distanceToSquared(sphere.position)>1e-9){simulation.moveSphere(old,sphere.position,RADIUS,{width:2,depth:2,displacementScale:.65});old.copy(sphere.position);}
      let substeps=0;
      while(accumulator>=1/120&&substeps++<6){simulation.stepSimulation();accumulator-=1/120;steps++;}
      if(substeps||count)simulation.updateNormals();
      sync(camera);
      if(causticTime>=1/q.causticHz){caustics.update(simulation.texture);causticTime=0;}
    });
  }
  function addDrop(x,z,strength=.022,radius=.035){
    if(dead||!Number.isFinite(x+z)||Math.abs(x)>.97||Math.abs(z)>.97)return;
    if(drops.length>=24)drops.shift();
    drops.push({x,z,strength:THREE.MathUtils.clamp(strength,-.035,.035),radius});
  }
  function dispose(){
    if(dead)return;dead=true;group.removeFromParent();simulation.dispose();caustics.dispose();tiles.dispose();sky.dispose();
    group.traverse(o=>o.geometry?.dispose());materials.forEach(m=>m.dispose());shellMaterial.dispose();drops.length=0;
  }
  reset();addDrop(.35,-.3,.012,.045);
  return {group,space,sphere,radius:RADIUS,step,reset,addDrop,dispose,sync,
    setWidth(width){group.scale.setScalar(THREE.MathUtils.clamp(width,.35,1.25)/2.2);group.updateMatrixWorld(true);},
    stats(){return {resolution:q.resolution,steps,queued:drops.length};},
  };
}
