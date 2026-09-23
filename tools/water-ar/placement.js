// Isolated placement math. Metres, XR8 absolute scale. No shared AR code is changed.
export const finitePoint = p => !!p && [p.x,p.y,p.z].every(Number.isFinite);
const distance = (a,b) => Math.hypot(a.x-b.x,a.y-b.y,a.z-b.z);
const median = a => [...a].sort((x,y)=>x-y)[Math.floor(a.length/2)];

export function intersectHorizontal(origin,direction,height,maxDistance=4) {
  if (!finitePoint(origin)||!finitePoint(direction)||!Number.isFinite(height)||direction.y>-.12) return null;
  const t=(height-origin.y)/direction.y;
  if (t<.15||t>maxDistance) return null;
  return {x:origin.x+direction.x*t,y:height,z:origin.z+direction.z*t};
}

// Tabletop support is inferred from a horizontal feature patch, never a lone hit.
export function supportedSurface(origin,direction,hits,observations) {
  for (const hit of (hits||[]).slice(0,12)) {
    const seed=hit?.position||hit;
    if (!finitePoint(seed)||seed.y>origin.y-.10) continue;
    const unique=new Map();
    for (const o of observations||[]) {
      const p=o?.position||o;
      if (!finitePoint(p)|| (Number.isFinite(o?.confidence)&&o.confidence<=0)) continue;
      if (Math.abs(p.y-seed.y)>.045||Math.hypot(p.x-seed.x,p.z-seed.z)>.42) continue;
      unique.set(`${Math.round(p.x/.018)},${Math.round(p.z/.018)}`,p);
    }
    if (unique.size<6) continue;
    const values=[...unique.values()],y=median(values.map(p=>p.y));
    const pts=values.filter(p=>Math.abs(p.y-y)<.02);
    if (pts.length<6||pts.length<values.length*.7) continue;
    const mean=pts.reduce((a,p)=>({x:a.x+p.x/pts.length,y:a.y+p.y/pts.length,z:a.z+p.z/pts.length}),{x:0,y:0,z:0});
    let xx=0,zz=0,xz=0,xy=0,zy=0;
    for(const p of pts){const x=p.x-mean.x,z=p.z-mean.z,dy=p.y-mean.y;xx+=x*x;zz+=z*z;xz+=x*z;xy+=x*dy;zy+=z*dy;}
    const det=xx*zz-xz*xz;
    const minor=(xx+zz-Math.hypot(xx-zz,2*xz))/(2*pts.length);
    if (minor<.0005||det<1e-10) continue;
    const sx=(xy*zz-zy*xz)/det,sz=(zy*xx-xy*xz)/det;
    if(Math.hypot(sx,sz)>Math.tan(8*Math.PI/180)) continue;
    const rms=Math.sqrt(pts.reduce((a,p)=>a+(p.y-mean.y-sx*(p.x-mean.x)-sz*(p.z-mean.z))**2,0)/pts.length);
    if(rms>.012) continue;
    const p=intersectHorizontal(origin,direction,mean.y);
    if(!p||Math.hypot(p.x-mean.x,p.z-mean.z)>.30) continue;
    return {position:p,kind:'supported',support:pts.length};
  }
  return null;
}

export class PlacementLock {
  constructor(){this.anchor=null;this.status='LIMITED';this.since=null;this.last=-Infinity;this.previous=null;this.clearCandidate();}
  clearCandidate(){this.samples=[];this.candidate=null;this.ready=false;this.sampleAt=-Infinity;this.kind='';}
  observe(now,status,position){
    const jump=this.previous&&finitePoint(position)&&distance(this.previous,position)>.30;
    if(status!=='NORMAL'||!finitePoint(position)||now-this.last>300||jump){this.since=null;this.clearCandidate();}
    this.status=status;
    if(status==='NORMAL'&&finitePoint(position)&&this.since===null)this.since=now;
    this.last=now;this.previous=finitePoint(position)?{...position}:null;
  }
  trackingReady(now){return this.status==='NORMAL'&&this.since!==null&&now-this.since>=600&&now-this.last<300;}
  sample(result,now){
    if(this.anchor)return;
    if(!this.trackingReady(now)||!finitePoint(result?.position)){this.clearCandidate();return;}
    if(now-this.sampleAt>300||this.kind!==result.kind)this.samples=[];
    this.sampleAt=now;this.kind=result.kind;
    this.samples.push({...result.position,t:now});
    while(this.samples.length>1&&this.samples[1].t<now-750)this.samples.shift();
    const first=this.samples[0];
    if(this.samples.some(p=>distance(p,first)>.045))this.samples=[this.samples.at(-1)];
    const n=this.samples.length;
    this.candidate=this.samples.reduce((a,p)=>({x:a.x+p.x/n,y:a.y+p.y/n,z:a.z+p.z/n}),{x:0,y:0,z:0});
    this.ready=n>=5&&now-this.samples[0].t>=500;
  }
  lock(now){
    if(this.anchor||!this.ready||!this.trackingReady(now)||now-this.sampleAt>250)return null;
    this.anchor=Object.freeze({...this.candidate});this.ready=false;return this.anchor;
  }
  relocate(){this.anchor=null;this.clearCandidate();}
}
