(() => {
  'use strict';

  const canvas = document.getElementById('record-cover');
  const art = canvas?.getContext('2d');
  if (!art) return;

  function rect(x, y, w, h, color) {
    art.fillStyle = color;
    art.fillRect(x, y, w, h);
  }

  function shape(points, color) {
    art.fillStyle = color;
    art.beginPath();
    art.moveTo(...points[0]);
    for (const point of points.slice(1)) art.lineTo(...point);
    art.closePath();
    art.fill();
  }

  function light(x, y, radius, tones) {
    tones.forEach((tone, i) => {
      const r = radius - i * 4;
      shape([[x-r, y-3], [x-r+4, y-3], [x-r+4, y-7], [x+r-4, y-7],
        [x+r-4, y-3], [x+r, y-3], [x+r, y+5], [x-r, y+5]], tone);
    });
  }

  function crystal(x, y, w, h, tones) {
    const tip = x + Math.floor(w * .55);
    const shoulder = y - h + Math.floor(w * .55);
    shape([[x-1, y+1], [x-1, shoulder], [tip, y-h-1], [x+w+1, shoulder], [x+w+1, y+1]], tones[0]);
    shape([[x, y], [x, shoulder], [tip, y-h], [tip, y]], tones[1]);
    shape([[tip, y], [tip, y-h], [x+w, shoulder], [x+w, y]], tones[2]);
    rect(tip - 1, shoulder, 1, Math.max(2, h - w), tones[3]);
  }

  function slime(x, y, tones) {
    const points = [[0,8], [0,5], [2,5], [2,2], [4,2], [4,0], [9,0], [9,1], [11,1],
      [11,3], [13,3], [13,6], [14,6], [14,10], [12,11], [2,11], [0,10]];
    art.save();
    art.translate(x, y);
    shape(points.map(([a, b]) => [a, b+1]), '#21162b');
    shape(points, tones[0]);
    shape([[1,6], [3,2], [8,1], [11,3], [12,7], [11,9], [3,9], [1,8]], tones[1]);
    rect(4, 2, 3, 1, '#fff1d8');
    rect(3, 3, 2, 1, '#fff1d8');
    rect(7, 5, 1, 3, '#22152c');
    rect(10, 5, 1, 3, '#22152c');
    art.restore();
  }

  function ledge(x, y, w, tones) {
    rect(x, y+2, w, 64-y, tones[2]);
    rect(x, y+3, w-3, 7, tones[1]);
    rect(x+2, y+13, w-5, 4, tones[1]);
    shape([[x,y+2], [x+4,y-1], [x+w,y-1], [x+w,y+2]], tones[0]);
  }

  const covers = [
    () => {
      rect(0, 0, 64, 34, '#6b517e');
      rect(0, 26, 64, 13, '#b582a6');
      light(30, 23, 17, ['#a6739e', '#d894aa', '#f6b6a4']);
      shape([[0,0], [64,0], [64,8], [57,8], [53,14], [46,10], [40,7], [18,7], [9,13], [5,10], [0,10]], '#30243f');
      rect(3, 16, 10, 2, '#c6a0bc');
      rect(48, 19, 12, 2, '#d6abcd');
      rect(0, 36, 64, 28, '#4f366d');
      [5, 12, 19, 42, 49, 56].forEach((x, i) => rect(x, 37 - i % 3 * 3, 4, 29, i % 2 ? '#7e5189' : '#9460a7'));
      ledge(0, 53, 17, ['#fce2f7', '#d96ca5', '#842b62']);
      ledge(20, 46, 26, ['#fff0f6', '#e782b5', '#933e74']);
      ledge(53, 52, 11, ['#fce2f7', '#cd5b9f', '#783161']);
      slime(26, 33, ['#c73780', '#ed5897']);
    },
    () => {
      rect(0, 0, 64, 64, '#172e39');
      shape([[0,0], [64,0], [64,17], [58,13], [52,13], [47,20], [44,34], [41,32], [40,20],
        [34,10], [24,10], [19,15], [16,32], [12,34], [11,22], [6,17], [0,20]], '#28575d');
      rect(0, 38, 64, 26, '#1b535c');
      [[2,42,15], [20,46,21], [41,42,21], [8,55,18], [37,51,18], [45,59,17]].forEach(([x,y,w]) =>
        rect(x, y, w, 1, '#3d959e'));
      ledge(22, 49, 23, ['#c6f0e9', '#4b9f98', '#265c60']);
      crystal(6, 39, 9, 20, ['#142f43', '#78e1db', '#318295', '#c4fff2']);
      crystal(15, 42, 5, 11, ['#142f43', '#71c9d2', '#2c6e84', '#c4fff2']);
      crystal(49, 43, 9, 25, ['#142f43', '#69d2d8', '#276e88', '#c4fff2']);
      slime(28, 36, ['#259e91', '#79d7c8']);
    },
    () => {
      rect(0, 0, 64, 64, '#271d3d');
      shape([[0,0], [22,0], [46,18], [64,23], [64,33], [40,25], [12,10], [0,8]], '#5c3672');
      shape([[0,5], [22,12], [39,22], [29,25], [13,18], [0,17]], '#754789');
      shape([[64,30], [37,30], [21,37], [0,38], [0,50], [31,44], [52,37], [64,39]], '#4b2c66');
      const violet = ['#311b48', '#d0a1f9', '#7547a9', '#f4d7ff'];
      crystal(8, 31, 8, 15, violet);
      crystal(16, 32, 5, 10, violet);
      crystal(44, 49, 11, 25, violet);
      crystal(54, 51, 7, 16, violet);
      ledge(0, 56, 56, ['#d8afe3', '#8e5ea7', '#4a2c62']);
      ledge(16, 48, 24, ['#f8dfff', '#b27ec7', '#633b85']);
      slime(21, 35, ['#824dc1', '#b789f5']);
    },
    () => {
      rect(0, 0, 64, 64, '#182943');
      light(38, 21, 17, ['#203551', '#2f4c6b', '#457192']);
      shape([[35,13], [38,13], [38,16], [41,18], [43,18], [43,22], [40,26],
        [35,28], [29,26], [32,24], [35,21], [36,17]], '#d5edff');
      shape([[0,0], [64,0], [64,8], [59,8], [57,19], [53,14], [50,8], [22,7],
        [18,12], [14,10], [7,22], [3,14], [0,14]], '#34547a');
      shape([[0,48], [7,39], [12,44], [20,31], [26,42], [35,49], [40,42], [49,33], [56,43], [64,49], [64,64], [0,64]], '#2c4567');
      ledge(0, 53, 18, ['#cce9ff', '#658dc3', '#38527c']);
      ledge(19, 46, 26, ['#e9f7ff', '#80aade', '#3d5a85']);
      ledge(49, 55, 15, ['#cce9ff', '#658dc3', '#38527c']);
      slime(25, 33, ['#465eae', '#8aa8f6']);
    },
    () => {
      rect(0, 0, 64, 64, '#322033');
      for (const [radius, color] of [[33,'#60303d'], [27,'#78394a'], [21,'#9c5053'], [15,'#bd6e64']]) {
        art.beginPath();
        art.arc(32, 54, radius, Math.PI, 2 * Math.PI);
        art.strokeStyle = color;
        art.lineWidth = 2;
        art.stroke();
      }
      shape([[0,0], [11,0], [11,18], [15,18], [15,30], [22,30], [22,49], [0,55]], '#533044');
      shape([[64,4], [55,4], [55,22], [50,22], [50,33], [44,33], [44,48], [64,54]], '#684052');
      rect(55, 9, 3, 13, '#b56b57');
      rect(7, 14, 2, 13, '#965047');
      [[13,30], [25,24], [38,17], [43,31], [52,29]].forEach(([x,y]) => rect(x, y, 1, 2, '#e99a76'));
      ledge(0, 54, 18, ['#efb1af', '#b35a75', '#71364d']);
      ledge(19, 47, 26, ['#ffd3cc', '#cc6e8b', '#843751']);
      ledge(47, 55, 17, ['#efb1af', '#b35a75', '#71364d']);
      slime(25, 34, ['#b63f72', '#eb779d']);
    }
  ];

  function draw(level) {
    covers[level - 1]?.();
  }

  window.drawRecordCover = draw;
  draw(1);
})();
