// Arena AI adapted from 3wasfnjd/hajwala.
// The controller no longer writes vehicle positions directly. It only
// produces steering/throttle/handbrake inputs; Vehicle.js + Crashcat/Jolt
// perform the actual movement, matching Hajwala's driving model.

const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const wrap=a=>((a+Math.PI)%(2*Math.PI)+2*Math.PI)%(2*Math.PI)-Math.PI;

function yawFromQuaternion(q){
  return Math.atan2(
    2*(q.w*q.y+q.x*q.z),
    1-2*(q.y*q.y+q.z*q.z)
  );
}

export class ArenaAutopilot {
  constructor({
    center,
    roadY,
    scale=1,
    roadRadius=1.30,
    carRadius=.25,
    random=Math.random,
    startAngle=0,
    introLap=false
  }){
    if(!Number.isFinite(scale)||scale<=0||roadRadius<=carRadius+.1){
      throw new Error('Invalid show dimensions');
    }

    this.center={x:center.x,z:center.z};
    this.roadY=roadY;
    this.scale=scale;
    this.limit=(roadRadius-carRadius-.10)*scale;
    this.random=random;

    this.startAngle=startAngle;
    this.introLap=!!introLap;
    this.lapActive=this.introLap;
    this.lapDirection=1;
    this.lapRadius=this.limit*.68;
    this.lapTravel=0;
    this.lapPrevAngle=null;

    this.state=this.lapActive?'LAP':'DRIFTING';
    this.timer=4.5+this.random()*1.5;
    this.sequence=0;
    this.direction=this.random()<.5?-1:1;
    this.time=0;

    this.steer=0;
    this.throttle=1;
    this.handbrake=false;
    this.boundaryCorrections=0;

    this.pickTarget();
  }

  getInitialPose(){
    const radius=this.lapActive?this.lapRadius:this.limit*.42;
    const angle=this.startAngle;
    return {
      x:this.center.x+Math.cos(angle)*radius,
      y:this.roadY,
      z:this.center.z+Math.sin(angle)*radius,
      heading:wrap(-angle)
    };
  }

  pickTarget(){
    const angle=this.random()*Math.PI*2;
    const radius=this.limit*(.28+this.random()*.30);
    this.target={
      x:Math.cos(angle)*radius,
      z:Math.sin(angle)*radius
    };
  }

  nextState(){
    this.sequence++;
    this.state=['DRIFTING','DONUT','CRUISING'][this.sequence%3];
    this.timer=this.state==='CRUISING'
      ?1.8+this.random()*1.2
      :3.2+this.random()*2.0;
    this.direction=this.random()<.5?-1:1;
    this.pickTarget();
  }

  vehicleState(vehicle){
    return {
      x:vehicle.spherePos.x-this.center.x,
      z:vehicle.spherePos.z-this.center.z,
      vx:vehicle.sphereVel.x,
      vz:vehicle.sphereVel.z,
      speed:Math.hypot(vehicle.sphereVel.x,vehicle.sphereVel.z),
      heading:yawFromQuaternion(vehicle.container.quaternion)
    };
  }

  updateIntroLap(dt,s){
    const angle=Math.atan2(s.z,s.x);

    if(this.lapPrevAngle===null){
      this.lapPrevAngle=angle;
    }else{
      const delta=wrap(angle-this.lapPrevAngle)*this.lapDirection;
      // Count only genuine forward progress; hand/body jitter cannot complete
      // the lap by oscillating around one point.
      if(delta>0&&delta<.45)this.lapTravel+=delta;
      this.lapPrevAngle=angle;
    }

    const lookAhead=.60*this.lapDirection;
    const targetAngle=angle+lookAhead;
    const targetX=Math.cos(targetAngle)*this.lapRadius;
    const targetZ=Math.sin(targetAngle)*this.lapRadius;
    const targetHeading=Math.atan2(targetX-s.x,targetZ-s.z);
    const error=wrap(targetHeading-s.heading);

    this.steer=clamp(-error*2.25,-1,1);
    this.throttle=1;
    this.handbrake=false;

    if(this.lapTravel>=Math.PI*2){
      this.lapActive=false;
      this.state='DRIFTING';
      this.timer=4.5;
      this.sequence=0;
      this.pickTarget();
    }
  }

  updateControls(dt,vehicle){
    if(!vehicle||!Number.isFinite(dt)||dt<0){
      return {x:0,z:0,touchActive:false,handbrake:false};
    }

    this.time+=dt;
    const s=this.vehicleState(vehicle);

    if(this.lapActive){
      this.updateIntroLap(dt,s);
      return {
        x:this.steer,
        z:this.throttle,
        touchActive:false,
        handbrake:this.handbrake
      };
    }

    this.timer-=dt;

    const radius=Math.hypot(s.x,s.z);
    let outwardSpeed=0;
    if(radius>.001){
      const nx=s.x/radius;
      const nz=s.z/radius;
      outwardSpeed=Math.max(0,s.vx*nx+s.vz*nz);
    }
    const predicted=radius+outwardSpeed*.28;

    if(radius>this.limit*.87||predicted>this.limit*.94){
      this.state='AVOIDANCE';
      this.boundaryCorrections++;
    }

    if(this.state==='AVOIDANCE'){
      if(radius<this.limit*.62&&outwardSpeed<.12*this.scale){
        this.state='DRIFTING';
        this.timer=3.8;
        this.pickTarget();
      }
    }else if(this.timer<=0){
      this.nextState();
    }

    if(
      this.state!=='DONUT' &&
      this.state!=='AVOIDANCE' &&
      Math.hypot(s.x-this.target.x,s.z-this.target.z)<this.limit*.16
    ){
      this.pickTarget();
    }

    this.handbrake=false;
    this.throttle=1;

    if(this.state==='DONUT'){
      // Hajwala-style arcade handbrake turn: full steering authority while
      // rear grip is released. Pulsing the handbrake keeps momentum alive.
      this.steer=.82*this.direction;
      this.handbrake=Math.sin(this.time*8)>-.20;
      this.throttle=.95;
    }else{
      const target=this.state==='AVOIDANCE'
        ?{x:0,z:0}
        :this.target;
      const targetHeading=Math.atan2(target.x-s.x,target.z-s.z);
      const error=wrap(targetHeading-s.heading);

      if(this.state==='DRIFTING'){
        this.steer=clamp(-error*3.4,-1,1);
        this.handbrake=Math.abs(error)>.34;
        this.throttle=1;
      }else if(this.state==='AVOIDANCE'){
        this.steer=clamp(-error*3.0,-1,1);
        this.handbrake=Math.abs(error)>.72;
        this.throttle=Math.abs(error)>1.15?.18:.70;
      }else{
        this.steer=clamp(-error*2.0,-1,1);
        this.throttle=.90;
      }
    }

    return {
      x:this.steer,
      z:this.throttle,
      touchActive:false,
      handbrake:this.handbrake
    };
  }
}
