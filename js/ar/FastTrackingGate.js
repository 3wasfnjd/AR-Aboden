// Estimated placement needs a fresh pose, not a still-phone/surface scan.
// Require two consecutive valid frames; never start from missing/limited data.
export class FastTrackingGate {
  constructor(){ this.reset(); }

  reset(){
    this.normalFrames=0;
    this.lastTracking=-Infinity;
  }

  observe({now,status,position}){
    const valid=Number.isFinite(now) && status==='NORMAL' && position &&
      [position.x,position.y,position.z].every(Number.isFinite);
    if(!valid){this.reset();return;}
    const gap=now-this.lastTracking;
    this.normalFrames=gap>0 && gap<=250 ? Math.min(2,this.normalFrames+1) : 1;
    this.lastTracking=now;
  }

  ready(now){
    return this.normalFrames>=2 && now>=this.lastTracking && now-this.lastTracking<=250;
  }
}
