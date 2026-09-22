// Short synthetic air/mechanical cues. No external recordings or background drone.
export class GalleryAudio{
 constructor(){this.ctx=null;this.muted=false;}
 unlock(){try{this.ctx??=new(window.AudioContext||window.webkitAudioContext)();if(this.ctx.state==='suspended')this.ctx.resume().catch(()=>{});}catch{}}
 tone(frequency,duration,gain=.035,type='sine',delay=0){if(!this.ctx||this.muted)return;const t=this.ctx.currentTime+delay,o=this.ctx.createOscillator(),g=this.ctx.createGain();o.type=type;o.frequency.setValueAtTime(frequency,t);g.gain.setValueAtTime(gain,t);g.gain.exponentialRampToValueAtTime(.001,t+duration);o.connect(g);g.connect(this.ctx.destination);o.start(t);o.stop(t+duration+.02);}
 shot(){if(!this.ctx||this.muted)return;const ctx=this.ctx,t=ctx.currentTime,n=Math.floor(ctx.sampleRate*.055),buf=ctx.createBuffer(1,n,ctx.sampleRate),a=buf.getChannelData(0);for(let i=0;i<n;i++)a[i]=(Math.random()*2-1)*Math.exp(-i/n*8);const s=ctx.createBufferSource();s.buffer=buf;const f=ctx.createBiquadFilter();f.type='bandpass';f.frequency.value=1500;const g=ctx.createGain();g.gain.value=.28;s.connect(f);f.connect(g);g.connect(ctx.destination);s.start(t);this.tone(160,.035,.045,'triangle');}
 hit(bull=false){this.tone(bull?1600:1100,.22,.045);this.tone(bull?2200:1650,.13,.018,'sine',.015);}
 reload(){this.tone(380,.03,.025,'triangle');this.tone(520,.045,.025,'triangle',.75);}
 tick(){this.tone(700,.07,.035);}
 finish(){[523,659,784].forEach((f,i)=>this.tone(f,.24,.035,'sine',i*.12));}
}
