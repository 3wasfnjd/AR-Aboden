export const ROUND_SECONDS=60;
export const TOTAL_SHOTS=24;
export const MAGAZINE_SIZE=6;
export function createRound(){return{score:0,hits:0,shots:0,remaining:TOTAL_SHOTS,magazine:MAGAZINE_SIZE,time:ROUND_SECONDS,reload:0};}
export function accuracy(round){return round.shots?Math.round(round.hits/round.shots*100):0;}
export function spendShot(round){if(round.magazine<=0||round.remaining<=0||round.reload>0||round.time<=0)return false;round.shots++;round.remaining--;round.magazine--;return true;}
export function reloadRound(round){if(round.reload>0||round.remaining<=0||round.magazine>=Math.min(MAGAZINE_SIZE,round.remaining))return false;round.reload=1.05;return true;}
export function tickRound(round,dt){round.time=Math.max(0,round.time-dt);if(round.reload>0){round.reload=Math.max(0,round.reload-dt);if(round.reload===0)round.magazine=Math.min(MAGAZINE_SIZE,round.remaining);}return round.time===0||round.remaining===0;}
