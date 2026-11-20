const tavernArt = (() => {
  const canvas = document.querySelector('#tavern-art');
  const { width, height } = canvas;
  const display = canvas.getContext('2d');
  display.imageSmoothingEnabled = false;

  const ink = '#241626';
  const walnut = '#704547';
  const amber = '#eca861';
  const cream = '#ffd796';
  const dark = '#321c32';
  const lantern = { x: 381, y: 77 };
  let ctx = display;

  function rect(color, x, y, w, h) {
    ctx.fillStyle = color;
    ctx.fillRect(x, y, w, h);
  }

  // Round projected edges onto the art grid rather than antialiasing a Canvas path.
  function polygon(color, points) {
    const heights = points.map((point) => point[1]);
    for (let y = Math.min(...heights); y < Math.max(...heights); y++) {
      const cuts = [];
      for (let i = 0; i < points.length; i++) {
        const [x1, y1] = points[i];
        const [x2, y2] = points[(i + 1) % points.length];
        if ((y1 > y + .5) !== (y2 > y + .5)) {
          cuts.push(x1 + (y + .5 - y1) * (x2 - x1) / (y2 - y1));
        }
      }
      cuts.sort((a, b) => a - b);
      for (let i = 0; i < cuts.length; i += 2) {
        const left = Math.round(cuts[i]);
        rect(color, left, y, Math.round(cuts[i + 1]) - left, 1);
      }
    }
  }

  function line(color, x0, y0, x1, y1, stroke = 1) {
    const steps = Math.max(1, Math.abs(x1 - x0), Math.abs(y1 - y0));
    for (let i = 0; i <= steps; i++) {
      rect(color, Math.round(x0 + (x1 - x0) * i / steps), Math.round(y0 + (y1 - y0) * i / steps), stroke, stroke);
    }
  }

  function ellipse(color, x, y, rx, ry) {
    for (let row = -ry; row <= ry; row++) {
      const span = Math.round(rx * Math.sqrt(1 - (row / ry) ** 2));
      rect(color, x - span, y + row, span * 2 + 1, 1);
    }
  }

  function box(x, y, w, h, depth, top, front, side) {
    const offset = Math.round(depth * .8);
    polygon(side, [[x + w, y], [x + w + offset, y - depth], [x + w + offset, y + h - depth], [x + w, y + h]]);
    rect(front, x, y, w, h);
    polygon(top, [[x, y], [x + offset, y - depth], [x + w + offset, y - depth], [x + w, y]]);
  }

  function layer(draw) {
    const image = document.createElement('canvas');
    image.width = width;
    image.height = height;
    ctx = image.getContext('2d');
    draw();
    ctx = display;
    return image;
  }

  // A curved plaster vault in lamplight. Quantise the falloff on the same grid
  // as the furniture; ordered dithering only covers the narrow band transitions.
  function plaster() {
    const tones = ['#251e31','#312337','#3d293a','#50313c','#663a3e','#784641','#895443','#9a624a'];
    const threshold = [0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5];
    const surface = ctx.createImageData(width, 253);
    const rgb = tones.map(hex => [1,3,5].map(i => parseInt(hex.slice(i,i+2),16)));
    for (let y=0; y<253; y++) {
      for (let x=0; x<width; x++) {
        const distance = Math.hypot((x-lantern.x)/370,(y-lantern.y-21)/210);
        const level = Math.max(0,6.8-distance*6 - Math.max(0,45-y)/45);
        const step = Math.floor(level);
        const t = threshold[(y%4)*4 + x%4]/16;
        const color = rgb[Math.min(7, step + (level-step > .41+t*.18 ? 1 : 0))];
        surface.data.set([...color,255],4*(y*width+x));
      }
    }
    ctx.putImageData(surface,0,0);
    for (const [x,y,flip] of [[38,16,1],[419,16,-1],[438,16,1],[599,16,-1]]) {
      const rib = (c,points) => polygon(c,points.map(([a,b]) => [x+flip*a,y+b]));
      rib('#382635',[[0,0],[62,0],[47,6],[29,17],[15,36],[6,60],[0,68]]);
      rib('#65404a',[[1,44],[11,28],[26,11],[42,2],[50,2],[30,14],[15,32],[5,55],[1,56]]);
    }
  }

  const glassRamps = [
    ['#242c38','#314b4a','#3f6a5d','#678778','#a8b79a'],
    ['#332432','#52313a','#804838','#ab734a','#d8a773'],
    ['#302536','#4a354b','#714b64','#94728a','#c2a1a2'],
    ['#232d3e','#304459','#416477','#6c8b91','#adc1b2']
  ];

  function bottle(x,base,r,h,shape,colors,label) {
    const profiles = [
      [[0,.54],[.06,.72],[.48,.72],[.62,.29],[.87,.29],[.89,.4],[.96,.4],[1,.28]],
      [[0,.52],[.08,.84],[.27,1],[.43,.92],[.59,.5],[.64,.29],[.88,.29],[.9,.41],[.96,.41],[1,.32]],
      [[0,.68],[.06,.95],[.51,.95],[.58,.64],[.66,.32],[.87,.32],[.9,.45],[.96,.45],[1,.33]]
    ];
    const profile = profiles[shape];
    ellipse('#513643',x-2,base+1,r+2,2);
    for(let j=0;j<h;j++) {
      const v=j/(h-1);
      const stop=profile.findIndex(([t])=>t>=v);
      const [to,b]=profile[stop], [from,a]=profile[Math.max(0,stop-1)];
      const span=Math.max(2,Math.round(r*(a+(b-a)*(v-from)/(to-from||1))));
      for(let i=-span;i<=span;i++) {
        const u=i/span;
        const normalZ=Math.sqrt(Math.max(0,1-u*u));
        const light=.7*u+.6*normalZ;
        let tone=light<-.17?0:light<.28?1:light<.74?2:3;
        if(v<.06 || (v>.63 && v<.86)) tone=Math.max(0,tone-1);
        if((v>.18 && v<.45 || v>.56 && v<.61) && u>.53 && u<.78) tone=4;
        let color=colors[tone];
        if(label && v>.17 && v<.36 && Math.abs(u)<.77) color=light>.72?'#b99877':'#91775e';
        if(v>.95) color=u>.1?'#a38063':'#735646';
        rect(color,x+i,base-j,1,1);
      }
    }
  }

  function drawWindow() {
    const arch = [[459, 217], [459, 78], [465, 78], [465, 67], [474, 67], [474, 57],
      [488, 57], [488, 48], [506, 48], [506, 42], [543, 42], [543, 48], [562, 48],
      [562, 57], [575, 57], [575, 68], [584, 68], [584, 79], [591, 79], [591, 217]];
    polygon(ink, arch.map(([x, y]) => [x + 5, y + 5]));
    polygon(walnut, arch);
    // Ten cut stones follow the arch. The inner reveals catch the moonlight.
    const archPoint = (angle,rx,ry) => [
      Math.round(526 + rx*Math.cos(angle)),Math.round(92 - ry*Math.sin(angle))
    ];
    for(let i=0;i<10;i++) {
      const start=i*Math.PI/10+.013, end=(i+1)*Math.PI/10-.013;
      const outer= i===4 || i===5 ? 55 : 52;
      const corners=[archPoint(start,68,outer),archPoint(end,68,outer),archPoint(end,55,38),archPoint(start,55,38)];
      polygon(['#79524f','#85605a','#765052'][i%3],corners);
      line('#976a5a',...corners[0],...corners[1]);
    }
    polygon('#251d32', [[470, 210], [470, 80], [478, 80], [478, 69], [490, 69], [490, 60],
      [508, 60], [508, 55], [543, 55], [543, 60], [559, 60], [559, 69], [571, 69], [571, 81],
      [580, 81], [580, 210]]);
    polygon('#173348', [[476, 207], [476, 82], [484, 82], [484, 73], [497, 73], [497, 65],
      [511, 65], [511, 61], [544, 61], [544, 65], [558, 65], [558, 75], [570, 75], [570, 83],
      [576, 83], [576, 208]]);
    polygon('#245265', [[476, 174], [489, 164], [512, 178], [532, 161], [549, 171], [570, 163], [576, 170], [576, 211], [476, 211]]);
    polygon('#1c3e54', [[476, 165], [487, 165], [487, 157], [500, 170], [500, 186], [513, 186],
      [525, 171], [538, 188], [553, 188], [553, 174], [564, 158], [576, 173], [576, 211], [476, 211]]);
    for (const [x, y] of [[488, 179], [503, 195], [557, 190], [571, 182]]) rect('#dba568', x, y, 3, 5);
    polygon('#b6e1dc', [[549, 82], [557, 82], [557, 86], [561, 86], [561, 91], [564, 91], [564, 99],
      [560, 99], [560, 104], [554, 104], [554, 108], [544, 108], [544, 105], [551, 102],
      [555, 97], [555, 90], [552, 86], [549, 86]]);
    for (const [x, y] of [[490, 90], [518, 76], [573, 119], [506, 115]]) rect('#74a2aa', x, y, 2, 2);
    rect('#302039', 523, 59, 7, 151);
    rect('#63364f', 524, 61, 3, 149);
    box(472, 126, 107, 4, 4, '#8d5060', '#533049', '#38223b');
    box(454, 214, 139, 7, 10, '#9e5c60', '#65364d', dark);
    for(const y of [107,136,169,195]) {
      rect('#523740',460,y,10,1);
      rect('#654046',583,y+7,7,1);
    }
    line('#b37965',458,214,493,214);
    line('#cb9b77',548,212,589,212);
  }

  const room = layer(() => {
    plaster();
    for (const [x, y, len] of [[53, 91, 126], [72, 139, 107], [85, 61, 161], [405, 164, 86],
      [442, 177, 76], [478, 229, 18], [506, 230, 20], [557, 227, 25], [600, 98, 160], [628, 61, 192]]) {
      rect('#322033', x, y, 2, len);
      rect('#553349', x + 2, y + 8, 1, len - 8);
    }
    box(0, 252, 640, 5, 7, '#61394b', '#4c2d40', ink);
    rect('#523347', 0, 257, width, 103);
    for (let x = -10; x < 700; x += 35) {
      line('#352333', x, 258, x - 91, 360, 2);
      line('#694154', x + 2, 258, x - 89, 360);
    }
    for (const [x, y, w] of [[0, 274, 130], [398, 274, 242], [6, 296, 628], [0, 327, 640]]) rect('#3d2639', x, y, w, 2);
    box(0, 10, 640, 13, 7, '#9a5564', '#68364f', ink);
    for (const [x, h] of [[25, 265], [425, 260], [604, 276]]) {
      box(x, 21, 13, h - 21, 6, '#9b5762', '#713c51', '#482638');
      rect('#925264', x + 2, 25, 3, h - 32);
      for (const y of [39, 102, 173, h - 13]) {
        box(x - 3, y, 19, 5, 4, '#60384b', ink, '#251829');
        rect('#a4656a', x + 1, y + 1, 2, 3);
      }
    }
    drawWindow();

    // Leave a dark gap on the lower shelf at the bartender's head.
    for (const [x,y,w] of [[108,105,228],[110,158,81],[282,158,54]]) {
      polygon('#44303a',[[x-3,y+3],[x+w,y+2],[x+w-7,y+11],[x+6,y+12]]);
      for (const end of [x+8,x+w-13]) {
        polygon('#593737',[[end,y+4],[end+9,y+4],[end+2,y+13],[end,y+13]]);
        rect('#875844',end+1,y+5,2,5);
      }
      box(x,y,w,4,7,'#98684f','#6c4341','#49313b');
      rect('#bd8860',x+15,y,w-21,1);
    }
    const bottles = [
      [123,99,7,25,0,0,0],[138,99,5,19,0,1,0],[159,99,10,23,1,1,1],
      [195,99,7,33,0,2,0],[212,99,7,27,2,0,0],[247,99,10,18,1,3,0],
      [297,99,8,37,0,0,0],[312,99,6,28,2,1,1],[328,99,7,16,1,2,0],
      [124,153,8,23,2,1,0],[142,153,7,16,1,2,0],[178,153,6,29,0,0,1],
      [296,153,9,18,1,1,0],[321,153,6,29,0,3,0]
    ];
    for (const [x,y,r,h,shape,hue,label] of bottles) bottle(x,y,r,h,shape,glassRamps[hue],label);

    // Suspended brass lantern, faceted glass around a single wick.
    for(let y=18;y<49;y+=5) {
      rect('#3b2930',380,y,3,5);
      rect('#ac7954',381,y+1,1,2);
    }
    ellipse('#402b31',381,52,6,4);
    polygon('#734837',[[362,62],[370,56],[376,54],[386,54],[397,61],[400,64],[361,64]]);
    polygon('#c28a52',[[366,61],[373,57],[380,55],[384,55],[379,58],[375,61]]);
    polygon('#f8ba65',[[365,65],[391,65],[390,82],[370,83]]);
    polygon('#c9844f',[[392,65],[397,64],[395,79],[390,83]]);
    polygon('#ffe9ac',[[375,80],[376,73],[380,68],[380,72],[383,74],[383,80]]);
    for(const [a,b] of [[364,369],[389,388],[397,395]]) line('#543637',a,64,b,82,2);
    ellipse('#513437',382,83,15,3);
    rect('#c38a56',372,82,17,1);

    ellipse('#362136', 76, 258, 29, 8);
    polygon('#794553', [[57, 170], [93, 170], [102, 197], [99, 235], [91, 253], [60, 253], [51, 233], [50, 196]]);
    polygon('#512b41', [[86, 171], [95, 174], [102, 194], [99, 235], [91, 253], [81, 253], [88, 227]]);
    ellipse('#a45d58', 74, 169, 20, 7);
    ellipse('#733d46', 74, 169, 15, 4);
    for (const [top,mid,base] of [[59,53,58],[65,61,63],[75,74,74],[83,86,83],[90,97,90]]) {
      line('#53353b',top,175,mid,200);
      line('#53353b',mid,200,mid,229);
      line('#53353b',mid,229,base,251);
      line('#95604e',mid+2,201,mid+2,223);
    }
    for (const y of [197, 230]) {
      polygon('#454155', [[51,y-3],[73,y+1],[101,y-4],[101,y+4],[73,y+8],[51,y+4]]);
      polygon('#7b7781', [[54,y-2],[73,y+2],[96,y-2],[96,y+1],[73,y+5],[54,y+2]]);
      rect('#b3a294',86,y,5,1);
    }
    rect('#e5ac66', 91, 220, 11, 4);
    rect('#b87552', 99, 223, 4, 7);
  });

  const furniture = layer(() => {
    polygon('#352131', [[97, 279], [347, 279], [382, 259], [388, 277], [359, 294], [86, 290]]);
    box(95, 224, 254, 58, 19, '#c4835d', '#6d334d', '#3f233b');
    // Broad joined oak boards, with a recessed apron and turned corner posts.
    for (const [y,w,c] of [[229,251,'#774740'],[239,250,'#845044'],[251,250,'#78443e'],[264,251,'#683c3b']]) {
      rect(c,96,y,w,11);
      rect('#52313a',97,y+10,w-1,1);
    }
    for(const [x,y,n] of [[116,242,32],[153,244,14],[181,256,23],[264,248,21],[298,263,35],[123,270,43]]) {
      line('#a2654e',x,y,x+n,y-1);
      line('#663b39',x+6,y+2,x+n+9,y+1);
    }
    for(const x of [98,336]) {
      rect('#53333a',x,228,10,49);
      rect('#965a47',x+2,230,5,45);
      rect('#bf7954',x+5,231,2,41);
      rect('#aa694e',x-1,233,12,3);
      rect('#673b39',x-1,271,12,3);
    }
    rect('#4b2940', 95, 278, 254, 5);
    box(91, 219, 264, 9, 22, amber, '#986052', '#69404b');
    polygon('#f5b970', [[92, 219], [100, 209], [240, 211], [265, 207], [371, 202], [355, 219]]);
    rect(cream, 92, 218, 134, 2);
    rect('#f8c68a', 240, 218, 73, 2);
    rect('#ffd593', 323, 218, 32, 2);
    for (const [x, y, len] of [[102, 215, 21], [188, 207, 15], [272, 213, 21], [323, 207, 23]]) rect('#e7a366', x, y, len, 1);

    polygon('#ac5564', [[216, 215], [221, 210], [264, 210], [260, 216], [260, 262], [216, 262]]);
    rect('#934258', 216, 222, 44, 38);
    rect('#c07569', 219, 253, 36, 2);
    for (let x = 219; x < 259; x += 6) rect('#bc6969', x, 261, 3, 4);

    ellipse('#342131', 393, 279, 28, 7);
    polygon('#482b42', [[380, 226], [387, 225], [388, 266], [382, 269]]);
    polygon('#4f2c43', [[411, 223], [417, 222], [421, 267], [414, 267]]);
    rect('#6b394b', 367, 266, 41, 4);
    polygon('#8b4c54', [[366, 229], [374, 229], [371, 282], [362, 282]]);
    polygon('#9b5557', [[399, 229], [407, 229], [412, 282], [404, 282]]);
    box(360, 224, 51, 8, 11, '#b77159', '#7b3946', '#512c40');
    polygon('#ad5963',[[361,222],[368,213],[418,213],[411,223],[408,225],[364,225]]);
    rect('#f1a86a', 360, 224, 51, 2);

    ellipse('#744641', 130, 213, 14, 3);
    ellipse('#4d3040', 129, 211, 13, 3);
    ellipse('#ba764a', 129, 208, 11, 4);
    polygon('#d9954d', [[120, 207], [121, 202], [124, 199], [134, 199], [138, 203], [139, 207]]);
    rect('#ffcd82', 123, 202, 7, 2);
    rect('#f9c074', 127, 196, 4, 4);
    rect('#ffe0a0', 126, 195, 5, 2);
    polygon('#aa6436',[[127,200],[132,199],[135,201],[136,205],[133,207],[129,207],[131,203]]);
    rect('#fff0b1',134,202,2,2);
    rect('#e4b46a',121,209,16,1);
  });

  function decodeSprite(rows, colors, shade) {
    const atlas = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    const image = document.createElement('canvas');
    image.width = rows[0].length;
    image.height = rows.length;
    const brush = image.getContext('2d');
    const rgb = colors.map(hex => [0, 2, 4].map(i => parseInt(hex.slice(i, i + 2), 16)));
    rows.forEach((row,y) => {
      for(let x=0;x<row.length;x++) {
        const i = atlas.indexOf(row[x]);
        if(i<0) continue;
        brush.fillStyle = shade ? shade(rgb[i], x, y) : '#' + colors[i];
        brush.fillRect(x,y,1,1);
      }
    });
    return image;
  }

  const keeperY = 119;
  const barBack = 197;
  let keeper;

  function lightKeeper(rows, colors, x, headCenter, torsoCenter) {
    return decodeSprite(rows, colors, ([r,g,b], px, py) => {
      // Approximate the head, torso and forearms as curved surfaces.
      // Quantize the light so it joins the room's hard pixel clusters.
      const center = py < 33 ? headCenter : torsoCenter;
      const u = Math.max(-1, Math.min(1, (px - center) / (py < 33 ? 16 : 24)));
      const dx = lantern.x - x - px;
      const dy = lantern.y - keeperY - py;
      const distance = Math.hypot(dx, dy);
      const facing = u * dx / distance + Math.sqrt(1 - u*u) * .45;
      const direct = Math.max(0, facing) * Math.min(1, 140 / distance);
      const light = Math.round(direct * 5) / 5;
      // Warm bounce from the oak under the cuffs. Violet ambient fills the shadow.
      const bounce = py >= 74 ? .10 : 0;
      return `rgb(${r*(.69 + light*.40 + bounce) + light*12 + 6},
        ${g*(.67 + light*.38 + bounce) + light*8 + 4},
        ${b*(.75 + light*.24 + bounce) + 13})`;
    });
  }

  function drawKeeper(pose, foreground) {
    const { image, x, w, hands } = keeper[pose];
    if (!foreground) {
      display.drawImage(image, x, keeperY, w, image.height);
      return;
    }
    // Only the reaching fingers cover the wood. The rest of the figure
    // is composited before the counter. Shadows follow the lamplight left.
    for (const [start, end, bottom] of hands) {
      const left = x + Math.round(start * w / image.width);
      const right = x + Math.round(end * w / image.width);
      const top = barBack - keeperY;
      polygon('#cf935c', [[left-1,barBack],[right-1,barBack],[right+1,keeperY+bottom+1],
        [left-3,keeperY+bottom+3],[left-8,keeperY+bottom+2],[left-9,keeperY+bottom]]);
      rect('#ad704d', left-1, keeperY+bottom, right-left-1, 1);
      display.drawImage(image, start, top, end-start, bottom-top, left, barBack, right-left, bottom-top);
    }
  }

  function turntable(progress) {
    ellipse('#724546', 199, 214, 33, 4);
    box(157, 203, 61, 12, 18, '#6d4347', '#52303a', '#361e31');
    rect('#9b5b53', 158, 203, 58, 2);
    ellipse(ink, 190, 194, 25, 10);
    ellipse('#463747', 190, 193, 22, 8);
    ellipse('#241c29', 190, 192, 20, 7);
    ellipse('#503e50', 190, 192, 14, 5);
    ellipse('#2e2231', 190, 192, 12, 4);
    ellipse('#ad4c72', 190, 192, 8, 3);
    rect('#e7bdab', 189, 191, 2, 2);
    const spin = Math.max(0, progress - .35) * 19 - 1.8;
    const dx = Math.round(Math.cos(spin) * 17);
    const dy = Math.round(Math.sin(spin) * 6);
    rect('#7f677e', 190 + dx, 192 + dy, 3, 1);
    rect('#c56b87', 190 + Math.round(Math.cos(spin + 1) * 4), 192 + Math.round(Math.sin(spin + 1) * 2), 2, 1);

    box(218, 186, 7, 4, 3, '#d0cad4', '#9e929e', '#655665');
    const swing = Math.min(1, progress * 2.8);
    const lower = Math.max(0, (progress - .48) * 2.5);
    const tx = Math.round(216 - 13 * swing);
    const ty = Math.round(201 - 12 * swing + 4 * lower);
    line('#392c3d', 221, 186, tx + 1, ty + 2, 3);
    line('#cec1c9', 220, 185, tx, ty, 2);
    rect('#e8d7d9', tx - 2, ty, 5, 2);
    rect('#a49aa1', 207, 208, 5, 3);
    rect(progress > .45 ? '#ffc481' : '#88616a', 162, 208, 2, 2);
  }

  const settled = { pose: 'side', x: 387, foot: 224, air: 0, squash: 0 };
  let slime;
  let visitor = { pose: 'front', x: 654, foot: 278, air: 0, squash: 0 };
  let needle = 0;

  function paint() {
    display.drawImage(room, 0, 0);
    drawKeeper(visitor.pose, false);
    display.drawImage(furniture, 0, 0);
    drawKeeper(visitor.pose, true);
    turntable(needle);
    if (slime) {
      ellipse(visitor.foot === 224 ? '#8d4e45' : '#3b2638', Math.round(visitor.x), visitor.foot - 1,
        Math.max(6, 17 - Math.round(visitor.air / 4)), 2);
      const w = Math.round(46 * (1 + visitor.squash));
      const h = Math.round(38 * (1 - visitor.squash));
      display.drawImage(slime, Math.round(visitor.x - w / 2), Math.round(visitor.foot - visitor.air - h), w, h);
    }
  }

  function animate(duration, update) {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
      update(1);
      paint();
      return Promise.resolve();
    }
    const start = performance.now();
    return new Promise((resolve) => {
      function frame(now) {
        const progress = Math.min((now - start) / duration, 1);
        update(progress);
        paint();
        if (progress === 1) resolve();
        else requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);
    });
  }

  const ready = fetch('tavern-sprites.json').then((response) => {
    if (!response.ok) throw new Error('Could not load the tavern characters.');
    return response.json();
  }).then((sprites) => {
    const front = lightKeeper(sprites.front, sprites.keeperColors, 233, 26, 26);
    const side = lightKeeper(sprites.side, sprites.keeperColors, 242, 19, 19);
    const turn = lightKeeper(sprites.front, sprites.keeperColors, 237, 23, 24);
    const frontHands = [[3, 11, 86], [38, 49, 86]];
    keeper = {
      front: {image: front, x: 233, w: 52, hands: frontHands},
      turn: {image: turn, x: 237, w: 46, hands: frontHands},
      side: {image: side, x: 242, w: 52, hands: [[14, 23, 85]]},
    };
    slime = decodeSprite(sprites.jelly,sprites.jellyColors);
    paint();
  });

  return {
    ready,
    async arrive() {
      const path = [654, 588, 530, 475, 423, 387];
      await animate(4200, (progress) => {
        if (progress >= .90) {
          visitor = { ...settled, pose: progress < .95 ? 'turn' : 'side', squash: (1 - progress) * .9 };
          return;
        }
        const step = progress / .90 * (path.length - 1);
        const hop = Math.floor(step);
        const t = step % 1;
        const travel = Math.min(t / .75, 1);
        const up = hop === path.length - 2;
        visitor = {
          pose: 'front',
          x: path[hop] + (path[hop + 1] - path[hop]) * travel,
          foot: Math.round(278 - (up ? 54 * travel : 0)),
          air: Math.sin(travel * Math.PI) * (up ? 26 : 20),
          squash: t > .75 ? Math.sin((t - .75) * Math.PI * 4) * .14 : 0,
        };
      });
    },
    playRecord() {
      return animate(1150, (progress) => { needle = progress; });
    },
  };
})();
