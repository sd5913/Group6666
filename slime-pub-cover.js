(() => {
  'use strict';

  const canvas = document.getElementById('home-art');
  const context = canvas.getContext('2d');
  if (!context) return;

  const room = new Image();
  room.src = 'slime-pub-room.png';
  const bartender = fetch('godot/data/bartender.json').then(response => {
    if (!response.ok) throw new Error(`Bartender geometry: HTTP ${response.status}`);
    return response.json();
  });

  function polygon(points) {
    context.beginPath();
    context.moveTo(...points[0]);
    for (const point of points.slice(1)) context.lineTo(...point);
    context.closePath();
  }

  Promise.all([room.decode(), bartender]).then(([, shapes]) => {
    context.imageSmoothingEnabled = false;
    context.drawImage(room, 0, 0);
    context.save();
    // Clip the bartender along the rear edges of the counter and the round tray.
    polygon([[0, 0], [480, 0], [480, 161], [279, 161], [274, 157], [267, 154],
      [256, 152], [245, 151], [234, 151], [222, 152], [212, 155], [205, 158],
      [201, 161], [0, 161]]);
    context.clip();
    context.translate(195, 67);
    context.scale(0.935, 0.935);
    for (const [fill, points] of shapes) {
      polygon(points);
      context.fillStyle = fill;
      context.fill();
    }
    context.restore();
  }).catch(error => console.error('Slime Pub cover could not be drawn.', error));
})();
