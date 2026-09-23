import * as THREE from 'three';

export const PAINT_COLORS={player:0x25c9ff,enemy:0xffae26};
export const PAINT_LIMITS={balls:48,drops:80,splats:24};

function splatGeometry(){
  const shapes=[],shape=new THREE.Shape();
  const radii=[.62,.74,.58,1.15,.56,.72,.62,.88,.58,.67,1.05,.57,.72,.61,.90,.58,.73,.56,1.18,.60,.76,.59,.86,.62];
  const points=radii.map((r,i)=>new THREE.Vector2(Math.cos(i/radii.length*Math.PI*2)*r,Math.sin(i/radii.length*Math.PI*2)*r));
  const mid=(a,b)=>a.clone().add(b).multiplyScalar(.5);
  const start=mid(points.at(-1),points[0]);shape.moveTo(start.x,start.y);
  points.forEach((p,i)=>{const next=mid(p,points[(i+1)%points.length]);shape.quadraticCurveTo(p.x,p.y,next.x,next.y);});
  shape.closePath();shapes.push(shape);
  for(let i=0;i<7;i++){
    const angle=i*2.399,radius=1.12+(i%3)*.12,size=.045+(i%3)*.021;
    const drop=new THREE.Shape();drop.absarc(Math.cos(angle)*radius,Math.sin(angle)*radius,size,0,Math.PI*2,false);shapes.push(drop);
  }
  return new THREE.ShapeGeometry(shapes,4);
}

export class PaintballEffects{
  constructor(scene){
    this.scene=scene;this.balls=[];this.drops=[];this.splats=[];this.disposed=false;
    this.geometry=new THREE.SphereGeometry(1,10,6);
    this.material=new THREE.MeshStandardMaterial({roughness:.26,metalness:0});
    this.instances=new THREE.InstancedMesh(this.geometry,this.material,PAINT_LIMITS.balls+PAINT_LIMITS.drops);
    this.instances.name='paintballs-and-droplets';this.instances.count=0;this.instances.frustumCulled=false;
    this.instances.instanceMatrix.setUsage(THREE.DynamicDrawUsage);scene.add(this.instances);
    this.splatGeometry=splatGeometry();
    this.matrix=new THREE.Matrix4();this.rotation=new THREE.Quaternion();this.scale=new THREE.Vector3();this.color=new THREE.Color();
  }

  fire(origin,direction,{team='player',speed=24,range=28,...shot}={}){
    if(this.disposed || direction.lengthSq()<1e-10) return;
    if(this.balls.length>=PAINT_LIMITS.balls) this.balls.shift();
    this.balls.push({...shot,team,color:PAINT_COLORS[team],origin:origin.clone(),position:origin.clone(),
      direction:direction.clone().normalize(),speed,remaining:range,radius:.032});
  }

  splat(point,normal,color,parent=null){
    if(this.disposed) return;
    while(this.splats.length>=PAINT_LIMITS.splats) this.removeSplat(0);
    const material=new THREE.MeshBasicMaterial({color,transparent:true,opacity:.92,side:THREE.DoubleSide,
      depthWrite:false,polygonOffset:true,polygonOffsetFactor:-2,polygonOffsetUnits:-2});
    const mesh=new THREE.Mesh(this.splatGeometry,material);
    mesh.name='paint-splat';mesh.position.copy(point).addScaledVector(normal,.006);
    mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0,0,1),normal);
    mesh.rotateZ(Math.random()*Math.PI*2);mesh.scale.setScalar(parent ? (parent.isBone ? .095 : .11) : .16);
    this.scene.add(mesh);
    // Preserve the world transform when following a moving body part.
    if(parent){parent.updateWorldMatrix(true,false);parent.attach(mesh);}
    this.splats.push({mesh,life:6,max:6});
    this.burst(point,normal,color);
  }

  burst(point,normal,color){
    for(let i=0;i<7;i++){
      if(this.drops.length>=PAINT_LIMITS.drops) this.drops.shift();
      const velocity=new THREE.Vector3(Math.random()-.5,Math.random()-.25,Math.random()-.5).multiplyScalar(1.7).addScaledVector(normal,.8);
      const life=.20+Math.random()*.18;
      this.drops.push({position:point.clone(),velocity,color,radius:.012+Math.random()*.012,life,max:life});
    }
  }

  removeSplat(index){
    const {mesh}=this.splats[index];mesh.removeFromParent();mesh.material.dispose();this.splats.splice(index,1);
  }

  update(dt,collide,onImpact,active=true){
    if(this.disposed) return;
    if(active) for(let i=this.balls.length-1;i>=0;i--){
      const ball=this.balls[i],step=Math.min(ball.remaining,ball.speed*dt);
      const end=ball.position.clone().addScaledVector(ball.direction,step);
      const hit=collide(ball,end);
      if(hit){this.balls.splice(i,1);onImpact(ball,hit);}
      else{ball.position.copy(end);ball.remaining-=step;if(ball.remaining<=1e-6)this.balls.splice(i,1);}
    }
    for(let i=this.drops.length-1;i>=0;i--){
      const d=this.drops[i];d.life-=dt;d.velocity.y-=3*dt;d.position.addScaledVector(d.velocity,dt);
      if(d.life<=0)this.drops.splice(i,1);
    }
    for(let i=this.splats.length-1;i>=0;i--){
      const s=this.splats[i];s.life-=dt;s.mesh.material.opacity=.92*Math.min(1,s.life/1.2);
      let ancestor=s.mesh;
      while(ancestor && ancestor!==this.scene)ancestor=ancestor.parent;
      if(s.life<=0 || !ancestor)this.removeSplat(i);
    }
    let index=0;
    for(const item of [...this.balls,...this.drops]){
      const radius=item.radius*(item.life===undefined?1:Math.max(0,item.life/item.max));
      this.matrix.compose(item.position,this.rotation,this.scale.setScalar(radius));
      this.instances.setMatrixAt(index,this.matrix);this.instances.setColorAt(index,this.color.setHex(item.color));index++;
    }
    this.instances.count=index;this.instances.instanceMatrix.needsUpdate=true;
    if(this.instances.instanceColor)this.instances.instanceColor.needsUpdate=true;
  }

  clear(){
    this.balls.length=0;this.drops.length=0;
    while(this.splats.length)this.removeSplat(this.splats.length-1);
    this.instances.count=0;
  }

  dispose(){
    if(this.disposed) return;
    this.clear();this.instances.removeFromParent();this.instances.dispose();
    this.geometry.dispose();this.material.dispose();this.splatGeometry.dispose();this.disposed=true;
  }
}
