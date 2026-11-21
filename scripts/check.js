"use strict";
// Syntax check of every app source file (CI and before packaging).
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const files = [];
(function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    if (fs.statSync(p).isDirectory()) walk(p);
    else if (p.endsWith(".js")) files.push(p);
  }
})(path.join(__dirname, "..", "src"));
for (const f of files) execFileSync(process.execPath, ["--check", f], { stdio: "inherit" });
console.log(`syntax ok: ${files.length} files`);
