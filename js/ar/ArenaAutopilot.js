// Adapted from 3wasfnjd/hajwala js/AIController.js (free-roam states,
// wrapped heading-error steering and rhythmic donut handbrake).
// Source: 4c9e421b469118c353724944a3b1465a0c1c0fc0. See docs/HAJWALA_LICENSE.txt.
// Spectator mode integrates a bounded planar drift, not an uncontrolled sphere.
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const wrap=a=>((a+Math.PI)%(2*Math.PI)+2*Math.PI)%(2*Math.PI)-Math.PI;

// Spectator show speed is expressed relative to arena scale so every placement
// size keeps the same apparent pace. Previous value was 0.65 and looked too slow.
const SHOW_SPEED=2.10;

export class ArenaAutopilot {
  constructor({center,roadY,scale=1,roadRadius=1.30,carRadius=.25,random=Math.random,startAngle=0,introLap=false}) {
    if(!Number.isFinite(scale)||scale<=0 || roadRadius<=carRadius+.1) throw new Error('Invalid show dimensions');
    this.center={x:center.x,z:center.z};this.roadY=roadY;this.scale=scale;
    this.limit=(roadRadius-carRadius-.10)*scale;
    this.random=random;
    this.introLap=!!introLap;
    this.lapActive=this.introLap;
    this.lapDirection=1;
    this.lapAngle=startAngle;
    this.lapTravel=0;
    this.lapRadius=this.limit*.66;

    const startRadius=this.lapActive?this.lapRadius:this.limit*.42;
    this.x=Math.cos(startAngle)*startRadius;
    this.z=Math.sin(startAngle)*startRadius;
    this.vx=0;this.vz=0;

    // Tangent heading for the circular intro lap. Non-lap cars use the same
    // correct tangent start so none initially accelerate into the barrier.
    this.heading=wrap(-startAngle);
    this.speed=0;this.angularSpeed=0;this.time=0;
    this.state=this.lapActive?'LAP':'DRIFTING';this.timer=5;this.sequence=0;this.direction=1;
    this.steer=0;this.handbrake=false;this.boundaryCorrections=0;
    this.pickTarget();
  }
  pickTarget() {
    const angle=this.random()*Math.PI*2;
    const radius=this.limit*(.35+this.random()*.22);
    this.target={x:Math.cos(angle)*radius,z:Math.sin(angle)*radius};
  }
  nextState() {
    this.sequence++;
    this.state=['DRIFTING','DONUT','CRUISING'][this.sequence%3];
    this.timer=this.state==='CRUISING'?2.2:4+this.random()*2;
    this.direction=this.random()<.5?-1:1;
    this.pickTarget();
  }

  stepIntroLap(dt) {
    const radius=Math.max(this.lapRadius,.05);
    const lapSpeed=SHOW_SPEED*this.scale*.88;
    const angular=(lapSpeed/radius)*this.lapDirection;
    const previousAngle=this.lapAngle;

    this.lapAngle+=angular*dt;
    this.lapTravel+=Math.abs(this.lapAngle-previousAngle);

    const angle=this.lapAngle;
    this.x=Math.cos(angle)*radius;
    this.z=Math.sin(angle)*radius;

    // Analytical tangent velocity keeps the opening lap smooth and circular.
    this.vx=-Math.sin(angle)*lapSpeed*this.lapDirection;
    this.vz= Math.cos(angle)*lapSpeed*this.lapDirection;
    this.speed=lapSpeed;
    this.heading=wrap(this.lapDirection>0?-angle:Math.PI-angle);
    this.angularSpeed=-angular;
    this.steer=.24*this.lapDirection;
    this.handbrake=false;

    if(this.lapTravel>=Math.PI*2){
      this.lapActive=false;
      this.state='DRIFTING';
      this.timer=4.5;
      this.sequence=0;
      this.direction=this.random()<.5?-1:1;
      this.pickTarget();

      // Preserve the lap's tangent velocity so transition into drift is
      // continuous instead of visually stopping and restarting.
      this.speed=Math.hypot(this.vx,this.vz);
    }
  }

