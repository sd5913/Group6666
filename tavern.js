const home = document.querySelector('#home');
const enterTavern = document.querySelector('#enter-tavern');
const bootStatus = document.querySelector('#boot-status');
const tavern = document.querySelector('#tavern');
const conversation = document.querySelector('#conversation');
const dialogue = document.querySelector('#dialogue');
const continueButton = document.querySelector('#continue');
const counterRecord = document.querySelector('#counter-record');
const picker = document.querySelector('#record-picker');
const closePicker = document.querySelector('#close-picker');
const playRecord = document.querySelector('#play-record');
const launchError = document.querySelector('#launch-error');
const game = document.querySelector('#game');
const flash = document.querySelector('#flash');

let pendingMemory;
let artReady = false;
let memoryLoaded = false;

function enableTavern() {
  if (!artReady || !memoryLoaded) return;
  enterTavern.disabled = false;
  bootStatus.textContent = '';
}

tavernArt.ready.then(() => {
  artReady = true;
  enableTavern();
}, (error) => {
  bootStatus.textContent = error.message;
});

window.addEventListener('message', ({ origin, source, data }) => {
  if (origin !== window.location.origin || source !== game.contentWindow) return;
  if (data?.type === 'title-ready') {
    memoryLoaded = true;
    enableTavern();
  }
  if (data?.type === 'title-error') {
    bootStatus.textContent = data.message;
  }
  if (data?.type === 'memory-ready') pendingMemory?.();
});

enterTavern.addEventListener('click', async () => {
  home.hidden = true;
  await playTavernPrologue();
  tavern.hidden = false;
  await tavernArt.arrive();
  conversation.hidden = false;
  continueButton.focus();
});

if (window.location.protocol === 'file:') {
  bootStatus.textContent = 'Open Play_Midi_Runner.cmd to start the local game server.';
} else {
  game.src = 'midi-runner.html';
}

function showRecords() {
  launchError.hidden = true;
  picker.showModal();
}

continueButton.addEventListener('click', () => {
  dialogue.textContent = 'Then a friend got stranded in the Jelly Grotto, and I was the only one who could reach them.';
  continueButton.textContent = 'Choose a record';
  counterRecord.disabled = false;
  continueButton.addEventListener('click', showRecords);
}, { once: true });

counterRecord.addEventListener('click', showRecords);
closePicker.addEventListener('click', () => picker.close());

playRecord.addEventListener('click', async () => {
  playRecord.disabled = true;
  picker.close();
  continueButton.disabled = true;
  counterRecord.disabled = true;
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let timeout;

  try {
    // Unlock WebAudio during the click, then turn the record before starting the level.
    game.contentWindow.unlockMemoryAudio();
    await tavernArt.playRecord();
    const ready = new Promise((resolve) => {
      pendingMemory = () => resolve(true);
      timeout = setTimeout(() => resolve(false), 9000);
    });
    game.contentWindow.launchMemory();
    if (!reducedMotion) {
      flash.hidden = false;
      await flash.animate([{ opacity: 0 }, { opacity: 1 }], {
        duration: 110,
        fill: 'forwards',
      }).finished;
    }

    if (!await ready) {
      launchError.textContent = 'The memory did not open. Reload the game to try again.';
      launchError.hidden = false;
      picker.showModal();
      return;
    }

    tavern.hidden = true;
    game.inert = false;
    game.removeAttribute('aria-hidden');
    game.contentWindow.focus();
    game.contentDocument.querySelector('#canvas').focus();
    if (!reducedMotion) {
      await flash.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 400 }).finished;
    }
  } catch (error) {
    console.error(error);
    launchError.textContent = 'The memory could not start. Reload the game to try again.';
    launchError.hidden = false;
    picker.showModal();
  } finally {
    clearTimeout(timeout);
    pendingMemory = undefined;
    flash.getAnimations().forEach((animation) => animation.cancel());
    flash.hidden = true;
  }
});
