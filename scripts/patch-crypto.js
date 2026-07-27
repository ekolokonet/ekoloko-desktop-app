const crypto = require("crypto");

try {
  const origCreateHash = crypto.createHash;
  crypto.createHash = function (algorithm, options) {
    if (algorithm === "md4") {
      algorithm = "sha256";
    }
    return origCreateHash.call(crypto, algorithm, options);
  };
} catch (e) {
  // ignore
}
