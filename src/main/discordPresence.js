// Minimal Discord Rich Presence client over Discord's local IPC socket.
// Dependency-free on purpose (like logger.js): the maintained RPC packages
// need Node >= 14 while Electron 8 ships Node 12, and the wire protocol is
// tiny — int32-LE opcode + int32-LE length + JSON payload, over a named pipe
// (Windows) or unix socket. Reference: Discord "RPC" local transport as used
// by discord-rpc / @xhayper/discord-rpc.
//
// Behavior:
// - Connects lazily and retries forever with backoff, so it works whether
//   Discord is already running, started mid-session, or never installed
//   (in which case it stays quietly disconnected).
// - setActivity() keeps only the latest activity and flushes it at most once
//   per 15s (Discord's presence rate limit), immediately on (re)connect.

const net = require("net");
const path = require("path");

const OP_HANDSHAKE = 0;
const OP_FRAME = 1;
const OP_CLOSE = 2;
const OP_PING = 3;
const OP_PONG = 4;

const MIN_UPDATE_INTERVAL_MS = 15 * 1000;
const RECONNECT_BACKOFF_MS = [15 * 1000, 30 * 1000, 60 * 1000, 120 * 1000];

let clientId = null;
let log = { info() {}, warn() {}, error() {} };

let socket = null;
let ready = false;
let readBuffer = Buffer.alloc(0);
let reconnectAttempt = 0;
let reconnectTimer = null;
let disposed = false;

let pendingActivity = null; // latest requested activity (or null to clear)
let dirty = false; // pendingActivity changed since last send
let lastSentAt = 0;
let flushTimer = null;

// Discord scans discord-ipc-0..9 in the temp dir; on Linux also inside the
// flatpak/snap private runtime dirs.
function socketCandidates() {
  const paths = [];
  if (process.platform === "win32") {
    for (let i = 0; i < 10; i++) paths.push(`\\\\?\\pipe\\discord-ipc-${i}`);
    return paths;
  }
  const base =
    process.env.XDG_RUNTIME_DIR || process.env.TMPDIR || process.env.TMP || process.env.TEMP || "/tmp";
  const dirs = [
    base,
    path.join(base, "app", "com.discordapp.Discord"),
    path.join(base, "snap.discord"),
    path.join(base, ".flatpak", "com.discordapp.Discord", "xdg-run"),
  ];
  for (const dir of dirs) {
    for (let i = 0; i < 10; i++) paths.push(path.join(dir, `discord-ipc-${i}`));
  }
  return paths;
}

function encode(op, payload) {
  const data = Buffer.from(JSON.stringify(payload), "utf8");
  const packet = Buffer.alloc(8 + data.length);
  packet.writeInt32LE(op, 0);
  packet.writeInt32LE(data.length, 4);
  data.copy(packet, 8);
  return packet;
}

function send(op, payload) {
  if (!socket || socket.destroyed) return;
  try {
    socket.write(encode(op, payload));
  } catch (e) {
    log.warn("discord", `write failed: ${(e && e.message) || e}`);
  }
}

function onData(chunk) {
  readBuffer = Buffer.concat([readBuffer, chunk]);
  while (readBuffer.length >= 8) {
    const op = readBuffer.readInt32LE(0);
    const len = readBuffer.readInt32LE(4);
    if (readBuffer.length < 8 + len) return;
    const body = readBuffer.slice(8, 8 + len);
    readBuffer = readBuffer.slice(8 + len);

    let payload = null;
    try {
      payload = JSON.parse(body.toString("utf8"));
    } catch (e) {
      continue;
    }

    if (op === OP_PING) {
      send(OP_PONG, payload);
      continue;
    }
    if (op === OP_CLOSE) {
      log.warn("discord", `server closed connection: ${JSON.stringify(payload)}`);
      teardownSocket();
      scheduleReconnect();
      return;
    }
    if (op === OP_FRAME && payload) {
      if (payload.evt === "ERROR") {
        // Discord rejected a command (e.g. invalid SET_ACTIVITY payload). When
        // that happens the presence silently stops broadcasting to others, so
        // surface the reason loudly.
        const detail = (payload.data && (payload.data.message || payload.data.code)) || JSON.stringify(payload.data);
        log.error("discord", `RPC ERROR (cmd=${payload.cmd || "?"}): ${detail}`);
      } else if (payload.evt === "READY") {
        ready = true;
        reconnectAttempt = 0;
        log.info("discord", "connected to Discord, rich presence ready");
        // Push whatever the app wants shown as soon as we're ready.
        dirty = true;
        flush();
      } else if (payload.cmd === "SET_ACTIVITY") {
        log.info("discord", "SET_ACTIVITY acknowledged by Discord");
      }
    }
  }
}

