"use strict";

// electron-builder afterPack hook: prune Chromium locale .pak files.
// electron-builder 22.4.1 has no `electronLanguages` option, so we delete the
// unused locale paks from the packaged app. The UI is custom HTML; only the
// app's languages (English + Hebrew) are kept.
const fs = require("fs");
const path = require("path");

const KEEP = new Set(["en-US.pak", "he.pak"]);

exports.default = async function afterPack(context) {
  // Windows/Linux: <appOutDir>/locales ; macOS: inside the .app bundle Resources.
  const candidates = [
    path.join(context.appOutDir, "locales"),
    path.join(
      context.appOutDir,
      `${context.packager.appInfo.productFilename}.app`,
      "Contents",
      "Resources",
      "locales"
    ),
  ];

  let removed = 0;
  let keptHe = false;
  for (const localesDir of candidates) {
    if (!fs.existsSync(localesDir)) continue;
    for (const file of fs.readdirSync(localesDir)) {
      if (!file.endsWith(".pak")) continue;
      if (KEEP.has(file)) {
        if (file === "he.pak") keptHe = true;
        continue;
      }
      fs.unlinkSync(path.join(localesDir, file));
      removed++;
    }
  }
  console.log(
    `  • afterPack: pruned ${removed} locale .pak files (he.pak ${keptHe ? "kept" : "not found"})`
  );
};
