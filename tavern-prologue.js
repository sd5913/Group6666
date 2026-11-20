// A miniature of the tavern seen from above. All marks land on a 320 x 180 grid.
async function playTavernPrologue() {
  const stage = document.querySelector('#prologue');
  const caption = document.querySelector('#intro-caption');
  const skip = document.querySelector('#skip-intro');
  const screen = document.querySelector('#overhead').getContext('2d');
  const makeLayer = () => {
    const c = document.createElement('canvas');
    c.width = 320;
    c.height = 180;
    return c;
  };
  const room = makeLayer();
  const frame = makeLayer();
  let pen = room.getContext('2d');
  const ink = '#271d30', shadow = '#442b38', brass = '#d89b59', glint = '#ffe5a2';
  function rect(color,x,y,w,h) {
    pen.fillStyle = color;
    pen.fillRect(Math.round(x),Math.round(y),w,h);
  }
  function oval(color,x,y,rx,ry) {
    for(let i=-ry;i<=ry;i++) {
      const half=Math.round(rx*Math.sqrt(1-(i/ry)**2));
      rect(color,x-half,y+i,2*half+1,1);
    }
  }
  function timber(x,y,w,h) {
    rect(ink,x-1,y+2,w+2,h+4);
    rect('#77443d',x,y,w,h+3);
    rect('#ba7850',x,y,w,h);
    rect('#edaf70',x+1,y,w-2,1);
    rect('#965c47',x+1,y+h-2,w-2,2);
    for(let i=8;i<w-10;i+=19) rect('#cb8b5e',x+i,y+Math.round(h*.45)+(i%3),7,1);
  }
  function cask(x,y,r) {
    oval(shadow,x-3,y+5,r+2,r-1);
    oval('#503442',x,y,r,r);
    oval('#a56a49',x,y-2,r-1,r-2);
    oval('#71483f',x,y-2,r-3,r-4);
    rect('#aa7953',x-r+4,y-4,2*r-8,1);
    rect('#93644c',x-r+3,y,2*r-6,1);
    rect('#c78a58',x+2,y-5,2,2);
  }
  function bottle(x,y,color) {
    oval('#64433f',x-1,y+1,3,2);
    oval(color,x,y-2,3,3);
    rect('#523a38',x-1,y-6,3,3);
    rect('#bd956e',x,y-6,2,1);
    rect('#e0bd87',x+1,y-3,1,2);
  }
  function wovenMat(x,y,w,h) {
    rect('#47303b',x-1,y+2,w+2,h+1);
    rect('#864355',x,y,w,h);
    rect('#bf7c60',x+2,y+2,w-4,h-4);
    rect('#723b50',x+3,y+3,w-6,h-6);
    for(let i=5;i<w-4;i+=4) {
      rect('#c69176',x+i,y-2,1,2);
      rect('#bd8169',x+i,y+h,1,2);
    }
  }
  function candle(x,y) {
    oval('#7f5348',x,y+2,4,2);
    rect('#ddbd85',x-1,y-4,3,6);
    rect('#f9a953',x,y-7,2,3);
    rect(glint,x,y-6,1,2);
  }
  rect(ink,0,0,320,180);
  rect('#362935',10,9,299,160);
  for(let row=0;row<16;row++) {
    const y=16+row*9;
    rect(['#704847','#79504a','#744a46','#694346'][row%4],14,y,291,8);
    for(let x=20+(row*31)%59;x<300;x+=59) {
      rect('#50353e',x,y,1,8);
      rect('#86574d',x+3,y+2,8,1);
    }
  }
  timber(10,7,300,7);
  timber(9,14,6,145);
  timber(303,14,6,145);
  // Cool light from the mullioned east window crosses the floorboards.
  for(let i=0;i<25;i++) {
    const x=289-i;
    for(let j=0;j<3;j++) rect(i<10?'#827277':'#76656b',x,61+j*9+Math.floor(i/3),1,7);
  }
  rect('#465369',300,58,6,32);
  rect('#8ab4b4',302,59,2,30);
  rect('#3b3343',300,72,7,2);
  cask(31,28,10); cask(50,26,8); cask(30,47,8);
  timber(71,18,118,10);
  for(const [x,c] of [[78,'#45665c'],[86,'#506f62'],[103,'#97624c'],[120,'#596378'],[128,'#825666'],[163,'#617358'],[174,'#64755f']]) bottle(x,23,c);
  wovenMat(97,102,138,37);
  for(let x=105;x<231;x+=12) {
    for(let i=0;i<4;i++) {
      rect('#9f565b',x+i,120-i,1,1); rect('#9f565b',x+i+4,117+i,1,1);
    }
  }
  timber(73,64,15,37); timber(74,64,166,26);
  rect('#f4bd78',88,88,108,1);
  // The little bell, record player and sleeve stay in the same order as in the side view.
  oval(shadow,135,80,6,3); oval('#976442',136,78,5,4);
  oval(brass,136,77,4,3); rect(glint,136,75,2,1);
  rect(ink,153,68,35,20); rect('#88574c',154,67,34,19);
  rect('#c18661',154,67,34,1);
  oval('#392a39',168,76,11,9); oval('#685463',168,75,10,8);
  rect('#bda8a1',182,70,3,3);
  candle(231,71);
  for(const x of [99,206]) {
    oval(shadow,x-2,104,9,6); oval('#563346',x,101,9,6);
    oval('#ae6463',x,99,8,5); oval('#c47d6c',x,98,6,3);
  }
  // Empty tables keep the single guest and the record as the focal point.
  for(const [x,y] of [[42,106],[271,120]]) {
    oval(shadow,x-3,y+4,16,11); oval('#77473d',x,y,16,11);
    oval('#aa714e',x,y-2,16,10);
    rect('#c99263',x-12,y-5,23,1); candle(x+5,y-3);
    oval('#573544',x-4,y+16,7,4); oval('#a46b51',x-4,y+14,7,4);
  }
  timber(10,157,136,6); timber(172,157,138,6);
  rect('#a37658',147,158,24,3);
  pen = frame.getContext('2d');
  screen.imageSmoothingEnabled=false;
  const smooth = t => {t=Math.max(0,Math.min(1,t)); return t*t*(3-2*t);};
  function line(color,x,y,tx,ty,size) {
    const n=Math.max(1,Math.ceil(Math.hypot(tx-x,ty-y)));
    for(let i=0;i<=n;i++) rect(color,x+(tx-x)*i/n,y+(ty-y)*i/n,size,size);
  }
  function disc(x,y,angle) {
    oval(ink,x,y+1,10,8);
    oval('#302736',x,y,10,8);
    for(const r of [6,8]) {
      for(let i=0;i<8;i++) {
        const a=angle+i*.11;
        rect('#756174',x+Math.cos(a)*r,y+Math.sin(a)*r*.8,1,1);
      }
    }
    oval('#c45b84',x,y,3,2); rect('#faccb3',x,y,1,1);
  }
  function draw(t) {
    pen.drawImage(room,0,0);
    const choose=smooth((t-1.7)/1.6), load=smooth((t-3.6)/1.9);
    const drop=smooth((t-5.6)/1.3);
    const sleeveX=207-4*choose;
    rect('#563344',sleeveX-11,69,23,17);
    rect('#a25c74',sleeveX-11,68,22,16);
    rect('#6c3e60',sleeveX-9,70,18,12);
    oval('#df91ae',sleeveX,76,4,3); rect('#f9d9cb',sleeveX-2,74,2,1);
    const dx=Math.round(sleeveX-35*load), dy=Math.round(75-7*Math.sin(load*Math.PI));
    if(load>0) disc(dx,dy,t>6.5?(t-6.5)*2:0);
    const pickup=smooth((t-2.8)/.85);
    const release=smooth((t-5.5)/.42);
    const returnHand=smooth((t-6.9)/.68);
    const handX=(181+(dx-181)*pickup+(182-dx)*release-8*drop)*(1-returnHand)+181*returnHand;
    const handY=(64+(dy-64)*pickup+(77-dy)*release)*(1-returnHand)+64*returnHand;
    oval(shadow,175,56,12,7);
    oval('#673344',178,55,12,9);
    rect('#465344',170,49,16,4);
    line('#d8bb96',184,57,handX-2,handY-2,4);
    oval('#eab48d',handX,handY,3,3);
    oval('#604f57',178,51,8,8);
    oval('#afa1a0',179,49,8,7);
    rect('#e4ceaf',178,44,7,2); rect('#d0b9a7',174,47,5,1);
    oval('#bf8978',179,55,5,3); rect('#ddc9b1',177,57,5,1);
    line('#c9bec2',183,71,183-9*drop,80-3*drop,1);
    rect('#e1ccc7',181-9*drop,80-3*drop,3,2);
    const lean=Math.sin(Math.PI*choose)*3;
    oval('#80405a',206,99,8,5); oval('#d84986',206,96-lean,9,7);
    oval('#fa76ab',205,94-lean,7,5); rect('#ffe0de',202,91-lean,3,2);
    rect('#51243c',202,91-lean,1,1); rect('#51243c',206,91-lean,1,1);
    if(t>7) {
      // Pale pink stepping stones in the grooves briefly recall the Jelly Grotto.
      for(let i=0;i<5;i++) {
        const phase=(t-7)*.7-i*.24;
        if(phase<=0 || phase>=1) continue;
        const x=171+phase*27, y=73-Math.sin(phase*Math.PI)*14;
        rect('#bc668a',x,y,4,3); rect('#f6c6cc',x,y,4,1);
      }
    }
    const zoom=1+.34*smooth((t-.6)/7.2);
    const cw=Math.round(320/zoom),ch=Math.round(180/zoom);
    screen.drawImage(frame,Math.round((320-cw)*.56),Math.round((180-ch)*.43),cw,ch,0,0,640,360);
  }
  const words=['At my bar, every guest picks a favorite record.',
    'I set it spinning and lower the needle.',
    'While it plays, they tell me where it takes them.'];
  const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
  stage.hidden=false;
  skip.focus();
  const start=performance.now();
  await new Promise(resolve=>{
    let animation;
    function finish() {
      cancelAnimationFrame(animation);
      skip.removeEventListener('click',finish);
      stage.hidden=true;
      resolve();
    }
    function tick(now) {
      const t=(now-start)/1000;
      if(t>=11.8) {finish();return;}
      const beat=t<3.6?0:t<7.1?1:2;
      if(caption.textContent!==words[beat]) caption.textContent=words[beat];
      draw(reduced?[0,5.5,7.1][beat]:t);
      animation=requestAnimationFrame(tick);
    }
    skip.addEventListener('click',finish);
    tick(start);
  });
}
