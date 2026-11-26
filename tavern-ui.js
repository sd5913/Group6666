/* The backup's home, story and record controls around the current Godot art. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const home = $('home');
  const enter = $('enter-tavern');
  const status = $('boot-status');
  const prologue = $('prologue');
  const skip = $('skip-intro');
  const caption = $('intro-caption');
  const tavern = $('tavern');
  const conversation = $('conversation');
  const dialogue = $('dialogue');
  const next = $('continue');
  const turntable = $('counter-record');
  const picker = $('record-picker');
  const close = $('close-picker');
  const play = $('play-record');
  const error = $('launch-error');
  const game = $('game');
  let gameReady = false;
  let hasEntered = false;
  let hasLaunched = false;
  let storyStep = 0;
  let nextLevel = 1;
  const previewAfterLevel = Number(new URLSearchParams(location.search).get('previewAfterLevel'));

  const story = [
    'At my bar, every guest picks a favorite record.',
    'I set it spinning and let the music tell a story.',
    'Where will this one take us?'
  ];

  function showTavern(returning = false) {
    document.body.classList.remove('playing', 'prologue-active');
    game.inert = true;
    game.setAttribute('aria-hidden', 'true');
    home.hidden = true;
    prologue.hidden = true;
    tavern.hidden = false;
    if (returning || storyStep >= 2) {
      conversation.hidden = true;
      turntable.disabled = false;
    } else {
      conversation.hidden = false;
      turntable.disabled = true;
      next.focus();
    }
  }

  function updateRecord(info) {
    const level = Number(info.nextLevel);
    nextLevel = Number.isInteger(level) && level >= 1 && level <= 5 ? level : 1;
    $('record-title').textContent = nextLevel === 1 ? 'The Jelly Grotto' : `Record ${nextLevel}`;
    $('record-level').textContent = `Level ${nextLevel}`;
    window.drawRecordCover?.(nextLevel);
  }

  window.addEventListener('message', event => {
    if (event.origin !== location.origin || event.source !== game.contentWindow) return;
    if (event.data?.type === 'tavern-ready') {
      gameReady = true;
      enter.disabled = false;
      status.textContent = '';
      updateRecord(event.data);
      if (!hasEntered && Number.isInteger(previewAfterLevel) && previewAfterLevel >= 1 && previewAfterLevel <= 5) {
        hasEntered = true;
        hasLaunched = true;
        storyStep = 2;
      }
      if (hasEntered && hasLaunched) showTavern(true);
    } else if (event.data?.type === 'game-error') {
      status.textContent = event.data.message || 'The game could not load.';
      error.textContent = status.textContent;
      error.hidden = false;
    }
  });

  function playPrologue() {
    prologue.hidden = false;
    document.body.classList.add('prologue-active');
    skip.focus();
    const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
    const duration = reduced ? 1200 : 7500;
    const start = performance.now();
    return new Promise(resolve => {
      let frame = 0;
      function finish() {
        cancelAnimationFrame(frame);
        skip.removeEventListener('click', finish);
        prologue.hidden = true;
        document.body.classList.remove('prologue-active');
        resolve();
      }
      function tick(now) {
        const progress = Math.min((now - start) / duration, 1);
        caption.textContent = story[Math.min(2, Math.floor(progress * 3))];
        if (progress >= 1) finish();
        else frame = requestAnimationFrame(tick);
      }
      skip.addEventListener('click', finish, { once: true });
      tick(start);
    });
  }

  enter.addEventListener('click', async () => {
    if (!gameReady || hasEntered) return;
    hasEntered = true;
    home.hidden = true;
    await playPrologue();
    showTavern();
  });

  function showRecords() {
    if (!gameReady || picker.open) return;
    error.hidden = true;
    picker.showModal();
  }

  next.addEventListener('click', () => {
    if (storyStep === 0) {
      dialogue.textContent = 'Then a friend got stranded in the Jelly Grotto, and I was the only one who could reach them.';
      next.textContent = 'Choose a record ▸';
      turntable.disabled = false;
      storyStep = 1;
    } else {
      storyStep = 2;
      showRecords();
    }
  });
  turntable.addEventListener('click', showRecords);
  close.addEventListener('click', () => picker.close());

  play.addEventListener('click', () => {
    if (!gameReady || typeof game.contentWindow.openTavernRecords !== 'function') {
      error.textContent = 'The record player is still loading.';
      error.hidden = false;
      return;
    }
    play.disabled = true;
    picker.close();
    try {
      game.contentWindow.openTavernRecords();
      hasLaunched = true;
      tavern.hidden = true;
      document.body.classList.add('playing');
      game.inert = false;
      game.removeAttribute('aria-hidden');
      game.contentWindow.focus();
      const canvas = game.contentDocument?.getElementById('canvas');
      canvas?.focus();
    } catch (cause) {
      console.error(cause);
      showTavern(true);
      error.textContent = 'The record could not start. Please try again.';
      error.hidden = false;
      picker.showModal();
    } finally {
      play.disabled = false;
    }
  });

  if (location.protocol === 'file:') {
    status.textContent = 'Open Play_Midi_Runner.cmd to start the local game server.';
  } else {
    setTimeout(() => {
      if (!gameReady) status.textContent = 'The game is taking longer to load. Please refresh this page.';
    }, 30000);
  }
})();
