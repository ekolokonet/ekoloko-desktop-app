"use strict";

// Keeps the player signed in across the 1.x -> 2.x update.
//
// 1.x (Electron 8 / Chrome 80) kept cookies in <userData>/Cookies, schema
// version 12, values unencrypted. This Chromium no longer migrates a cookie
// database that old: it moves the file to Network/Cookies and starts it empty,
// so every player would be signed out once (measured: a persistent
// play.ekoloko.org cookie written by 1.1.1 was gone in 2.0.0; localStorage
// survived). So, before Chromium touches it: read the old file's persistent,
// unexpired ekoloko.org cookies, move the file aside (Cookies.electron8.bak),
// and after "ready" put them back with session.cookies.set().

const fs = require("fs");
const path = require("path");

const BACKUP_SUFFIX = ".electron8.bak";

function isEkolokoHost(host) {
  const h = String(host || "").replace(/^\./, "").toLowerCase();
  return h === "ekoloko.org" || h.endsWith(".ekoloko.org");
}

// Before "ready". Returns the cookies to restore (possibly empty).
function readLegacyCookies(userData, logger) {
  const oldFile = path.join(userData, "Cookies");
  const newFile = path.join(userData, "Network", "Cookies");
  if (!fs.existsSync(oldFile) || fs.existsSync(newFile)) return [];
  let rows = [];
  try {
    const { DatabaseSync } = require("node:sqlite");
    const db = new DatabaseSync(oldFile, { readOnly: true });
    const meta = db.prepare("SELECT value FROM meta WHERE key = 'version'").get();
    const version = Number(meta && meta.value);
    if (!(version > 0 && version < 16)) {
      db.close();
      return []; // a database this Chromium still migrates itself
    }
    rows = db
      .prepare(
        `SELECT host_key AS host, name, value, path, is_secure AS secure, is_httponly AS httpOnly, samesite,
                CAST(expires_utc / 1000000 - 11644473600 AS INTEGER) AS expires
           FROM cookies
          WHERE is_persistent = 1 AND length(value) > 0`
      )
      .all();
    db.close();
    logger.info("cookies", `found a 1.x cookie database (version ${version}, ${rows.length} persistent cookies)`);
  } catch (e) {
    logger.warn("cookies", `could not read the 1.x cookie database: ${(e && e.message) || e}`);
    return [];
  }
  // Move it aside so this Chromium starts a fresh database (it would empty it
  // anyway); the backup stays for support.
  for (const suffix of ["", "-journal"]) {
    try {
      if (fs.existsSync(oldFile + suffix)) fs.renameSync(oldFile + suffix, oldFile + BACKUP_SUFFIX + suffix);
    } catch (e) {
      logger.warn("cookies", `could not move ${path.basename(oldFile + suffix)}: ${(e && e.message) || e}`);
    }
  }
  const now = Date.now() / 1000;
  return rows.filter((r) => isEkolokoHost(r.host) && Number(r.expires) > now + 60);
}

// After "ready".
async function restoreCookies(ses, cookies, logger) {
  if (!cookies || !cookies.length) return;
  const SAME_SITE = { 0: "no_restriction", 1: "lax", 2: "strict" };
  let ok = 0;
  for (const c of cookies) {
    const host = String(c.host);
    const bare = host.replace(/^\./, "");
    try {
      await ses.cookies.set({
        url: `https://${bare}${c.path || "/"}`,
        name: c.name,
        value: c.value,
        domain: host.startsWith(".") ? host : undefined,
        path: c.path || "/",
        secure: !!c.secure,
        httpOnly: !!c.httpOnly,
        sameSite: SAME_SITE[c.samesite] || "unspecified",
        expirationDate: Number(c.expires),
      });
      ok++;
    } catch (e) {
      logger.warn("cookies", `could not restore cookie ${c.name} for ${host}: ${(e && e.message) || e}`);
    }
  }
  try {
    await ses.cookies.flushStore();
  } catch (e) {
    /* written later anyway */
  }
  logger.info("cookies", `restored ${ok} of ${cookies.length} ekoloko.org cookies from 1.x`);
}

module.exports = { readLegacyCookies, restoreCookies };
