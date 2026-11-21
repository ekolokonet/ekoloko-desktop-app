"use strict";

// The control bar above the game. It runs sandboxed with no Node access: the
// only way out is window.ekolokoControl from preloads/control.js, a fixed set
// of messages the main process checks again on arrival.
(function () {
  const api = window.ekolokoControl;
  if (!api) return;

  const $ = (id) => document.getElementById(id);
  const barEl = document.querySelector(".bar");
  const fullscreenBtn = $("fullscreenBtn");
  const zoom = $("zoom");
  const zoomValue = $("zoomValue");
  const zoomFitBtn = $("zoomFitBtn");
  const volume = $("volume");
  const volumeValue = $("volumeValue");
  const volumeLabel = $("volumeLabel");
  const clearCache = $("clearCache");
  const restartBtn = $("restartBtn");
  const saveLogsBtn = $("saveLogsBtn");
  const darkModeBtn = $("darkModeBtn");
  const presenceBtn = $("presenceBtn");
  const presenceSpacer = $("presenceSpacer");
  const openDiscord = $("openDiscord");
  let dark = false;
  let presenceDetails = false;

  // The bar's height flexes with the window width (CSS clamp()s), so the main
  // process sizes the game view under it from the real laid-out height.
  function reportBarHeight() {
    api.send("control-bar-height", Math.ceil(barEl.getBoundingClientRect().height));
  }
  new ResizeObserver(reportBarHeight).observe(barEl);
  reportBarHeight();

  function formatPercent(value) {
    return Math.round(Number(value) * 100) + "%";
  }

  function setSliderFill(input) {
    const min = parseFloat(input.min) || 0;
    const max = parseFloat(input.max) || 1;
    const pct = ((parseFloat(input.value) - min) / (max - min)) * 100;
    input.style.setProperty("--fill", pct + "%");
  }

  function updateZoomUI(value, fit) {
    zoom.value = value;
    zoomValue.textContent = formatPercent(value);
    setSliderFill(zoom);
    zoomFitBtn.classList.toggle("active", !!fit);
  }

  function updateVolumeUI() {
    const v = Number(volume.value);
    volumeValue.textContent = formatPercent(volume.value);
    setSliderFill(volume);
    volumeLabel.textContent = (v === 0 ? "🔇" : v < 0.5 ? "🔉" : "🔊") + " עוצמת קול";
  }

  function updatePresenceUI() {
    presenceBtn.textContent = presenceDetails ? "🎮 דיסקורד: שם ומיקום" : "🔒 דיסקורד: אנונימי";
  }

  fullscreenBtn.addEventListener("click", () => api.send("toggle-fullscreen"));

  // Dragging the slider is an explicit manual zoom, so it leaves fit mode.
  zoom.addEventListener("input", () => {
    updateZoomUI(zoom.value, false);
    api.send("zoom-change", Number(zoom.value));
  });
  zoomFitBtn.addEventListener("click", () => api.send("zoom-fit"));

  volume.addEventListener("input", () => {
    updateVolumeUI();
    api.send("volume-change", Number(volume.value));
  });

  clearCache.addEventListener("click", () => {
    api.send("clear-cache");
    clearCache.textContent = "✓ נוקה!";
    setTimeout(() => { clearCache.textContent = "🗑️ נקה מטמון"; }, 2000);
  });

  darkModeBtn.addEventListener("click", () => {
    dark = !dark;
    document.body.classList.toggle("dark", dark);
    darkModeBtn.textContent = dark ? "☀️ מצב יום" : "🌙 מצב לילה";
    api.send("dark-mode-toggle", dark);
  });

  restartBtn.addEventListener("click", () => api.send("restart"));

  let savingLogs = false;
  saveLogsBtn.addEventListener("click", () => {
    if (savingLogs) return;
    savingLogs = true;
    saveLogsBtn.textContent = "⏳ שומר...";
    api.send("save-logs");
  });

  openDiscord.addEventListener("click", () => api.send("open-discord"));

  presenceBtn.addEventListener("click", () => {
    presenceDetails = !presenceDetails;
    updatePresenceUI();
    api.send("presence-details-toggle", presenceDetails);
  });

  // The main process owns the zoom: it answers the initial request and pushes
  // a new factor whenever fit mode recomputes (load, resize, fullscreen).
  api.on("zoom-changed", (state) => updateZoomUI(state.zoom, state.fit));
  api.on("fullscreen-changed", (isFull) => {
    fullscreenBtn.textContent = isFull ? "🗗 יציאה ממסך מלא" : "⛶ מסך מלא";
  });
  api.on("save-logs-done", (ok) => {
    savingLogs = false;
    saveLogsBtn.textContent = ok ? "✓ נשמר!" : "✗ שגיאה";
    setTimeout(() => { saveLogsBtn.textContent = "💾 שמירת לוגים"; }, 2500);
  });

  api.init().then((state) => {
    if (!state) return;
    presenceDetails = !!state.presenceShowDetails;
    presenceBtn.hidden = presenceSpacer.hidden = !state.presenceEnabled;
    updatePresenceUI();
    updateZoomUI(state.zoom, state.zoomFit);
    if (state.isFullScreen) fullscreenBtn.textContent = "🗗 יציאה ממסך מלא";
    updateVolumeUI();
    api.send("zoom-request");
  });
})();
