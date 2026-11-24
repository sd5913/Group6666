/* Midi Runner tavern entrance. The art is drawn from geometry at runtime. */
(() => {
  'use strict';
  const W = 1280, H = 720;
  const canvas = document.createElement('canvas');
  canvas.id = 'tavern-menu';
  canvas.width = W;
  canvas.height = H;
  canvas.tabIndex = 0;
  canvas.setAttribute('aria-label', 'Midi Runner 酒馆入口；点击唱片机进入唱片界面');
  Object.assign(canvas.style, {
    position: 'fixed', inset: '0', width: '100vw', height: '100vh',
    zIndex: '100', cursor: 'default', background: '#281d32',
    imageRendering: 'pixelated', touchAction: 'manipulation'
  });
  document.body.appendChild(canvas);
  const screen = canvas.getContext('2d', { alpha: false });
  const world = document.createElement('canvas');
  world.width = W; world.height = H;
  const compose = world.getContext('2d', { willReadFrequently: true, alpha: false });
  let ctx = compose;
  const art = document.createElement('canvas');
  art.width = W; art.height = H;
  const artContext = art.getContext('2d', { alpha: false });
  const pixelSize = 3, pixelW = Math.ceil(W / pixelSize), pixelH = Math.ceil(H / pixelSize);
  const pixelCanvas = document.createElement('canvas');
  pixelCanvas.width = pixelW; pixelCanvas.height = pixelH;
  const pixelContext = pixelCanvas.getContext('2d');
  const sample = new Float32Array(pixelW * pixelH * 3);
  const light = new Float32Array(pixelW * pixelH);
  const pixelImage = pixelContext.createImageData(pixelW, pixelH);
  let ready = false, requested = false, finished = false, painted = false;
  let view = { x: 0, y: 0, scale: 1 };

  function makeLayer(opaque = false) {
    const image = document.createElement('canvas');
    image.width = W; image.height = H;
    return { image, context: image.getContext('2d', { willReadFrequently: true, alpha: !opaque }) };
  }

  const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
  const rgb = c => Array.isArray(c) ? c : [1, 3, 5].map(i => parseInt(c.slice(i, i + 2), 16));
  const css = c => Array.isArray(c) ? `rgb(${c[0]},${c[1]},${c[2]})` : c;
  function path(points, close = false) {
    ctx.beginPath();
    ctx.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i++) ctx.lineTo(points[i][0], points[i][1]);
    if (close) ctx.closePath();
  }
  function shape(op, a, k) {
    const fill = a[1] ?? k.fill;
    const outline = a[2] ?? k.outline;
    const width = a[3] ?? k.width ?? 2;
    ctx.lineJoin = 'round';
    if (op === 'poly' || op === 'line') path(a[0], op === 'poly');
    else {
      const [x0, y0, x1, y1] = a[0];
      ctx.beginPath();
      if (op === 'rect') {
        const r = a[4] ?? k.radius ?? 0;
        if (r) ctx.roundRect(x0, y0, x1 - x0 + 1, y1 - y0 + 1, r);
        else ctx.rect(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
      } else ctx.ellipse((x0 + x1) / 2, (y0 + y1) / 2,
        (x1 - x0) / 2, (y1 - y0) / 2, 0, 0, Math.PI * 2);
    }
    if (fill && op !== 'line') { ctx.fillStyle = css(fill); ctx.fill(); }
    if (op === 'line' || outline) {
      ctx.strokeStyle = css(op === 'line' ? fill : outline);
      ctx.lineWidth = op === 'line' ? (a[2] ?? k.width ?? 2) : width;
      ctx.stroke();
    }
  }
  function glow(a, k) {
    const [cx, cy, rx, ry, color] = a;
    const strength = a[5] ?? k.strength ?? .42;
    const [r, g, b] = rgb(color);
    const x0 = clamp(cx - rx, 0, W), y0 = clamp(cy - ry, 0, H);
    const x1 = clamp(cx + rx, 0, W), y1 = clamp(cy + ry, 0, H);
    const img = ctx.getImageData(x0, y0, x1 - x0, y1 - y0);
    const d = img.data;
    for (let y = 0; y < img.height; y++) for (let x = 0; x < img.width; x++) {
      const v = Math.max(0, 1 - ((x + x0 - cx) / rx) ** 2 - ((y + y0 - cy) / ry) ** 2);
      const alpha = v * v * strength, i = (y * img.width + x) * 4;
      d[i] = d[i] * (1 - alpha) + r * alpha;
      d[i + 1] = d[i + 1] * (1 - alpha) + g * alpha;
      d[i + 2] = d[i + 2] * (1 - alpha) + b * alpha;
    }
    ctx.putImageData(img, x0, y0);
  }
  function shadedPoly(a, k) {
    const [points, base] = a;
    const vertical = a[2] ?? k.vertical ?? 0;
    const horizontal = a[3] ?? k.horizontal ?? 0;
    const warm = a[4] ?? k.warm ?? 0;
    const [r, g, b] = rgb(base);
    const xs = points.map(p => p[0]), ys = points.map(p => p[1]);
    const xmin = Math.min(...xs), xmax = Math.max(...xs);
    const ymin = Math.min(...ys), ymax = Math.max(...ys);
    const x0 = clamp(xmin, 0, W), y0 = clamp(ymin, 0, H);
    const x1 = clamp(xmax + 1, 0, W), y1 = clamp(ymax + 1, 0, H);
    const maskCanvas = document.createElement('canvas');
    maskCanvas.width = x1 - x0; maskCanvas.height = y1 - y0;
    const m = maskCanvas.getContext('2d');
    m.beginPath(); m.moveTo(points[0][0] - x0, points[0][1] - y0);
    for (let i = 1; i < points.length; i++) m.lineTo(points[i][0] - x0, points[i][1] - y0);
    m.closePath(); m.fill();
    const mask = m.getImageData(0, 0, maskCanvas.width, maskCanvas.height).data;
    const img = ctx.getImageData(x0, y0, maskCanvas.width, maskCanvas.height);
    const d = img.data;
    for (let y = 0; y < img.height; y++) for (let x = 0; x < img.width; x++) {
      const i = (y * img.width + x) * 4;
      if (!mask[i + 3]) continue;
      const u = clamp((x + x0 - xmin) / Math.max(1, xmax - xmin), 0, 1);
      const v = clamp((y + y0 - ymin) / Math.max(1, ymax - ymin), 0, 1);
      const light = 1 + vertical * (.5 - v) + horizontal * (.5 - u);
      d[i] = clamp(r * light + warm * (1 - v), 0, 255);
      d[i + 1] = clamp(g * light + warm * .48 * (1 - v), 0, 255);
      d[i + 2] = clamp(b * light - warm * .35 * (1 - v), 0, 255);
      d[i + 3] = 255;
    }
    ctx.putImageData(img, x0, y0);
  }
  function slime(a, k) {
    const [box, radius, base] = a, elder = a[3] ?? k.elder ?? false;
    const [x0, y0, x1, y1] = box, w = x1 - x0, h = y1 - y0;
    const hx = w / 2, cx = (x0 + x1) / 2, crown = y0 + radius;
    const c = rgb(base), edge = rgb(elder ? '#304244' : '#743249');
    const img = ctx.getImageData(x0, y0, w, h), d = img.data;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const xx = x + x0, yy = y + y0;
      const row = clamp((yy - crown) / radius, -1, 0);
      let side = hx * Math.sqrt(Math.max(0, 1 - row * row));
      if (yy >= crown) side = hx * (1 - .055 * (yy - crown) / Math.max(1, y1 - crown));
      if (!elder) {
        const t = clamp((yy - (y1 - 14)) / 14, 0, 1);
        side -= 7.7 * (1 - Math.sqrt(Math.max(0, 1 - t * t)));
      }
      const nx0 = clamp(Math.abs(xx - cx) / hx, 0, 1);
      const top = crown - radius * Math.sqrt(Math.max(0, 1 - nx0 * nx0));
      const margin = Math.min(side - Math.abs(xx - cx), yy - top, y1 - 1 - yy);
      if (margin < 0) continue;
      const u = (xx - cx) / hx, v = (yy - y0) / Math.max(1, h);
      const nx = clamp(u, -1, 1), ny = clamp((v - .35) * 1.2, -1, 1);
      const nz = Math.sqrt(Math.max(.04, 1 - .73 * nx * nx - .32 * ny * ny));
      const lambert = Math.max(0, -.48 * nx - .50 * ny + .72 * nz);
      const vol = elder ? .55 + .39 * lambert - .20 * clamp((v - .64) / .36, 0, 1)
        : .64 + .52 * lambert - .23 * clamp((v - .64) / .36, 0, 1);
      const keyW = .27 * (104 / w), keyH = .16 * (85 / h), keyV = elder ? .14 : .23;
      const key = Math.exp(-(((u + .38) / keyW) ** 2) - (((v - keyV) / keyH) ** 2));
      const broad = Math.exp(-(((u + .31) / .56) ** 2) - (((v - .37) / .55) ** 2));
      const cool = clamp((u - .56) / .36, 0, 1) * (1 - v * .55);
      const shade = !elder ? 1 - .17 * clamp((yy - (y1 - 18)) / 9, 0, 1) : 1;
      const rim = margin < 20 ? .75 + .23 * clamp(margin / 20, 0, 1) : 1;
      const i = (y * w + x) * 4;
      for (let ch = 0; ch < 3; ch++) {
        let value = (c[ch] * vol + key * (elder ? [30, 27, 24][ch] : [67, 51, 47][ch])
          + broad * (elder ? [8, 5, 3][ch] : [16, 9, 5][ch])
          + cool * [8, 24, 34][ch]) * shade * rim;
        if (margin <= 4) value = value * .25 + edge[ch] * .75;
        d[i + ch] = clamp(value, 0, 255);
      }
      d[i + 3] = 255;
    }
    ctx.putImageData(img, x0, y0);
  }
  const lum = (r, g, b) => r * .299 + g * .587 + b * .114;
  const bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];
  function smooth(a, b, x) { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); }
  function pixelPost(elderPose) {
    const source = compose.getImageData(0, 0, W, H).data;
    for (let y = 0; y < pixelH; y++) for (let x = 0; x < pixelW; x++) {
      const si = (Math.min(H - 1, y * pixelSize + 1) * W + Math.min(W - 1, x * pixelSize + 1)) * 4;
      const i = (y * pixelW + x) * 3, j = y * pixelW + x;
      sample[i] = source[si] / 255; sample[i + 1] = source[si + 1] / 255;
      sample[i + 2] = source[si + 2] / 255;
      light[j] = lum(sample[i], sample[i + 1], sample[i + 2]);
    }
    const d = pixelImage.data;
    for (let y = 0; y < pixelH; y++) for (let x = 0; x < pixelW; x++) {
      const j = y * pixelW + x, i = j * 3;
      const right = light[y * pixelW + (x + 1) % pixelW], left = light[y * pixelW + (x + pixelW - 1) % pixelW];
      const down = light[((y + 1) % pixelH) * pixelW + x], up = light[((y + pixelH - 1) % pixelH) * pixelW + x];
      const brighter = Math.max(right, left, down, up) - light[j];
      const rampX = (right - light[j]) * (light[j] - left) > 0 ? Math.min(Math.abs(right - light[j]), Math.abs(light[j] - left)) : 0;
      const rampY = (down - light[j]) * (light[j] - up) > 0 ? Math.min(Math.abs(down - light[j]), Math.abs(light[j] - up)) : 0;
      const dark = smooth(.14, .16, brighter);
      let r = sample[i] * (1 - .4 * dark), g = sample[i + 1] * (1 - .4 * dark), b = sample[i + 2] * (1 - .4 * dark);
      const l = lum(r, g, b);
      r = clamp((l + (r - l) * 1.15 - .5) * 1.05 + .5, 0, 1);
      g = clamp((l + (g - l) * 1.15 - .5) * 1.05 + .5, 0, 1);
      b = clamp((l + (b - l) * 1.15 - .5) * 1.05 + .5, 0, 1);
      let yy = r * .25 + g * .5 + b * .25;
      let co = (r - b) * .5, cg = -r * .25 + g * .5 - b * .25;
      const th = (bayer[y % 4][x % 4] + .5) / 16 - .5;
      const grad = smooth(.001, .006, Math.max(rampX, rampY)) * (1 - dark);
      yy = Math.floor(yy * 15 + .5 + th * .8 * grad) / 15;
      co = Math.floor(co * 64 + .5) / 64; cg = Math.floor(cg * 64 + .5) / 64;
      const oi = j * 4;
      d[oi] = clamp(yy + co - cg, 0, 1) * 255;
      d[oi + 1] = clamp(yy + cg, 0, 1) * 255;
      d[oi + 2] = clamp(yy - co - cg, 0, 1) * 255;
      d[oi + 3] = 255;
    }
    pixelContext.putImageData(pixelImage, 0, 0);
    const actx = artContext;
    actx.imageSmoothingEnabled = false;
    actx.drawImage(pixelCanvas, 0, 0, W, H);
    // Both brows are matched after grading so their color remains identical.
    actx.fillStyle = '#d8dfce';
    for (const x of [496, 553]) actx.fillRect(
      Math.round(551 + (x - 551) * elderPose.sx),
      Math.round(443 + (327 - 443) * elderPose.sy),
      Math.round(28 * elderPose.sx), Math.round(9 * elderPose.sy));
    actx.fillStyle = '#66817b';
    for (const x of [496, 553]) actx.fillRect(
      Math.round(551 + (x + 3 - 551) * elderPose.sx),
      Math.round(443 + (336 - 443) * elderPose.sy),
      Math.round(22 * elderPose.sx), Math.max(2, Math.round(3 * elderPose.sy)));
    actx.beginPath();
    actx.moveTo(423, 649); actx.lineTo(857, 649); actx.lineTo(846, 697);
    actx.lineTo(434, 697); actx.closePath();
    actx.fillStyle = '#362638'; actx.fill();
    actx.lineWidth = 3; actx.strokeStyle = '#9e6770'; actx.stroke();
    actx.fillStyle = '#563447'; actx.fillRect(451, 662, 378, 24);
    actx.font = '40px Upheaval, monospace';
    actx.textBaseline = 'top'; actx.textAlign = 'left';
    hudText(actx, 'MIDI RUNNER', 128, 78);
    actx.font = '30px Upheaval, monospace';
    actx.textAlign = 'center';
    hudText(actx, 'CLICK THE RECORD PLAYER', 640, 654);
  }
  function hudText(g, text, x, y) {
    g.lineJoin = 'round'; g.lineWidth = 3;
    g.strokeStyle = '#2a1c32'; g.strokeText(text, x + 3, y + 3);
    g.fillStyle = '#2a1c32'; g.fillText(text, x + 3, y + 3);
    g.lineWidth = 2; g.strokeStyle = '#4a2f40'; g.strokeText(text, x, y);
    g.fillStyle = '#f9e7c4'; g.fillText(text, x, y);
  }
  function drawCommand(command) {
    const { op, args, kwargs } = command;
    if (['poly', 'line', 'rect', 'ellipse'].includes(op)) shape(op, args, kwargs);
    else if (op === 'glow') glow(args, kwargs);
    else if (op === 'shaded_poly') shadedPoly(args, kwargs);
    else if (op === 'slime') slime(args, kwargs);
  }
  function drawRange(commands, from, to, target) {
    ctx = target.context;
    for (let i = from; i < to; i++) drawCommand(commands[i]);
  }
  function findSceneParts(commands) {
    const elder = commands.findIndex(c => c.op === 'slime' && c.kwargs.elder);
    const young = commands.findIndex((c, i) => i > elder && c.op === 'slime');
    const hat = commands.findIndex((c, i) => i > elder && i < young && c.op === 'poly' && c.args[0][0][1] < 260);
    const counter = commands.findIndex((c, i) => i > young && c.op === 'shaded_poly' && c.args[0][0][0] === 219);
    const player = commands.findIndex((c, i) => i > counter && c.op === 'poly' && c.args[0][0][0] === 292);
    const disc = commands.findIndex((c, i) => i > player && c.op === 'ellipse' && c.args[0][0] === 329 && c.args[0][1] === 375);
    if ([elder, young, hat, counter, player, disc].some(i => i < 0)) throw new Error('Tavern animation layers could not be found');
    return { elder, young, hat, counter, player, disc };
  }
  function makeSceneLayers(commands) {
    const p = findSceneParts(commands);
    const base = makeLayer(true), elder = makeLayer(), hat = makeLayer();
    const young = makeLayer(), counter = makeLayer(), player = makeLayer(), front = makeLayer();
    base.context.fillStyle = '#281d32'; base.context.fillRect(0, 0, W, H);
    drawRange(commands, 0, p.elder, base);
    drawRange(commands, p.young - 1, p.young, base); // stool contact shadow
    drawRange(commands, p.elder, p.hat, elder);
    drawRange(commands, p.hat, p.young - 1, hat);
    drawRange(commands, p.young, p.counter, young);
    drawRange(commands, p.counter, p.player, counter);
    drawRange(commands, p.player, p.disc, player);
    drawRange(commands, p.disc + 4, commands.length, front); // tonearm and bell remain above the disc
    ctx = compose;
    return { base, elder, hat, young, counter, player, front };
  }
  function squashPose(seconds, period, phase, width, height) {
    const cycle = ((seconds / period + phase) % 1 + 1) % 1;
    const keys = [[0, 0], [.19, 1], [.36, 0], [.59, -1], [.78, 0], [1, 0]];
    let amount = 0;
    for (let i = 0; i < keys.length - 1; i++) {
      const [at, value] = keys[i], [nextAt, nextValue] = keys[i + 1];
      if (cycle <= nextAt) {
        const u = smooth(0, 1, (cycle - at) / (nextAt - at));
        amount = value + (nextValue - value) * u;
        break;
      }
    }
    return { sx: 1 + amount * width, sy: 1 - amount * height };
  }
  function drawSquash(layer, crop, cx, baseY, pose) {
    compose.save();
    compose.translate(cx, baseY);
    compose.scale(pose.sx, pose.sy);
    compose.translate(-cx, -baseY);
    compose.imageSmoothingEnabled = false;
    compose.drawImage(layer.image, ...crop, ...crop);
    compose.restore();
  }
  function drawPlayerGlow(seconds) {
    const pulse = .43 + .045 * Math.sin(seconds * 2.2);
    compose.save();
    compose.beginPath();
    compose.moveTo(291, 392); compose.lineTo(432, 392);
    compose.lineTo(458, 407); compose.lineTo(458, 440);
    compose.lineTo(314, 440); compose.lineTo(291, 423); compose.closePath();
    compose.strokeStyle = `rgba(255, 204, 110, ${pulse})`;
    compose.shadowColor = 'rgba(255, 195, 84, .68)';
    compose.shadowBlur = 16;
    compose.lineWidth = 4;
    compose.stroke();
    compose.beginPath();
    compose.ellipse(375, 392, 49, 19, 0, 0, Math.PI * 2);
    compose.strokeStyle = 'rgba(255, 213, 122, .38)';
    compose.lineWidth = 4;
    compose.stroke();
    compose.restore();
  }
  function drawRecord(seconds) {
    compose.save();
    compose.translate(375, 392);
    compose.scale(1, .38); // rotating in its own plane, then foreshortened on the tabletop
    compose.rotate(seconds * 1.4);
    compose.beginPath(); compose.arc(0, 0, 46, 0, Math.PI * 2);
    compose.fillStyle = '#211d2c'; compose.fill();
    compose.lineWidth = 4; compose.strokeStyle = '#876d72'; compose.stroke();
    for (const radius of [37, 33, 29]) {
      compose.beginPath(); compose.arc(0, 0, radius, 0, Math.PI * 2);
      compose.lineWidth = 1.7; compose.strokeStyle = '#443244'; compose.stroke();
    }
    // Offset marks make the record's rotation visible without changing its shape.
    compose.beginPath(); compose.arc(0, 0, 37, -.38, .18);
    compose.lineWidth = 3; compose.strokeStyle = '#b7a2a0'; compose.stroke();
    compose.beginPath(); compose.arc(0, 0, 31, 2.25, 2.63);
    compose.lineWidth = 2; compose.strokeStyle = '#927681'; compose.stroke();
    compose.beginPath(); compose.arc(0, 0, 20, 0, Math.PI * 2);
    compose.fillStyle = '#bd5a78'; compose.fill();
    compose.fillStyle = '#f3c49c';
    compose.fillRect(12, -5, 8, 10);
    compose.beginPath(); compose.arc(0, 0, 7, 0, Math.PI * 2);
    compose.fillStyle = '#f2b66c'; compose.fill();
    compose.restore();
  }
  function renderFrame(layers, seconds) {
    const elderPose = squashPose(seconds, 3.3, 0, .035, .045);
    const youngPose = squashPose(seconds, 2.7, .26, .05, .06);
    compose.drawImage(layers.base.image, 0, 0);
    drawSquash(layers.elder, [450, 275, 200, 170], 551, 443, elderPose);
    const hatShift = (276 - 443) * (elderPose.sy - 1);
    compose.drawImage(layers.hat.image, 516, 242, 68, 43, 516, 242 + hatShift, 68, 43);
    drawSquash(layers.young, [725, 370, 112, 90], 781, 458, youngPose);
    compose.drawImage(layers.counter.image, 0, 0);
    compose.drawImage(layers.player.image, 0, 0);
    drawPlayerGlow(seconds);
    drawRecord(seconds);
    compose.drawImage(layers.front.image, 0, 0);
    pixelPost(elderPose);
    painted = true;
    present();
  }
  function present() {
    screen.imageSmoothingEnabled = false;
    screen.fillStyle = '#281d32'; screen.fillRect(0, 0, canvas.width, canvas.height);
    if (painted) screen.drawImage(art, view.x, view.y, W * view.scale, H * view.scale);
  }
  function resize() {
    const ratio = window.devicePixelRatio || 1;
    canvas.width = Math.round(innerWidth * ratio);
    canvas.height = Math.round(innerHeight * ratio);
    const scale = Math.min(canvas.width / W, canvas.height / H);
    view = { x: (canvas.width - W * scale) / 2, y: (canvas.height - H * scale) / 2, scale };
    present();
  }
  function openRecords() {
    if (finished) return;
    requested = true;
    if (!ready) return;
    finished = true;
    canvas.remove();
    const game = document.getElementById('canvas');
    if (game) game.focus();
  }
  canvas.addEventListener('pointermove', event => {
    const x = (event.clientX * (window.devicePixelRatio || 1) - view.x) / view.scale;
    const y = (event.clientY * (window.devicePixelRatio || 1) - view.y) / view.scale;
    canvas.style.cursor = x >= 285 && x <= 464 && y >= 365 && y <= 445 ? 'pointer' : 'default';
  });
  canvas.addEventListener('click', event => {
    const x = (event.clientX * (window.devicePixelRatio || 1) - view.x) / view.scale;
    const y = (event.clientY * (window.devicePixelRatio || 1) - view.y) / view.scale;
    if (x >= 285 && x <= 464 && y >= 365 && y <= 445) openRecords();
  });
  window.addEventListener('keydown', event => {
    if (finished) return;
    if ([' ', 'Enter', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(event.key)) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (event.key === ' ' || event.key === 'Enter') openRecords();
    }
  }, true);
  window.addEventListener('resize', resize);
  window.tavernMenu = {
    setGameReady() { ready = true; if (requested) openRecords(); },
    setGameFailed() { ready = false; finished = true; canvas.remove(); }
  };
  resize();
  Promise.all([
    Promise.resolve(window.tavernGeometry),
    new FontFace('Upheaval', 'url(tavern_upheavtt.ttf)').load().then(f => document.fonts.add(f))
  ]).then(([commands]) => {
    if (!Array.isArray(commands)) throw new Error('Tavern geometry missing');
    const layers = makeSceneLayers(commands);
    renderFrame(layers, 0);
    let previousFrame = 0;
    function animate(stamp) {
      if (finished) return;
      requestAnimationFrame(animate);
      if (stamp - previousFrame < 1000 / 30) return;
      previousFrame = stamp;
      renderFrame(layers, stamp / 1000);
    }
    requestAnimationFrame(animate);
  }).catch(err => {
    console.error('Tavern scene failed:', err);
    finished = true; canvas.remove();
  });
})();
