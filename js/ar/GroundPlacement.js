// All distances are metres. The XR8 adapter must configure scale: 'absolute'.
const finitePoint = p => p && [p.x, p.y, p.z].every(Number.isFinite);
const distance = (a, b) => Math.hypot(a.x-b.x, a.y-b.y, a.z-b.z);
const median = values => [...values].sort((a,b)=>a-b)[Math.floor(values.length/2)];

// Validate a local patch of the engine's ground plane. A single feature point
// can belong to furniture: require spatially distributed, nearly horizontal
// evidence close to the absolute world floor, not simply any hit-test result.
export function groundPatch(candidate, observations) {
  if (!finitePoint(candidate)) return null;
  const unique = new Map();
  for (const observation of observations || []) {
    const p = observation?.position || observation;
    if (!finitePoint(p) || Math.abs(p.y) > .08) continue;
    if (Number.isFinite(observation.confidence) && observation.confidence <= 0) continue;
    if (Math.hypot(p.x-candidate.x, p.z-candidate.z) > .7) continue;
    const key = `${Math.round(p.x/.025)},${Math.round(p.z/.025)}`;
    if (!unique.has(key)) unique.set(key, p);
  }
  if (unique.size < 6) return null;
  const points = [...unique.values()];
  const y = median(points.map(p=>p.y));
  const inliers = points.filter(p=>Math.abs(p.y-y) <= .025);
  if (inliers.length < 6 || inliers.length < points.length*.7) return null;
  const mean = inliers.reduce((a,p)=>({x:a.x+p.x,y:a.y+p.y,z:a.z+p.z}),{x:0,y:0,z:0});
  for (const key of ['x','y','z']) mean[key] /= inliers.length;
  let xx=0, zz=0, xz=0, xy=0, zy=0;
  for (const p of inliers) {
    const x=p.x-mean.x, z=p.z-mean.z, dy=p.y-mean.y;
    xx+=x*x; zz+=z*z; xz+=x*z; xy+=x*dy; zy+=z*dy;
  }
  const n=inliers.length;
  const minorVariance=(xx+zz-Math.hypot(xx-zz,2*xz))/(2*n);
  // Reject collinear points (e.g. the bottom edge of a wall).
  if (minorVariance < .001) return null;
  const determinant=xx*zz-xz*xz;
  const slopeX=(xy*zz-zy*xz)/determinant;
  const slopeZ=(zy*xx-xy*xz)/determinant;
  if (Math.hypot(slopeX,slopeZ) > Math.tan(8*Math.PI/180)) return null;
  const error=Math.sqrt(inliers.reduce((sum,p)=>sum+Math.pow(p.y-mean.y-slopeX*(p.x-mean.x)-slopeZ*(p.z-mean.z),2),0)/n);
  if (error > .012) return null;
  const height=mean.y+slopeX*(candidate.x-mean.x)+slopeZ*(candidate.z-mean.z);
  if (Math.abs(height) > .08) return null;
  return {position:{x:candidate.x,y:height,z:candidate.z},support:n,error};
}

export class GroundPlacement {
  constructor() { this.reset(); }
  reset() {
    this.status='LIMITED'; this.normalSince=null; this.lastTracking=-Infinity;
    this.previousCamera=null; this.samples=[]; this.lastSample=-Infinity;
    this.ready=false; this.candidate=null; this.anchor=null; this.support=0;
    this.cameraStep=0; this.reason='tracking'; this.surface='estimated';
  }
  invalidate(reason='surface') {
    this.samples=[]; this.ready=false; this.candidate=null;
    this.support=0; this.reason=reason; this.surface='estimated';
  }
  observe({now,status,position,rotation}) {
    const gap=now-this.lastTracking;
    this.cameraStep=finitePoint(position)&&this.previousCamera ? distance(position,this.previousCamera.position) : 0;
    const q=rotation, old=this.previousCamera?.rotation;
    const angle=q&&old ? 2*Math.acos(Math.min(1,Math.abs(q.x*old.x+q.y*old.y+q.z*old.z+q.w*old.w))) : 0;
    const discontinuity=gap>250 || this.cameraStep>.30 || angle>.45;
    this.status=status;
    if (status!=='NORMAL' || !finitePoint(position) || discontinuity) {
      this.normalSince=null;
      this.invalidate('tracking');
    }
    if (status==='NORMAL' && finitePoint(position) && this.normalSince===null) this.normalSince=now;
    this.lastTracking=now;
    this.previousCamera=finitePoint(position) ? {position:{...position},rotation:q?{...q}:null} : null;
  }
  trackingReady(now) {
    return this.status==='NORMAL' && this.normalSince!==null && now-this.normalSince>=800 && now-this.lastTracking<=250;
  }
  sample(candidate,observations,now) {
    if (this.anchor) return;
    if (!this.trackingReady(now)) { this.invalidate('tracking'); return; }
    if (!finitePoint(candidate)) { this.invalidate('aim'); return; }
    const evidence=groundPatch(candidate,observations);
    // Sparse world points must not deadlock placement. The adapter's ray
    // intersects XR8's estimated ground; feature evidence only refines height.
    const patch=evidence || {position:{x:candidate.x,y:0,z:candidate.z},support:0};
    this.surface=evidence?'supported':'estimated';
    if (now-this.lastSample>250) this.samples=[];
    this.lastSample=now;
    this.support=patch.support;
    this.samples.push({time:now,...patch.position});
    // Retain a full one-second window, including its boundary sample.
    while (this.samples.length>1 && this.samples[1].time<=now-1000) this.samples.shift();
    const xs=this.samples.map(p=>p.x), ys=this.samples.map(p=>p.y), zs=this.samples.map(p=>p.z);
    const spread=Math.hypot(Math.max(...xs)-Math.min(...xs),Math.max(...zs)-Math.min(...zs));
    if (spread>.04 || Math.max(...ys)-Math.min(...ys)>.02) {
      this.samples=[this.samples[this.samples.length-1]];
    }
    const count=this.samples.length;
    this.candidate=this.samples.reduce((a,p)=>({x:a.x+p.x/count,y:a.y+p.y/count,z:a.z+p.z/count}),{x:0,y:0,z:0});
    this.ready=count>=8 && now-this.samples[0].time>=1000;
    this.reason=this.ready?'ready':'steady';
  }
  canLock(now) {
    return !this.anchor && this.trackingReady(now) && now-this.lastSample<=250 && !!this.candidate;
  }
  lock(now,{manual=false}={}) {
    // An explicit tap may accept the preview without waiting for a perfectly
    // still reticle, but never bypass missing/stale tracking or a missing ray hit.
    if (!this.canLock(now) || (!manual && !this.ready)) return null;
    this.anchor=Object.freeze({...this.candidate});
    this.ready=false;
    return this.anchor;
  }
}
