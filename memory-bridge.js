(() => {
  let audioContext;
  const Context = window.AudioContext || window.webkitAudioContext;
  if (Context) {
    const key = window.AudioContext ? 'AudioContext' : 'webkitAudioContext';
    window[key] = class extends Context {
      constructor(...options) {
        super(...options);
        audioContext = this;
      }
    };
  }

  window.tavernNotify = (type, message) => {
    window.parent.postMessage({ type, message }, window.location.origin);
  };

  window.unlockMemoryAudio = () => {
    audioContext?.resume().catch(console.error);
  };

  window.launchMemory = () => {
    window.tavernStart();
  };
})();