  step(dt) {
    this.time+=dt;

    if(this.lapActive){
      this.stepIntroLap(dt);
      return;
    }

    this.timer-=dt;
    const radius=Math.hypot(this.x,this.z);
    const predicted=Math.hypot(this.x+this.vx*.65,this.z+this.vz*.65);
    if(radius>this.limit*.78 || predicted>this.limit*.9) this.state='AVOIDANCE';
    if(this.state==='AVOIDANCE') {
      if(radius<this.limit*.52 && predicted<this.limit*.65){this.state='DRIFTING';this.timer=4;this.pickTarget();}
    } else if(this.timer<=0) this.nextState();

    if(this.state!=='DONUT' && this.state!=='AVOIDANCE' && Math.hypot(this.x-this.target.x,this.z-this.target.z)<this.limit*.18) this.pickTarget();
    const target=this.state==='AVOIDANCE'?{x:0,z:0}:this.target;
    const error=wrap(Math.atan2(target.x-this.x,target.z-this.z)-this.heading);
    let throttle=1,grip=2;
    this.handbrake=false;
    if(this.state==='DONUT') {
      this.steer=.55*this.direction;
      this.handbrake=Math.sin(this.time*10)>.5;
      grip=1.5;
    } else if(this.state==='DRIFTING') {
      this.steer=clamp(-error*4,-1,1);
      this.handbrake=Math.abs(error)>.4;
      grip=1.8;
    } else if(this.state==='AVOIDANCE') {
      this.steer=clamp(-error*3,-1,1);
      throttle=Math.abs(error)>1.1?.10:.65;
      this.handbrake=Math.abs(error)>.6;
      grip=7;
    } else {
      this.steer=clamp(-error*2,-1,1);throttle=.85;grip=4;
    }
    const turnGrip=this.handbrake?1:clamp(this.speed/(SHOW_SPEED*this.scale),.2,1);
    const turn=-this.steer*turnGrip*(this.handbrake?4.6:3.5);
    this.angularSpeed+=(turn-this.angularSpeed)*(1-Math.exp(-5*dt));
    this.heading=wrap(this.heading+this.angularSpeed*dt);
    const targetSpeed=SHOW_SPEED*this.scale*throttle*(this.handbrake?.86:1);
    this.speed+=(targetSpeed-this.speed)*(1-Math.exp(-3.4*dt));
    this.vx+=(Math.sin(this.heading)*this.speed-this.vx)*(1-Math.exp(-grip*dt));
    this.vz+=(Math.cos(this.heading)*this.speed-this.vz)*(1-Math.exp(-grip*dt));

    // Brake the outward component before the boundary, keeping tangential slide.
    if(radius>this.limit*.6) {
      const nx=this.x/radius,nz=this.z/radius;
      const outward=this.vx*nx+this.vz*nz;
      const allowed=Math.max(0,(this.limit-radius)*1.5);
      if(outward>allowed){this.vx-=(outward-allowed)*nx;this.vz-=(outward-allowed)*nz;}
    }
    this.x+=this.vx*dt;this.z+=this.vz*dt;
    const distance=Math.hypot(this.x,this.z);
    // Final footprint constraint, including low frame rates. Normally unused.
    if(distance>this.limit) {
      const nx=this.x/distance,nz=this.z/distance;
      this.x=nx*this.limit;this.z=nz*this.limit;
      const outward=Math.max(0,this.vx*nx+this.vz*nz);
      this.vx-=outward*nx;this.vz-=outward*nz;
      this.state='AVOIDANCE';this.boundaryCorrections++;
    }
  }
  update(dt) {
    if(!Number.isFinite(dt)||dt<0) throw new Error('Invalid show timestep');
    // Hidden/tracking-loss intervals are not passed here; never catch them up.
    let remaining=Math.min(dt,.1);
    while(remaining>1e-8){const step=Math.min(remaining,1/120);this.step(step);remaining-=step;}
    const speed=Math.hypot(this.vx,this.vz);
    const slip=speed>.01?Math.abs(wrap(Math.atan2(this.vx,this.vz)-this.heading)):0;
    return {x:this.center.x+this.x,y:this.roadY,z:this.center.z+this.z,
      heading:this.heading,vx:this.vx,vz:this.vz,speed,steer:this.steer,
      handbrake:this.handbrake,state:this.state,
      driftIntensity:clamp(slip*1.5+(this.handbrake?.65:0),0,1.8)*clamp(speed/(.2*this.scale),0,1)};
  }
}
