"use strict";

// Coalesce failures from the game and toolbar. A native dialog remains usable
// when neither renderer can paint. Never reload an authenticated game silently.
module.exports = function createRecovery({ log, ask, rebuild }) {
  let generation = 0;
  let stopping = false;
  let pending = null;
  return {
    begin() { return ++generation; },
    stop() { stopping = true; },
    async fail(token, source, reason) {
      if (stopping || token !== generation) return false;
      log(`${source}: ${reason}`);
      if (pending) return false;
      pending = Promise.resolve().then(() => ask(source, reason));
      try {
        const retry = await pending;
        if (!stopping && token === generation && retry) {
          // Invalidate old callbacks before destroying their views.
          ++generation;
          rebuild();
          return true;
        }
        return false;
      } finally { pending = null; }
    },
  };
};
