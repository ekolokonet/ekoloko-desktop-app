// Dependency-free logger for the ekoloko desktop app.
//
// Keeps the most recent log lines in memory and appends them to a rolling file
// under userData/logs. The "שמירת לוגים" button reads this back (via
// getExportText) together with the Flash player's flashlog.txt and hands the
// user a single file to send us manually.
//
// Hard rule: logging must NEVER throw. Every fs operation is wrapped so a
// logging failure can never take down the app.

const { app } = require("electron");
const fs = require("fs");
const path = require("path");
const os = require("os");

const MAX_BUFFER = 5000; // lines kept in RAM for instant export
const MAX_FILE_BYTES = 2 * 1024 * 1024; // 2 MB, then rotate to .1

let buffer = [];
let logDir = null;
let logFile = null;
let flashVersion = "unknown";

function ts() {
  return new Date().toISOString();
}

function init(opts) {
  if (opts && opts.flashVersion) flashVersion = opts.flashVersion;
  try {
    logDir = path.join(app.getPath("userData"), "logs");
    fs.mkdirSync(logDir, { recursive: true });
    logFile = path.join(logDir, "ekoloko.log");
  } catch (e) {
    logDir = null;
    logFile = null;
  }
  appendToFile("\n" + metadataHeader() + "\n");
}

function appendToFile(text) {
  if (!logFile) return;
  try {
    let size = 0;
    try {
      size = fs.statSync(logFile).size;
    } catch (e) {
      size = 0;
    }
    if (size > MAX_FILE_BYTES) {
      try {
        fs.renameSync(logFile, logFile + ".1"); // overwrites any previous backup
      } catch (e) {
        /* keep going even if rotation fails */
      }
    }
    fs.appendFileSync(logFile, text);
  } catch (e) {
    /* never throw from logging */
  }
}

function log(level, source, msg) {
  const line = `${ts()} [${level}] [${source}] ${msg}`;
  buffer.push(line);
  if (buffer.length > MAX_BUFFER) buffer.shift();
  appendToFile(line + "\n");
}

function metadataHeader() {
  let appVersion = "?";
  let locale = "?";
  let packaged = "?";
  try {
    appVersion = app.getVersion();
  } catch (e) {}
  try {
    locale = app.getLocale();
  } catch (e) {}
  try {
    packaged = String(app.isPackaged);
  } catch (e) {}
  return [
    "==================== ekoloko log ====================",
    `app version     : ${appVersion}`,
    `electron        : ${process.versions.electron}`,
    `chrome          : ${process.versions.chrome}`,
    `node            : ${process.versions.node}`,
    `flash (declared): ${flashVersion}`,
    `platform/arch   : ${process.platform} ${process.arch}`,
    `os release      : ${os.release()}`,
    `locale          : ${locale}`,
    `packaged        : ${packaged}`,
    `timestamp       : ${ts()}`,
    "=====================================================",
  ].join("\n");
}

// Returns the full persisted log (rotated backup first, then the current file).
// Falls back to the in-memory buffer if the files can't be read.
function getExportText() {
  const chunks = [];
  if (logFile) {
    for (const f of [logFile + ".1", logFile]) {
      try {
        if (fs.existsSync(f)) chunks.push(fs.readFileSync(f, "utf8"));
      } catch (e) {
        /* ignore unreadable file */
      }
    }
  }
  if (chunks.length === 0) {
    return buffer.join("\n") + "\n";
  }
  return chunks.join("\n");
}

module.exports = {
  init,
  metadataHeader,
  getExportText,
  getLogFile: () => logFile,
  getLogDir: () => logDir,
  info: (source, msg) => log("INFO", source, msg),
  warn: (source, msg) => log("WARN", source, msg),
  error: (source, msg) => log("ERROR", source, msg),
};