function teardownSocket() {
  ready = false;
  readBuffer = Buffer.alloc(0);
  if (socket) {
    socket.removeAllListeners();
    try {
      socket.destroy();
    } catch (e) {
      /* ignore */
    }
    socket = null;
  }
}

function scheduleReconnect() {
  if (disposed || reconnectTimer) return;
  const delay =
    RECONNECT_BACKOFF_MS[Math.min(reconnectAttempt, RECONNECT_BACKOFF_MS.length - 1)];
  reconnectAttempt++;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, delay);
}

function connect(candidateIndex) {
  if (disposed || !clientId) return;
  const candidates = socketCandidates();
  const index = candidateIndex || 0;
  if (index >= candidates.length) {
    // Discord isn't running (or isn't installed). Retry later, quietly.
    scheduleReconnect();
    return;
  }

  teardownSocket();
  const sock = net.createConnection(candidates[index]);
  socket = sock;

  sock.on("connect", () => {
    send(OP_HANDSHAKE, { v: 1, client_id: clientId });
  });
  sock.on("data", onData);
  sock.on("error", () => {
    // This candidate socket doesn't exist / refused; try the next one.
    if (socket === sock) {
      teardownSocket();
      connect(index + 1);
    }
  });
  sock.on("close", () => {
    if (socket === sock) {
      teardownSocket();
      scheduleReconnect();
    }
  });
}

function flush() {
  if (!ready || !dirty) return;
  const now = Date.now();
  const wait = lastSentAt + MIN_UPDATE_INTERVAL_MS - now;
  if (wait > 0) {
    if (!flushTimer) {
      flushTimer = setTimeout(() => {
        flushTimer = null;
        flush();
      }, wait);
    }
    return;
  }
  lastSentAt = now;
  dirty = false;
  send(OP_FRAME, {
    cmd: "SET_ACTIVITY",
    args: { pid: process.pid, activity: pendingActivity },
    nonce: String(now),
  });
  log.info(
    "discord",
    pendingActivity
      ? `SET_ACTIVITY sent: ${pendingActivity.details || ""}${pendingActivity.state ? " | " + pendingActivity.state : ""}`
      : "SET_ACTIVITY sent: <cleared>"
  );
}

module.exports = {
  // Starts the client. A falsy clientId disables the module entirely.
  init(id, appLogger) {
    if (appLogger) log = appLogger;
    if (!id) {
      log.info("discord", "no client id configured; rich presence disabled");
      return;
    }
    clientId = String(id);
    disposed = false;
    connect();
  },

  // activity: https://discord.com/developers/docs/rich-presence (SET_ACTIVITY
  // args.activity shape) or null to clear. Only the latest value is kept.
  setActivity(activity) {
    pendingActivity = activity || null;
    dirty = true;
    flush();
  },

  clearActivity() {
    this.setActivity(null);
  },

  isConnected() {
    return ready;
  },

  dispose() {
    disposed = true;
    if (reconnectTimer) {
      clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    if (flushTimer) {
      clearTimeout(flushTimer);
      flushTimer = null;
    }
    // Best-effort: clear the presence so it doesn't linger after quit.
    if (ready) {
      send(OP_FRAME, {
        cmd: "SET_ACTIVITY",
        args: { pid: process.pid, activity: null },
        nonce: `dispose-${Date.now()}`,
      });
    }
    teardownSocket();
  },
};
