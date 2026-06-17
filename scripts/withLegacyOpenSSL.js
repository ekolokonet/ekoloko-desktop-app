"use strict";

const { spawn } = require("child_process");

const [command, ...args] = process.argv.slice(2);

if (!command) {
  console.error("Usage: node scripts/withLegacyOpenSSL.js <command> [...args]");
  process.exit(1);
}

const env = { ...process.env };
const nodeMajor = Number(process.versions.node.split(".")[0]);

if (nodeMajor >= 17) {
  const currentOptions = env.NODE_OPTIONS ? env.NODE_OPTIONS.split(/\s+/) : [];
  if (!currentOptions.includes("--openssl-legacy-provider")) {
    currentOptions.push("--openssl-legacy-provider");
  }
  env.NODE_OPTIONS = currentOptions.filter(Boolean).join(" ");
}

const child = spawn(command, args, {
  env,
  shell: process.platform === "win32",
  stdio: "inherit",
});

child.on("error", (error) => {
  console.error(error.message);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code === null ? 1 : code);
});
