
const reduce=matchMedia('(prefers-reduced-motion: reduce)').matches;
const c=document.getElementById('fx'),x=c.getContext('2d');
const sp=72;
let W,H,cols,rows,nodes,pk,rings,mx=-999,my=-999,t=0;
function build(){W=c.width=innerWidth;H=c.height=innerHeight;cols=Math.ceil(W/sp)+1;rows=Math.ceil(H/sp)+1;nodes=[];for(let r=0;r<rows;r++)for(let q=0;q<cols;q++)nodes.push({bx:q*sp,by:r*sp,x:q*sp,y:r*sp});pk=[];rings=[]}
build();addEventListener('resize',build);
addEventListener('pointermove',e=>{mx=e.clientX;my=e.clientY});
addEventListener('pointerleave',()=>{mx=-999;my=-999});
function nb(i){const q=i%cols,r=Math.floor(i/cols),o=[];if(q>0)o.push(i-1);if(q<cols-1)o.push(i+1);if(r>0)o.push(i-cols);if(r<rows-1)o.push(i+cols);return o}
function frame(){
t++;
x.clearRect(0,0,W,H);
for(let i=0;i<nodes.length;i++){const n=nodes[i];let tx=n.bx+Math.sin(t*0.02+i)*2,ty=n.by+Math.cos(t*0.017+i*1.3)*2;const dx=n.bx-mx,dy=n.by-my,d=Math.hypot(dx,dy);if(d<170){const f=(1-d/170)*46;tx+=dx/d*f;ty+=dy/d*f}n.x+=(tx-n.x)*0.12;n.y+=(ty-n.y)*0.12}
x.strokeStyle='rgba(108,59,255,0.28)';x.lineWidth=1;x.beginPath();
for(let i=0;i<nodes.length;i++){const q=i%cols,r=Math.floor(i/cols),n=nodes[i];if(q<cols-1){x.moveTo(n.x,n.y);x.lineTo(nodes[i+1].x,nodes[i+1].y)}if(r<rows-1){x.moveTo(n.x,n.y);x.lineTo(nodes[i+cols].x,nodes[i+cols].y)}}
x.stroke();
x.fillStyle='rgba(0,212,255,0.55)';
for(const n of nodes){x.fillRect(n.x-1.5,n.y-1.5,3,3)}
if(t%9===0&&pk.length<46)pk.push({a:Math.floor(Math.random()*nodes.length),b:0,p:0,life:8+Math.floor(Math.random()*10)}),pk[pk.length-1].b=nb(pk[pk.length-1].a)[Math.floor(Math.random()*nb(pk[pk.length-1].a).length)];
for(let k=pk.length-1;k>=0;k--){const q=pk[k];q.p+=0.05;const A=nodes[q.a],B=nodes[q.b],px=A.x+(B.x-A.x)*q.p,py=A.y+(B.y-A.y)*q.p;
x.shadowColor='#00d4ff';x.shadowBlur=14;x.fillStyle='#7fe9ff';x.beginPath();x.arc(px,py,3,0,6.283);x.fill();x.shadowBlur=0;
if(q.p>=1){rings.push({x:B.x,y:B.y,r:2});q.a=q.b;const o=nb(q.a);q.b=o[Math.floor(Math.random()*o.length)];q.p=0;q.life--;if(q.life<=0)pk.splice(k,1)}}
for(let k=rings.length-1;k>=0;k--){const g=rings[k];g.r+=1.5;const al=1-g.r/46;if(al<=0){rings.splice(k,1);continue}x.strokeStyle='rgba(108,59,255,'+al+')';x.lineWidth=1.5;x.beginPath();x.arc(g.x,g.y,g.r,0,6.283);x.stroke()}
if(!reduce)requestAnimationFrame(frame)}
frame();
